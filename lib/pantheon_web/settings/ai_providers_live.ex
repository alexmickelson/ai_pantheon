defmodule PantheonWeb.Settings.AIProvidersLive do
  use PantheonWeb, :live_view

  alias Pantheon.AIProviders

  @impl true
  def mount(_params, session, socket) do
    user_id = session_user_id(session)
    AIProviders.subscribe(user_id)
    providers = AIProviders.list(user_id)

    {:ok,
     socket
     |> assign(:user_id, user_id)
     |> assign(:editing_provider, nil)
     |> stream(:providers, providers)}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    provider = Enum.find(AIProviders.list(socket.assigns.user_id), &(&1.id == id))

    case provider do
      nil ->
        {:noreply, socket |> put_flash(:error, "Provider not found")}

      _ ->
        {:noreply, assign(socket, :editing_provider, provider)}
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

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_provider, nil)}
  end

  @impl true
  def handle_info({:provider_created, provider}, socket) do
    user_id = socket.assigns.user_id

    case Map.get(provider, :user_id) do
      ^user_id ->
        {:noreply,
         socket
         |> stream_insert(:providers, provider)
         |> put_flash(:info, "Provider added")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:provider_updated, provider}, socket) do
    user_id = socket.assigns.user_id

    case Map.get(provider, :user_id) do
      ^user_id ->
        {:noreply,
         socket
         |> assign(:editing_provider, nil)
         |> stream_insert(:providers, provider)
         |> put_flash(:info, "Provider updated")}

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

  def handle_info({:form_cancelled}, socket) do
    {:noreply, assign(socket, :editing_provider, nil)}
  end

  defp session_user_id(session) do
    session["current_user_id"]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <.header>
        AI Providers
        <:subtitle>Manage your AI provider connections</:subtitle>
      </.header>

      <.live_component
        module={PantheonWeb.Settings.ProviderFormComponent}
        id="provider-form"
        user_id={@user_id}
        provider={@editing_provider}
      />

      <div :if={@streams.providers != []} class="card bg-base-200">
        <div class="card-body p-6">
          <h2 class="card-title text-base mb-4">Connected Providers</h2>

          <div id="providers" phx-update="stream" class="space-y-2">
            <%= for {id, provider} <- @streams.providers do %>
              <div
                id={"provider-" <> Integer.to_string(id)}
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
                    class="btn btn-sm btn-ghost"
                  >
                    Edit
                  </button>

                  <button
                    type="button"
                    phx-click="delete"
                    phx-value-id={id}
                    data-confirm="Remove this provider?"
                    class="btn btn-sm btn-ghost text-error hover:bg-error/10"
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
