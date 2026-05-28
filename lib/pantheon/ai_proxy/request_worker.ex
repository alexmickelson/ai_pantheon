defmodule Pantheon.AiProxy.RequestWorker do
  require Logger

  alias Pantheon.AiProxy.CompletionMetrics

  @stream_timeout 30_000

  @type request_data :: %{
          user_id: binary() | nil,
          provider: map(),
          path: String.t(),
          body: map()
        }

  @spec run(request_data(), pid()) :: :ok
  def run(
        %{user_id: user_id, provider: provider, path: path, body: body} = _request_data,
        client_pid
      ) do
    start_time = System.monotonic_time(:millisecond)

    base_url = String.trim_trailing(provider.endpoint, "/")
    url = build_url(base_url, path, body)

    headers = [
      {"Authorization", "Bearer #{provider.auth_token}"},
      {"Content-Type", "application/json"},
      {"Accept", "text/event-stream"}
    ]

    model = Map.get(body, "model", "")

    case Req.post(url, headers: headers, json: body, into: :self) do
      {:ok, %Req.Response{status: 200} = resp} ->
        send(client_pid, {:proxy_stream_init, 200})
        final_chunks = stream_loop(resp, client_pid, [])
        elapsed = System.monotonic_time(:millisecond) - start_time

        metrics =
          CompletionMetrics.from_stream(
            user_id,
            Map.get(provider, :id),
            model,
            200,
            elapsed,
            final_chunks
          )

        send(client_pid, {:proxy_stream_done})
        report(metrics)
        :ok

      {:ok, %Req.Response{status: status, body: resp_body}}
      when is_map(resp_body) and status >= 400 ->
        send(client_pid, {:proxy_stream_init, status})
        elapsed = System.monotonic_time(:millisecond) - start_time
        error_detail = Map.get(resp_body, "detail", to_string(resp_body))

        metrics =
          CompletionMetrics.from_error(
            user_id,
            Map.get(provider, :id),
            model,
            status,
            elapsed,
            error_detail
          )

        send(client_pid, {:proxy_stream_error, error_detail})
        report(metrics)
        :ok

      {:error, reason} ->
        send(client_pid, {:proxy_stream_error, Exception.message(reason)})
        elapsed = System.monotonic_time(:millisecond) - start_time

        metrics =
          CompletionMetrics.from_error(
            user_id,
            Map.get(provider, :id),
            model,
            nil,
            elapsed,
            to_string(reason)
          )

        report(metrics)
        :ok
    end
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
    after
      @stream_timeout ->
        Req.cancel_async_response(resp)
        Logger.warning("Timeout waiting for stream response from provider endpoint")

        send(
          client_pid,
          {:proxy_stream_error, "Provider endpoint did not respond within timeout"}
        )

        final_chunks
    end
  end

  defp accumulate_final(chunk, chunks) when is_binary(chunk) do
    trimmed = String.trim_leading(chunk, "data: ")
    trimmed = String.trim_trailing(trimmed)

    if trimmed == "[DONE]" do
      chunks
    else
      case Jason.decode(trimmed) do
        {:ok, _} -> chunks ++ [trimmed]
        {:error, _} -> chunks
      end
    end
  end

  defp accumulate_final(_chunk, chunks), do: chunks

  defp report(%CompletionMetrics{} = metrics) do
    db_attrs = CompletionMetrics.to_db_map(metrics)
    Task.start(fn -> Pantheon.Data.CompletionMetricsDB.insert(db_attrs) end)
  end

  defp build_url(base, path, body) do
    query = if Map.get(body, "stream", false), do: "?stream=true", else: ""
    "#{base}#{path}#{query}"
  end
end
