defmodule PantheonWeb.Proxy.V1Controller do
  use PantheonWeb, :controller

  require Logger

  @stream_done_timeout 30_000

  def list_models(conn, _params) do
    providers = Pantheon.AIProviders.list()

    models =
      providers
      |> Enum.flat_map(fn provider ->
        Enum.map(provider.models || [], fn model_id ->
          %{
            id: model_id,
            object: "model",
            created: 0,
            owned_by: provider.name
          }
        end)
      end)
      |> Enum.uniq_by(& &1.id)

    json(conn, %{data: models, object: "list"})
  end

  def create_completion(conn, params) do
    model = get_in(params, ["model"])

    case model do
      nil ->
        error_body =
          Jason.encode!(%{
            error: %{message: "Missing required field: model", type: "invalid_request_error"}
          })

        conn |> send_resp(400, error_body)

      "" ->
        error_body =
          Jason.encode!(%{
            error: %{message: "Missing required field: model", type: "invalid_request_error"}
          })

        conn |> send_resp(400, error_body)

      model ->
        provider = find_provider_for_model(model)

        case provider do
          nil ->
            error_body =
              Jason.encode!(%{
                error: %{message: "Model not found: #{model}", type: "invalid_request_error"}
              })

            conn |> send_resp(404, error_body)

          provider ->
            stream_completion(conn, provider, params)
        end
    end
  end

  defp find_provider_for_model(model_id) do
    providers = Pantheon.AIProviders.list()

    Enum.find(providers, fn provider ->
      models = provider.models || []
      model_id in models
    end)
  end

  defp stream_completion(conn, provider, body_params) do
    conn
    |> put_resp_header("content-type", "text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("connection", "keep-alive")
    |> send_chunked(200)
    |> then(&stream_loop(&1, provider, body_params))
  end

  defp stream_loop(conn, provider, body_params) do
    request_data = %{
      provider: %{
        endpoint: provider.endpoint,
        auth_token: provider.auth_token
      },
      path: "/v1/chat/completions",
      body: body_params
    }

    Pantheon.AiProxy.Router.dispatch(request_data, self())

    receive do
      {:proxy_stream_init, 200} ->
        stream_loop(conn)

      {:proxy_stream_init, status} when status >= 400 ->
        conn |> send_resp(status, "")

      {:proxy_stream_init, 503} ->
        stream_loop(conn)
    after
      @stream_done_timeout ->
        Logger.warning("Timeout waiting for proxy stream initialization")

        error_json =
          Jason.encode!(%{error: %{message: "Proxy initialization timeout", type: "api_error"}})

        chunk(conn, "data: #{error_json}\n\n")
        chunk(conn, "data: [DONE]\n\n")
        conn
    end
  end

  defp stream_loop(conn) do
    receive do
      {:proxy_stream_chunk, data} ->
        chunk(conn, data)
        stream_loop(conn)

      {:proxy_stream_done} ->
        chunk(conn, "data: [DONE]\n\n")
        conn

      {:proxy_stream_error, message} ->
        error_json = Jason.encode!(%{error: %{message: message, type: "api_error"}})
        chunk(conn, "data: #{error_json}\n\n")
        chunk(conn, "data: [DONE]\n\n")
        conn
    after
      @stream_done_timeout ->
        Logger.warning("Timeout waiting for proxy stream data from provider")
        chunk(conn, "data: [DONE]\n\n")
        conn
    end
  end
end
