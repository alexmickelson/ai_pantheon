defmodule PantheonWeb.Proxy.V1Controller do
  use PantheonWeb, :controller

  require Logger

  # @stream_done_timeout 30_000

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
            owned_by: provider.name,
            permission: [
              %{
                id: "#{provider.id}_perm_#{model_id}",
                object: "model_permission",
                created: 0,
                allow_create_engine: false,
                allow_sampling: true,
                allow_logprobs: true,
                allow_search_indices: false,
                allow_view: true,
                allow_fine_tuning: false,
                organization: "*",
                group: nil,
                is_blocking: false
              }
            ],
            root: model_id,
            parent: nil
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

  def unknown_path(conn, _params) do
    Logger.warning(
      "Unrecognized proxy endpoint requested: method=#{conn.method} path=#{conn.request_path} peer=#{conn.remote_ip |> Tuple.to_list() |> Enum.join(".")}"
    )

    error_body =
      Jason.encode!(%{
        error: %{
          message:
            "The /v1/#{conn.path_info |> Enum.join("/")} endpoint does not exist or is not implemented",
          type: "not_found_error"
        }
      })

    conn |> send_resp(404, error_body)
  end

  defp find_provider_for_model(model_id) do
    providers = Pantheon.AIProviders.list()

    Enum.find(providers, fn provider ->
      models = provider.models || []
      model_id in models
    end)
  end

  @spec stream_completion(Plug.Conn.t(), map(), map()) :: no_return()
  defp stream_completion(conn, provider, body_params) do
    streaming? = Map.get(body_params, "stream", false)

    if streaming? do
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> send_chunked(200)
      |> then(&dispatch_and_stream(&1, provider, body_params))
    else
      dispatch_and_respond(conn, provider, body_params)
    end
  end

  @spec dispatch_and_stream(Plug.Conn.t(), map(), map()) :: no_return()
  defp dispatch_and_stream(conn, provider, body_params) do
    request_data = request_data(conn, provider, body_params)

    Pantheon.AiProxy.Router.dispatch(request_data, self())

    receive do
      {:proxy_stream_init, 200} ->
        stream_loop(conn)

      {:proxy_stream_init, status} when status >= 400 ->
        error_json =
          Jason.encode!(%{error: %{message: "Provider returned #{status}", type: "api_error"}})

        Logger.warning("Provider returned #{status} for streaming request: #{error_json}")
        Logger.warning("#{inspect(request_data, pretty: true, limit: :infinity)}")

        chunk(conn, "data: #{error_json}\n\n")
        chunk(conn, "data: [DONE]\n\n")
        conn

      {:proxy_stream_init, 503} ->
        error_json = Jason.encode!(%{error: %{message: "Proxy unavailable", type: "api_error"}})
        chunk(conn, "data: #{error_json}\n\n")
        chunk(conn, "data: [DONE]\n\n")
        conn
    end
  end

  @spec dispatch_and_respond(Plug.Conn.t(), map(), map()) :: Plug.Conn.t()
  defp dispatch_and_respond(conn, provider, body_params) do
    request_data = request_data(conn, provider, body_params)

    Pantheon.AiProxy.Router.dispatch(request_data, self())

    receive do
      {:proxy_response, status, body} ->
        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(status, Jason.encode!(body))
    end
  end

  defp request_data(conn, provider, body_params) do
    %{
      user_id: conn.assigns.current_api_key_user_id,
      api_key_id: conn.assigns.current_api_key_id,
      provider: %{
        id: provider.id,
        endpoint: provider.endpoint,
        auth_token: provider.auth_token
      },
      path: "/v1/chat/completions",
      body: body_params
    }
  end

  @spec stream_loop(Plug.Conn.t()) :: no_return()
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
    end
  end
end
