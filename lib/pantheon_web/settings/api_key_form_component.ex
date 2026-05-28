defmodule PantheonWeb.Settings.ApiKeyFormComponent do
  use PantheonWeb, :live_component

  alias Pantheon.UserApiKeys

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:key_name, "")
     |> assign(:show_created_modal, false)
     |> assign(:created_key, nil)
     |> assign(:errors, %{})}
  end

  @impl true
  def handle_event("create_change", %{"api_key" => params}, socket) do
    {:noreply, assign(socket, :key_name, Map.get(params, "name", ""))}
  end

  @impl true
  def handle_event("create", %{"api_key" => %{"name" => name}}, socket) do
    user_id = socket.assigns.user_id

    case UserApiKeys.generate(user_id, String.trim(name)) do
      {:ok, %{full_key: full_key}} ->
        {:noreply,
         socket
         |> assign(:key_name, "")
         |> assign(:show_created_modal, true)
         |> assign(:created_key, full_key)}

      {:error, reason} ->
        {:noreply, assign(socket, errors: %{__all__: [reason]})}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_created_modal, false)
     |> assign(:created_key, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <form
        method="post"
        id="create-key-form"
        phx-target={@myself}
        phx-change="create_change"
        phx-submit="create"
      >
        <div class="flex gap-2">
          <input
            type="text"
            name="api_key[name]"
            id="api-key-name-input"
            value={@key_name}
            placeholder="Key name (e.g., production-server)"
            required
            class="flex-1 px-3 py-2 text-sm bg-slate-900 border border-slate-700 rounded-lg text-slate-200 placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500/50 focus:border-blue-500"
          />
          <button
            type="submit"
            class="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-emerald-600 rounded-lg hover:bg-emerald-700 transition-colors shrink-0"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> Create New Key
          </button>
        </div>
      </form>

      <%= if Map.get(@errors, :__all__) do %>
        <div class="mt-2 text-sm text-red-400">
          <%= for error <- @errors[:__all] do %>
            <p>{error}</p>
          <% end %>
        </div>
      <% end %>

      <%= if @show_created_modal do %>
        <div
          id="api-key-created-modal"
          class="fixed inset-0 bg-black/60 flex items-center justify-center z-50"
        >
          <div class="bg-slate-900 border border-slate-700 rounded-2xl p-8 max-w-lg w-full mx-4 shadow-2xl">
            <h3 class="text-lg font-semibold text-white mb-2">API Key Created</h3>
            <p class="text-sm text-amber-400 mb-4">
              Copy this key now. You won't be able to see it again.
            </p>

            <div class="bg-slate-950 border border-slate-700 rounded-lg p-4 flex items-center justify-between gap-3">
              <code class="text-green-400 text-sm font-mono break-all">{@created_key}</code>
              <button
                type="button"
                phx-hook=".CopyApiKey"
                phx-value-key={@created_key}
                id="copy-api-key"
                class="shrink-0 px-3 py-1.5 text-xs font-medium bg-slate-800 text-slate-300 rounded-lg hover:bg-slate-700 transition-colors"
              >
                Copy
              </button>
            </div>

            <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyApiKey">
              export default {
                mounted() {
                  this.el.addEventListener("click", () => {
                    navigator.clipboard.writeText(this.el.dataset.key || this.el.getAttribute("phx-value-key"))
                      .then(() => {
                        const original = this.el.textContent;
                        this.el.textContent = "Copied!";
                        setTimeout(() => (this.el.textContent = original), 2000);
                      });
                  });
                }
              }
            </script>

            <div class="mt-6 flex justify-end">
              <button
                type="button"
                phx-click="close_modal"
                phx-target={@myself}
                class="px-4 py-2 text-sm font-medium bg-slate-800 text-slate-300 rounded-lg hover:bg-slate-700 transition-colors"
              >
                Done
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
