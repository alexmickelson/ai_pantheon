defmodule PantheonWeb.Settings.ProvidersListComponent do
  use PantheonWeb, :live_component

  alias Pantheon.AIProviders

  @impl true
  def update(assigns, socket) do
    user_id = assigns.user_id

    if assigns[:initial] != false do
      AIProviders.subscribe(user_id)
    end

    providers = AIProviders.list(user_id)

    {:ok,
     socket
     |> assign(assigns)
     |> stream(:providers, providers)}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    provider = Enum.find(AIProviders.list(socket.assigns.user_id), &(&1.id == id))

    case provider do
      nil ->
        {:noreply, socket |> put_flash(:error, "Provider not found")}

      _ ->
        send(socket.parent_pid, {:edit_provider, provider})
        {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case AIProviders.delete(id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Provider removed")}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, "Failed to delete provider: #{inspect(reason)}")}
    end
  end

  def handle_info({:provider_created, provider}, socket) do
    user_id = socket.assigns.user_id

    case Map.get(provider, :user_id) do
      ^user_id ->
        {:noreply, stream_insert(socket, :providers, provider)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:provider_updated, provider}, socket) do
    user_id = socket.assigns.user_id

    case Map.get(provider, :user_id) do
      ^user_id ->
        {:noreply, stream_insert(socket, :providers, provider)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:provider_deleted, %{id: id}}, socket) do
    deleted = %{id: id}

    case Enum.any?(AIProviders.list(socket.assigns.user_id), &(&1.id == id)) do
      true ->
        {:noreply, stream_delete(socket, :providers, deleted)}

      false ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div :if={@streams.providers != []} class="card bg-base-200">
        <div class="card-body p-6">
          <h2 class="card-title text-base mb-4">Connected Providers</h2>

          <div id="providers" phx-update="stream" class="space-y-2">
            <%= for {id, provider} <- @streams.providers do %>
              <div
                id={"provider-" <> to_string(id)}
                class="flex items-center justify-between p-4 bg-base-100 rounded-lg gap-4"
              >
                <div>
                  <p class="font-medium">{provider.name}</p>
                  <p :if={provider.endpoint} class="text-sm text-base-content/60">
                    {provider.endpoint}
                  </p>
                </div>

                <div class="flex gap-2 flex-shrink-0">
                  <button
                    type="button"
                    phx-click="edit"
                    phx-value-id={id}
                    phx-target={@myself}
                    class="btn btn-sm btn-ghost"
                  >
                    Edit
                  </button>

                  <button
                    type="button"
                    phx-click="delete"
                    phx-value-id={id}
                    phx-target={@myself}
                    data-confirm="Remove this provider?"
                    class="btn btn-sm btn-ghost text-red-500 hover:bg-red-500/10"
                  >
                    Delete
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
