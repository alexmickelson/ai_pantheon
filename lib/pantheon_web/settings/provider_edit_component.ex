defmodule PantheonWeb.Settings.ProviderEditComponent do
  use PantheonWeb, :live_component

  alias Pantheon.AIProviders
  alias PantheonWeb.Settings.ProvidersListComponent

  @impl true
  def update(assigns, socket) do
    provider = assigns.provider

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, %{name: provider.name, endpoint: provider.endpoint, auth_token: ""})
     |> assign(:edit_error, nil)}
  end

  @impl true
  def handle_event("edit_change", %{"provider" => params}, socket) do
    form = %{
      name: Map.get(params, "name", ""),
      endpoint: Map.get(params, "endpoint", ""),
      auth_token: Map.get(params, "auth_token", "")
    }

    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save_edit", %{"provider" => params}, socket) do
    provider_id = socket.assigns.provider.id
    attrs = Map.take(params, ["name", "endpoint", "auth_token"])

    case AIProviders.update(provider_id, attrs) do
      {:ok, _provider} ->
        send_update(ProvidersListComponent, id: "providers-list", action: :edit_finished)
        {:noreply, assign(socket, :edit_error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :edit_error, reason)}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    send_update(ProvidersListComponent, id: "providers-list", action: :edit_cancelled)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={%{}}
        id={"edit-form-#{@provider.id}"}
        phx-target={@myself}
        phx-change="edit_change"
        phx-submit="save_edit"
      >
        <div class="space-y-3">
          <div>
            <label for={"edit-name-#{@provider.id}"} class="block text-sm font-medium mb-1">
              Name
            </label>
            <input
              type="text"
              name="provider[name]"
              id={"edit-name-#{@provider.id}"}
              value={@form.name}
              class={[
                "w-full px-3 py-2 text-sm bg-slate-900 border border-slate-700 rounded-lg text-slate-200 focus:outline-none focus:ring-2 focus:ring-blue-500/50 focus:border-blue-500",
                @edit_error && "border-red-500"
              ]}
            />
          </div>

          <div>
            <label for={"edit-endpoint-#{@provider.id}"} class="block text-sm font-medium mb-1">
              Endpoint
            </label>
            <input
              type="text"
              name="provider[endpoint]"
              id={"edit-endpoint-#{@provider.id}"}
              value={@form.endpoint}
              class="w-full px-3 py-2 text-sm bg-slate-900 border border-slate-700 rounded-lg text-slate-200 focus:outline-none focus:ring-2 focus:ring-blue-500/50 focus:border-blue-500"
            />
          </div>

          <div>
            <label for={"edit-token-#{@provider.id}"} class="block text-sm font-medium mb-1">
              Auth Token
            </label>
            <input
              type="password"
              name="provider[auth_token]"
              id={"edit-token-#{@provider.id}"}
              value={@form.auth_token}
              class="w-full px-3 py-2 text-sm bg-slate-900 border border-slate-700 rounded-lg text-slate-200 focus:outline-none focus:ring-2 focus:ring-blue-500/50 focus:border-blue-500"
            />
          </div>
        </div>

        <p :if={@edit_error} class="mt-2 text-xs text-red-100 bg-red-900 rounded px-2 py-1">
          {@edit_error}
        </p>

        <div class="flex gap-2 mt-3">
          <button
            type="submit"
            class="inline-flex items-center gap-1 px-3 py-1.5 text-xs font-medium bg-blue-600 rounded-lg hover:bg-blue-700 transition-colors"
          >
            Save
          </button>
          <button
            type="button"
            phx-click="cancel_edit"
            phx-target={@myself}
            class="inline-flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-lg hover:bg-slate-700 transition-colors bg-slate-900"
          >
            Cancel
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
