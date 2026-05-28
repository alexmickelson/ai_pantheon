defmodule PantheonWeb.Settings.AIProvidersLive do
  use PantheonWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    user_id = session["current_user_id"]

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
