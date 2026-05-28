defmodule PantheonWeb.Settings.AIProvidersLive do
  use PantheonWeb, :live_view

  alias Pantheon.AIProviders
  alias PantheonWeb.Settings.ProvidersListComponent

  @impl true
  def mount(_params, session, socket) do
    user_id = session["current_user_id"]

    if connected?(socket) do
      AIProviders.subscribe()
    end

    {:ok,
     socket
     |> assign(:user_id, user_id)
     |> assign(:editing_provider, nil)}
  end

  @impl true
  def handle_info({:edit_provider, provider}, socket) do
    {:noreply, assign(socket, :editing_provider, provider)}
  end

  @impl true
  def handle_info({:form_cancelled}, socket) do
    {:noreply, assign(socket, :editing_provider, nil)}
  end

  @impl true
  def handle_info({:provider_created, provider}, socket) do
    send_update(ProvidersListComponent, id: "providers-list", action: {:insert, provider})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:provider_updated, provider}, socket) do
    send_update(ProvidersListComponent, id: "providers-list", action: {:update, provider})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:provider_deleted, payload}, socket) do
    send_update(ProvidersListComponent, id: "providers-list", action: {:delete, payload})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <.header>
        AI Providers
      </.header>

      <.live_component
        module={PantheonWeb.Settings.ProviderFormComponent}
        id="provider-form"
        user_id={@user_id}
        provider={@editing_provider}
      />

      <.live_component
        module={PantheonWeb.Settings.ProvidersListComponent}
        id="providers-list"
        user_id={@user_id}
      />
    </div>
    """
  end
end
