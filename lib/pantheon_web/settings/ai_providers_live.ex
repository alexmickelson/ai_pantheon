defmodule PantheonWeb.Settings.AIProvidersLive do
  use PantheonWeb, :live_view

  alias Pantheon.AIProviders
  alias Pantheon.UserApiKeys
  alias PantheonWeb.Settings.ProvidersListComponent

  @impl true
  def mount(_params, session, socket) do
    user_id = session["current_user_id"]

    if connected?(socket) do
      AIProviders.subscribe()
      UserApiKeys.subscribe(user_id)
      Phoenix.PubSub.subscribe(Pantheon.PubSub, "user_error:#{user_id}")
    end

    {:ok,
     socket
     |> assign(:user_id, user_id)
     |> assign(:editing_provider, nil)
     |> assign(:error_toasts, [])}
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
  def handle_info({:key_created, _key}, socket) do
    send_update(PantheonWeb.Settings.ApiKeyListComponent,
      id: "api-keys-list",
      user_id: socket.assigns.user_id,
      action: {:insert, nil}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:key_deleted, _payload}, socket) do
    send_update(PantheonWeb.Settings.ApiKeyListComponent,
      id: "api-keys-list",
      user_id: socket.assigns.user_id,
      action: :refresh
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:error_broadcast, message}, socket) do
    toast_id = System.system_time(:millisecond)
    toast = %{id: toast_id, message: message}

    # Auto-dismiss after 5 seconds
    Process.send_after(self(), {:dismiss_error_toast, toast_id}, 5_000)

    {:noreply,
     socket
     |> update(:error_toasts, &[toast | &1])}
  end

  @impl true
  def handle_info({:dismiss_error_toast, toast_id}, socket) do
    {:noreply,
     socket
     |> update(:error_toasts, fn toasts ->
       Enum.reject(toasts, fn t -> t.id == toast_id end)
     end)}
  end

  @impl true
  def handle_event("dismiss_error_toast", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> update(:error_toasts, fn toasts ->
       Enum.reject(toasts, fn t -> Integer.to_string(t.id) == id end)
     end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!-- Error toast notifications -->
    <div id="error-toasts" class="fixed top-4 right-4 z-50 flex flex-col gap-2 max-w-sm w-full">
      <%= for toast <- @error_toasts do %>
        <div
          id={"error-toast-#{toast.id}"}
          class="bg-red-900/90 border border-red-700 text-red-100 px-4 py-3 rounded-lg shadow-lg flex items-start gap-3 animate-slide-in"
        >
          <.icon name="hero-exclamation-circle-mini" class="w-5 h-5 shrink-0 mt-0.5 text-red-400" />
          <p class="text-sm flex-1">{toast.message}</p>
          <button
            type="button"
            phx-click="dismiss_error_toast"
            phx-value-id={toast.id}
            class="shrink-0 text-red-400 hover:text-red-200 transition-colors"
          >
            <.icon name="hero-x-mark-mini" class="w-4 h-4" />
          </button>
        </div>
      <% end %>
    </div>

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

      <div class="mt-12">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-xl font-semibold">API Keys</h2>
          <.live_component
            module={PantheonWeb.Settings.ApiKeyFormComponent}
            id="api-key-form"
            user_id={@user_id}
          />
        </div>

        <p class="text-sm text-slate-400 mb-6">
          API keys grant access to the /v1 proxy endpoints. Keys are shown only once upon creation.
        </p>

        <.live_component
          module={PantheonWeb.Settings.ApiKeyListComponent}
          id="api-keys-list"
          user_id={@user_id}
        />
      </div>
    </div>
    """
  end
end
