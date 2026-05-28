defmodule Pantheon.AIProviders.OpenAICompatible do
  @moduledoc """
  HTTP client for OpenAI-compatible API endpoints.
  Supports fetching available models from a provider.
  """

  require Logger

  @type model :: %{
          id: String.t(),
          object: String.t() | nil,
          created: integer() | nil,
          owned_by: String.t() | nil
        }

  @spec fetch_models(String.t(), String.t()) :: {:ok, [model]} | {:error, String.t()}
  def fetch_models(base_url, auth_token) do
    url = models_url(base_url)

    headers = [
      {"Authorization", "Bearer #{auth_token}"},
      {"Content-Type", "application/json"}
    ]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: %{"data" => models}}} when is_list(models) ->
        normalized = Enum.map(models, &%{id: &1["id"]})
        {:ok, normalized}

      {:ok, %{status: status, body: body}} ->
        Logger.warning(
          "Failed to fetch models from API endpoint at #{url}: status #{status} response #{inspect(body)}"
        )

        {:error, "API returned status #{status} when fetching available models"}

      {:error, %Mint.TransportError{reason: reason}} ->
        msg = "Connection failed while reaching API endpoint: #{Exception.message(reason)}"
        Logger.warning(msg)
        {:error, msg}

      {:error, exception} ->
        msg = "Request to API endpoint failed: #{Exception.message(exception)}"
        Logger.warning(msg)
        {:error, msg}
    end
  end

  @doc false
  @spec models_url(String.t()) :: String.t()
  def models_url(base_url) do
    build_url(base_url, "/v1/models")
  end

  defp build_url(base, path) do
    base = String.trim_trailing(base, "/")
    "#{base}#{path}"
  end
end
