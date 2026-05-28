defmodule PantheonWeb.Plugs.RefreshToken do
  @moduledoc """
  Plug that validates the OIDC access token expiry on each HTTP request.

  If the access token has expired and a refresh token is available, it attempts
  to exchange it for a new access token using the OIDC provider. On success the
  session is updated in-place. On failure (or when no refresh token exists) the
  session is cleared so downstream auth guards redirect the user to login.

  Auth routes (/auth/*) are skipped so that the login flow itself is not
  interrupted.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3]
  require Logger

  def init(opts), do: opts

  def call(%{request_path: "/auth/" <> _} = conn, _opts), do: conn

  def call(conn, _opts) do
    with current_user_id when not is_nil(current_user_id) <- get_session(conn, "current_user_id"),
         expires_at when is_integer(expires_at) <- get_session(conn, "token_expires_at"),
         true <- System.system_time(:second) >= expires_at do
      attempt_refresh(conn)
    else
      _ -> conn
    end
  end

  defp attempt_refresh(conn) do
    refresh_token = get_session(conn, "refresh_token")
    oidc_sub = get_session(conn, "oidc_sub")

    if is_binary(refresh_token) and is_binary(oidc_sub) do
      oidc_config = Application.fetch_env!(:pantheon, :oidc)
      client_id = Keyword.fetch!(oidc_config, :client_id)

      case Oidcc.refresh_token(
             refresh_token,
             Pantheon.OidcProvider,
             client_id,
             :unauthenticated,
             %{expected_subject: oidc_sub}
           ) do
        {:ok, new_token} ->
          Logger.info("Refreshed OIDC access token for sub=#{oidc_sub}")

          new_expires_at =
            case new_token.access do
              %{expires: exp} when is_integer(exp) -> exp
              _ -> nil
            end

          new_refresh_token =
            case new_token.refresh do
              %Oidcc.Token.Refresh{token: rt} -> rt
            end

          conn
          |> put_session("token_expires_at", new_expires_at)
          |> put_session("refresh_token", new_refresh_token)

        {:error, reason} ->
          Logger.warning(
            "Could not silently refresh OIDC access token on page request, dropping session: #{inspect(reason)}"
          )

          drop_session(conn)
      end
    else
      Logger.info(
        "Access token expired on page request with no refresh token available, dropping session"
      )

      drop_session(conn)
    end
  end

  defp drop_session(conn) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:error, "Session expired. Please log in again.")
  end
end
