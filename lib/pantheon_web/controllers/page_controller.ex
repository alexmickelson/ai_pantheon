defmodule PantheonWeb.PageController do
  use PantheonWeb, :controller

  def home(conn, _params) do
    current_user = get_session_user(conn)
    current_scope = if current_user, do: %{email: current_user.email}, else: nil

    render(conn, :home, current_user: current_user, current_scope: current_scope)
  end

  defp get_session_user(conn) do
    with user_id when not is_nil(user_id) <- get_session(conn, "current_user_id"),
         %{} = claims <- get_session(conn, "oidc_claims") do
      %{id: user_id, email: Map.get(claims, "email", user_id)}
    else
      _ -> nil
    end
  end
end
