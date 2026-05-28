defmodule PantheonWeb.Proxy.AuthPlug do
  @moduledoc """
  API key authentication plug for the /v1 proxy endpoints.

  Validates the `Authorization: Bearer <api_key>` header against
  user-provisioned keys stored in the database.
  """

  import Plug.Conn

  @spec init(any()) :: any()
  def init(_opts), do: nil

  @spec call(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case find_header(conn.req_headers, "authorization") do
      nil ->
        unauthorized(conn, "Missing API key")

      "Bearer " <> key ->
        validate(conn, key)

      _ ->
        unauthorized(conn, "Invalid authorization header format — use Bearer token")
    end
  end

  defp validate(conn, key) do
    case Pantheon.UserApiKeys.validate_key(key) do
      {:ok, user_id} ->
        assign(conn, :current_api_key_user_id, user_id)

      {:error, :key_expired} ->
        unauthorized(conn, "API key has expired")

      {:error, :db_error} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          503,
          Jason.encode!(%{
            error: %{message: "Service temporarily unavailable", type: "service_unavailable"}
          })
        )
        |> halt()

      {:error, _reason} ->
        unauthorized(conn, "Invalid API key")
    end
  end

  defp find_header(headers, name) do
    Enum.find_value(headers, fn
      {^name, value} -> value
      _ -> nil
    end)
  end

  defp unauthorized(conn, reason) do
    body = Jason.encode!(%{error: %{message: reason, type: "auth_error"}})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, body)
    |> halt()
  end
end
