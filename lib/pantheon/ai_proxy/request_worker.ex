defmodule Pantheon.AiProxy.RequestWorker do
  require Logger

  alias Pantheon.AiProxy.CompletionMetrics

  @type request_data :: %{
          user_id: binary() | nil,
          api_key_id: binary() | nil,
          provider: map(),
          path: String.t(),
          body: map()
        }

  @spec run(request_data(), pid()) :: :ok
  def run(request_data, client_pid) do
    start_time = System.monotonic_time(:millisecond)
    streaming? = Map.get(request_data.body, "stream", false)

    if streaming? do
      do_stream(request_data, client_pid, start_time)
    else
      do_request(request_data, client_pid, start_time)
    end
  end

  defp do_stream(
         %{user_id: user_id, api_key_id: api_key_id, provider: provider, path: path, body: body} =
           _request_data,
         client_pid,
         start_time
       ) do
    base_url = String.trim_trailing(provider.endpoint, "/")
    model = Map.get(body, "model", "")

    body = inject_stream_options(body)

    headers = [
      {"Authorization", "Bearer #{provider.auth_token}"},
      {"Content-Type", "application/json"},
      {"Accept", "text/event-stream"}
    ]

    url = build_url(base_url, path, body)

    case Req.post(url: url, headers: headers, json: body, into: :self) do
      {:ok, %Req.Response{status: 200} = resp} ->
        send(client_pid, {:proxy_stream_init, 200})
        final_chunks = stream_loop(resp, client_pid, [])
        elapsed_ms = System.monotonic_time(:millisecond) - start_time

        metrics =
          CompletionMetrics.from_stream(
            user_id,
            api_key_id,
            Map.get(provider, :id),
            model,
            200,
            elapsed_ms,
            final_chunks
          )

        send(client_pid, {:proxy_stream_done})
        report(metrics)
        :ok

      {:ok, %Req.Response{status: status, body: resp_body}}
      when is_map(resp_body) and not is_struct(resp_body) and status >= 400 ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        error_detail = Map.get(resp_body, "detail", inspect(resp_body))

        metrics =
          CompletionMetrics.from_error(
            user_id,
            api_key_id,
            Map.get(provider, :id),
            model,
            status,
            elapsed,
            error_detail
          )

        send(client_pid, {:proxy_stream_init, status})
        send(client_pid, {:proxy_stream_error, error_detail})
        report(metrics)
        :ok

      {:ok, %Req.Response{status: status}} when status >= 400 ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        error_msg = "Provider returned HTTP #{status}"

        metrics =
          CompletionMetrics.from_error(
            user_id,
            api_key_id,
            Map.get(provider, :id),
            model,
            status,
            elapsed,
            error_msg
          )

        send(client_pid, {:proxy_stream_init, status})
        send(client_pid, {:proxy_stream_error, error_msg})
        report(metrics)
        :ok

      {:error, reason} ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        error_msg = Exception.message(reason)

        metrics =
          CompletionMetrics.from_error(
            user_id,
            api_key_id,
            Map.get(provider, :id),
            model,
            nil,
            elapsed,
            error_msg
          )

        send(client_pid, {:proxy_stream_error, error_msg})
        report(metrics)
        :ok
    end
  end

  defp do_request(
         %{user_id: user_id, api_key_id: api_key_id, provider: provider, path: path, body: body} =
           _request_data,
         client_pid,
         start_time
       ) do
    base_url = String.trim_trailing(provider.endpoint, "/")
    model = Map.get(body, "model", "")
    url = "#{base_url}#{path}"

    headers = [
      {"Authorization", "Bearer #{provider.auth_token}"},
      {"Content-Type", "application/json"}
    ]

    case Req.post(url: url, headers: headers, json: body) do
      {:ok, %Req.Response{status: status, body: resp_body}}
      when is_map(resp_body) and not is_struct(resp_body) ->
        elapsed_ms = System.monotonic_time(:millisecond) - start_time

        metrics =
          if status >= 400 do
            error_detail = Map.get(resp_body, "detail", inspect(resp_body))

            CompletionMetrics.from_error(
              user_id,
              api_key_id,
              Map.get(provider, :id),
              model,
              status,
              elapsed_ms,
              error_detail
            )
          else
            CompletionMetrics.from_response(
              user_id,
              api_key_id,
              Map.get(provider, :id),
              model,
              status,
              elapsed_ms,
              resp_body
            )
          end

        send(client_pid, {:proxy_response, status, resp_body})
        report(metrics)
        :ok

      {:ok, %Req.Response{status: status}} when status >= 400 ->
        elapsed_ms = System.monotonic_time(:millisecond) - start_time
        error_msg = "Provider returned HTTP #{status}"

        metrics =
          CompletionMetrics.from_error(
            user_id,
            api_key_id,
            Map.get(provider, :id),
            model,
            status,
            elapsed_ms,
            error_msg
          )

        send(
          client_pid,
          {:proxy_response, status, %{error: %{message: error_msg, type: "api_error"}}}
        )

        report(metrics)
        :ok

      {:error, reason} ->
        elapsed_ms = System.monotonic_time(:millisecond) - start_time
        error_msg = Exception.message(reason)

        metrics =
          CompletionMetrics.from_error(
            user_id,
            api_key_id,
            Map.get(provider, :id),
            model,
            nil,
            elapsed_ms,
            error_msg
          )

        send(
          client_pid,
          {:proxy_response, 503, %{error: %{message: error_msg, type: "api_error"}}}
        )

        report(metrics)
        :ok
    end
  end

  defp inject_stream_options(body) do
    existing_opts = Map.get(body, "stream_options", %{})
    Map.put(body, "stream_options", Map.merge(%{"include_usage" => true}, existing_opts))
  end

  defp stream_loop(resp, client_pid, final_chunks) do
    receive do
      message ->
        case Req.parse_message(resp, message) do
          {:ok, [data: chunk]} ->
            send(client_pid, {:proxy_stream_chunk, chunk})
            new_final = accumulate_final(chunk, final_chunks)
            stream_loop(resp, client_pid, new_final)

          {:ok, [:done]} ->
            Logger.debug("Stream done: collected #{length(final_chunks)} chunks for metrics")
            final_chunks

          {:ok, [trailers: _trailers]} ->
            stream_loop(resp, client_pid, final_chunks)

          {:error, reason} ->
            Logger.warning(
              "Stream error proxying request to provider endpoint: #{Exception.message(reason)}"
            )

            send(client_pid, {:proxy_stream_error, Exception.message(reason)})
            final_chunks

          :unknown ->
            stream_loop(resp, client_pid, final_chunks)
        end
    end
  end

  defp accumulate_final(chunk, chunks) when is_binary(chunk) do
    segments = String.split(chunk, "\n\n", trim: true)

    Enum.reduce(segments, chunks, fn segment, acc ->
      trimmed =
        segment
        |> String.trim_leading("data: ")
        |> String.trim_trailing()

      if trimmed == "[DONE]" do
        Logger.debug("Discarding [DONE] chunk")
        acc
      else
        case Jason.decode(trimmed) do
          {:ok, _parsed} ->
            acc ++ [trimmed]

          {:error, reason} ->
            Logger.warning("Failed to decode accumulated chunk: #{inspect(reason)}")
            acc
        end
      end
    end)
  end

  defp accumulate_final(_chunk, chunks), do: chunks

  defp report(%CompletionMetrics{} = metrics) do
    Logger.debug("Reporting completion metrics: #{inspect(metrics)}")
    Pantheon.Data.CompletionMetricsDB.insert(metrics)
  end

  defp build_url(base, path, body) do
    query = if Map.get(body, "stream", false), do: "?stream=true", else: ""
    "#{base}#{path}#{query}"
  end
end
