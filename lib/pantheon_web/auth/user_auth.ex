defmodule PantheonWeb.UserAuth do
  import Phoenix.LiveView, only: [connected?: 1, redirect: 2]
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView.Utils, only: [put_flash: 3, push_event: 4]
  import Phoenix.LiveView.Lifecycle, only: [attach_hook: 4]
  require Logger

  @refresh_before_seconds 60

  def on_mount(:ensure_authenticated, _params, session, socket) do
    case fetch_current_user(session) do
      {:ok, user_info} ->
        socket =
          socket
          |> assign(:current_user, user_info)
          |> schedule_session_refresh(session)
          |> attach_hook(:track_current_path, :handle_params, fn _params, url, socket ->
            %{path: path} = URI.parse(url)
            {:cont, assign(socket, :current_path, path)}
          end)

        {:cont, socket}

      :error ->
        socket =
          socket
          |> put_flash(:error, "Your session has expired. Please log in again.")
          |> redirect(to: "/auth/logout")

        {:halt, socket}
    end
  end

  def on_mount(:optional_auth, _params, session, socket) do
    user_info =
      case fetch_current_user(session) do
        {:ok, info} -> info
        :error -> nil
      end

    {:cont, assign(socket, :current_user, user_info)}
  end

  defp fetch_current_user(session) do
    if session_expired?(session) do
      :error
    else
      email = session["current_user_id"]

      case email do
        nil -> :error
        _ -> {:ok, %{id: email, email: email}}
      end
    end
  end

  defp session_expired?(%{"session_expires_at" => exp}) when is_integer(exp) do
    System.system_time(:second) >= exp
  end

  defp session_expired?(_), do: false

  defp schedule_session_refresh(socket, %{"session_expires_at" => exp}) when is_integer(exp) do
    now = System.system_time(:second)
    refresh_at_ms = max((exp - @refresh_before_seconds - now) * 1000, 0)

    if connected?(socket) do
      Logger.info("Scheduling session refresh in #{refresh_at_ms}ms")
      Process.send_after(self(), :session_refresh_soon, refresh_at_ms)
    end

    socket
    |> attach_hook(:session_refresh_info, :handle_info, fn
      :session_refresh_soon, socket ->
        {:halt, push_event(socket, "session_refresh", %{}, [])}

      _other, socket ->
        {:cont, socket}
    end)
    |> attach_hook(:session_refresh_event, :handle_event, fn
      "session_refreshed", %{"exp" => new_exp}, socket when is_integer(new_exp) ->
        now = System.system_time(:second)
        refresh_at_ms = max((new_exp - @refresh_before_seconds - now) * 1000, 0)
        Process.send_after(self(), :session_refresh_soon, refresh_at_ms)
        {:halt, socket}

      "session_refreshed", params, socket ->
        Logger.warning("session_refreshed received unexpected params=#{inspect(params)}")
        {:halt, socket}

      _event, _params, socket ->
        {:cont, socket}
    end)
  end

  defp schedule_session_refresh(socket, _session), do: socket
end
