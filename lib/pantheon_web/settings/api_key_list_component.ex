defmodule PantheonWeb.Settings.ApiKeyListComponent do
  use PantheonWeb, :live_component

  alias Pantheon.UserApiKeys

  @impl true
  def update(assigns, socket) do
    dom_id = fn k -> "api-key-#{k.id}" end

    socket =
      case assigns[:action] do
        {:insert, _key} ->
          keys = to_list(UserApiKeys.list_by_user(assigns.user_id))

          socket
          |> assign(assigns)
          |> stream(:api_keys, keys, dom_id: dom_id, reset: true)

        :refresh ->
          keys = to_list(UserApiKeys.list_by_user(assigns.user_id))

          socket
          |> assign(assigns)
          |> assign(:deleting_key_id, nil)
          |> stream(:api_keys, keys, dom_id: dom_id, reset: true)

        nil ->
          keys = to_list(UserApiKeys.list_by_user(assigns.user_id))

          socket
          |> assign(assigns)
          |> assign_new(:deleting_key_id, fn -> nil end)
          |> stream(:api_keys, keys, dom_id: dom_id)
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    keys = to_list(UserApiKeys.list_by_user(socket.assigns.user_id))

    {:noreply,
     socket
     |> assign(:deleting_key_id, id)
     |> stream(:api_keys, keys, reset: true)}
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    case UserApiKeys.delete(id, socket.assigns.user_id) do
      :ok ->
        {:noreply,
         socket
         |> assign(:deleting_key_id, nil)
         |> put_flash(:info, "API key removed")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:deleting_key_id, nil)
         |> put_flash(:error, "Failed to delete API key: #{reason}")}
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    keys = to_list(UserApiKeys.list_by_user(socket.assigns.user_id))

    {:noreply,
     socket
     |> assign(:deleting_key_id, nil)
     |> stream(:api_keys, keys, reset: true)}
  end

  defp to_list([]), do: []
  defp to_list([_ | _] = list), do: list
  defp to_list({:error, _reason}), do: []

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%= if @streams.api_keys != [] do %>
        <div class="bg-slate-900 rounded-xl border border-slate-800">
          <div class="p-6">
            <h2 class="text-base font-semibold mb-4">Your API Keys</h2>

            <div id="api-keys" phx-update="stream" class="space-y-2">
              <%= for {_id, key} <- @streams.api_keys do %>
                <div
                  id={"api-key-#{key.id}"}
                  class="flex items-center justify-between gap-4 p-4 bg-slate-800/50 rounded-lg"
                >
                  <div>
                    <p :if={key.name != ""} class="font-medium">{key.name}</p>
                    <p class="font-mono text-xs text-slate-400">{key.key_prefix}</p>
                    <p class="text-xs text-slate-500 mt-0.5">
                      Created {format_date(key.inserted_at)}
                      <%= if key.expires_at do %>
                        · Expires {format_date(key.expires_at)}
                      <% end %>
                    </p>
                  </div>

                  <div class="flex gap-2 shrink-0">
                    <%= if @deleting_key_id == key.id do %>
                      <span class="text-xs text-red-400 mr-2">Remove?</span>
                      <button
                        type="button"
                        phx-click="confirm_delete"
                        phx-value-id={key.id}
                        phx-target={@myself}
                        class="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-medium text-red-200 bg-red-900/50 rounded-lg hover:bg-red-950 transition-colors"
                      >
                        Confirm
                      </button>
                      <button
                        type="button"
                        phx-click="cancel_delete"
                        phx-target={@myself}
                        class="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-medium rounded-lg hover:bg-slate-700 bg-slate-900 transition-colors"
                      >
                        Deny
                      </button>
                    <% else %>
                      <button
                        type="button"
                        phx-click="delete"
                        phx-value-id={key.id}
                        phx-target={@myself}
                        class="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-medium text-red-400 rounded-lg hover:bg-red-900/30 transition-colors"
                      >
                        Delete
                      </button>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% else %>
        <p class="text-sm text-slate-500">No API keys created yet.</p>
      <% end %>
    </div>
    """
  end

  defp format_date(nil), do: "never"

  defp format_date(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, dt, _offset} -> Calendar.strftime(dt, "%Y-%m-%d")
      {:error, _reason} -> datetime
    end
  end

  defp format_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d")
  end
end
