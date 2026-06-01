defmodule PantheonWeb.Settings.ProvidersListComponent do
  use PantheonWeb, :live_component

  alias Pantheon.AIProviders

  @impl true
  def update(assigns, socket) do
    dom_id = fn p -> "provider-#{p.id}" end

    socket =
      case assigns[:action] do
        {:insert, provider} ->
          assign(socket, assigns) |> stream_insert(:providers, provider, dom_id: dom_id)

        {:update, provider} ->
          assign(socket, assigns) |> stream_insert(:providers, provider, dom_id: dom_id)

        {:delete, payload} ->
          socket
          |> assign(assigns)
          |> stream_delete_by_dom_id(:providers, "provider-#{payload.id}")

        :edit_finished ->
          providers = AIProviders.list()

          socket
          |> assign(assigns)
          |> assign(:editing_provider_id, nil)
          |> put_flash(:info, "Provider updated")
          |> stream(:providers, providers, reset: true)

        :edit_cancelled ->
          providers = AIProviders.list()

          socket
          |> assign(assigns)
          |> assign(:editing_provider_id, nil)
          |> stream(:providers, providers, reset: true)

        nil ->
          providers = AIProviders.list()

          socket
          |> assign(assigns)
          |> assign_new(:deleting_provider_id, fn -> nil end)
          |> assign_new(:editing_provider_id, fn -> nil end)
          |> stream(:providers, providers, dom_id: dom_id)
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    providers = AIProviders.list()

    {:noreply,
     socket
     |> assign(:editing_provider_id, id)
     |> stream(:providers, providers, reset: true)}
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    case AIProviders.delete(id) do
      :ok ->
        providers = AIProviders.list()

        {:noreply,
         socket
         |> assign(:deleting_provider_id, nil)
         |> stream(:providers, providers, reset: true)
         |> put_flash(:info, "Provider removed")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:deleting_provider_id, nil)
         |> put_flash(:error, "Failed to delete provider: #{inspect(reason)}")}
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    providers = AIProviders.list()

    {:noreply,
     socket
     |> assign(:deleting_provider_id, nil)
     |> stream(:providers, providers, reset: true)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    providers = AIProviders.list()

    {:noreply,
     socket
     |> assign(:deleting_provider_id, id)
     |> stream(:providers, providers, reset: true)}
  end

  def handle_event("refresh_models", %{"id" => id}, socket) do
    case AIProviders.refresh_models(id, socket.assigns.user_id) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to refresh models: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div :if={@streams.providers != []} class="bg-slate-900 rounded-xl border border-slate-800">
        <div class="p-6">
          <h2 class="text-base font-semibold mb-4">Connected Providers</h2>

          <div id="providers" phx-update="stream" class="space-y-2">
            <%= for {_id, provider} <- @streams.providers do %>
              <div
                id={"provider-#{provider.id}"}
                class="flex flex-col gap-3 p-4 bg-slate-800/50 rounded-lg"
              >
                <%= if @editing_provider_id == provider.id do %>
                  <.live_component
                    module={PantheonWeb.Settings.ProviderEditComponent}
                    id={"edit-#{provider.id}"}
                    provider={provider}
                  />
                <% else %>
                  <div class="flex items-center justify-between gap-4">
                    <div>
                      <p class="font-medium">{provider.name}</p>
                      <p :if={provider.endpoint} class="text-sm text-slate-500">
                        {provider.endpoint}
                      </p>
                    </div>

                    <div class="flex gap-2 shrink-0">
                      <%= if @deleting_provider_id == provider.id do %>
                        <span class="text-xs text-red-400 mr-2">Remove?</span>
                        <button
                          type="button"
                          phx-click="confirm_delete"
                          phx-value-id={provider.id}
                          phx-target={@myself}
                          class="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-medium text-red-200 bg-red-900/50 rounded-lg hover:bg-red-950 transition-colors"
                        >
                          Confirm
                        </button>
                        <button
                          type="button"
                          phx-click="cancel_delete"
                          phx-target={@myself}
                          class="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-medium rounded-lg hover:bg-slate-900 bg-slate-700 transition-colors"
                        >
                          Deny
                        </button>
                      <% else %>
                        <button
                          type="button"
                          phx-click="refresh_models"
                          phx-value-id={provider.id}
                          phx-target={@myself}
                          class="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-medium rounded-lg hover:bg-blue-700 transition-colors bg-blue-900/50 text-blue-200"
                          title="Refresh models list"
                        >
                          <.icon name="hero-arrow-path" class="h-3.5 w-3.5" />
                        </button>

                        <button
                          type="button"
                          phx-click="edit"
                          phx-value-id={provider.id}
                          phx-target={@myself}
                          class="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-medium rounded-lg hover:bg-slate-700 transition-colors bg-slate-900"
                        >
                          Edit
                        </button>

                        <button
                          type="button"
                          phx-click="delete"
                          phx-value-id={provider.id}
                          phx-target={@myself}
                          class="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-medium text-red-400 rounded-lg hover:bg-red-900/30 transition-colors"
                        >
                          Delete
                        </button>
                      <% end %>
                    </div>
                  </div>

                  <div :if={provider.models != []} class="flex flex-wrap gap-1.5">
                    <%= for model_id <- provider.models do %>
                      <span class="inline-flex items-center px-2 py-0.5 rounded-md text-xs bg-slate-700 text-slate-300">
                        {model_id}
                      </span>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
