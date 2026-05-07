defmodule PantheonWeb.PageController do
  use PantheonWeb, :controller

  def home(conn, _params) do
    current_user = get_session_user(conn)
    render(conn, :home, current_user: current_user)
  end

  defp get_session_user(conn) do
    with email when not is_nil(email) <- get_session(conn, "current_user_id"),
         %{} = claims <- get_session(conn, "oidc_claims") do
      %{id: email, email: Map.get(claims, "email", email)}
    else
      _ -> nil
    end
  end
end
