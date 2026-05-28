defmodule PantheonWeb.Settings.ProviderFormComponent do
  use PantheonWeb, :live_component

  alias Pantheon.AIProviders

  @empty_form %{name: "", endpoint: "", auth_token: ""}

  def update(assigns, socket) do
    provider = assigns[:provider]

    form =
      case provider do
        nil -> @empty_form
        p -> %{name: p.name, endpoint: p.endpoint, auth_token: ""}
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, form)
     |> assign(:errors, %{})}
  end

  def handle_event("save", %{"ai_provider" => params}, socket) do
    form_params = string_keys_to_atoms(params)

    case validate_new(form_params) do
      {:error, errors} ->
        {:noreply, assign(socket, errors: errors)}

      :ok ->
        attrs = Map.take(params, ["name", "endpoint", "auth_token"])

        case AIProviders.create(socket.assigns.user_id, attrs) do
          {:ok, _provider} ->
            send(self(), :save_succeeded)
            {:noreply, assign(socket, form: @empty_form, errors: %{})}

          {:error, :duplicate_name} ->
            {:noreply,
             assign(socket, errors: %{name: ["A provider with that name already exists"]})}

          {:error, reason} ->
            {:noreply, assign(socket, errors: %{__all__: [inspect(reason)]})}
        end
    end
  end

  def handle_event("update", %{"ai_provider" => params}, socket) do
    provider = socket.assigns.provider!

    auth_token =
      if params["auth_token"] != "",
        do: Map.put(params, "auth_token", params["auth_token"]),
        else: params

    case AIProviders.update(provider.id, auth_token) do
      {:ok, _provider} ->
        send(self(), :edit_succeeded)
        {:noreply, socket}

      {:error, reason} ->
        send(self(), {:form_error, %{__all__: [inspect(reason)]}})
        {:noreply, socket}
    end
  end

  def handle_event("cancel", _params, socket) do
    send(socket.parent_pid, :form_cancelled)

    {:noreply, socket}
  end

  defp validate_new(params) do
    errors = %{}

    errors =
      if params.name == "",
        do: Map.put(errors, :name, ["Name is required"]),
        else: errors

    errors =
      if params.auth_token == "",
        do: Map.put(errors, :auth_token, ["Auth token is required"]),
        else: errors

    if map_size(errors) > 0, do: {:error, errors}, else: :ok
  end

  defp string_keys_to_atoms(params) do
    for {k, v} <- params, into: %{}, do: {String.to_atom(k), v}
  end

  attr :id, :string, required: true
  attr :user_id, :integer, required: true
  attr :provider, :any, default: nil
  attr :rest, :global, include: ~w(phx-update)

  def render(assigns) do
    assigns = assign(assigns, :editing, !is_nil(assigns.provider))

    ~H"""
    <div id={@id} class="card bg-base-200 mb-8">
      <div class="card-body p-6">
        <h2 class="card-title text-base mb-4">
          {if @editing, do: "Edit Provider", else: "Add Provider"}
        </h2>

        <.form
          for={%{}}
          id={if @editing, do: "edit-provider-form", else: "add-provider-form"}
          phx-target={@myself}
          phx-submit={if @editing, do: "update", else: "save"}
        >
          <%= if @editing do %>
            <input type="hidden" name="ai_provider[id]" value={@provider.id} />
          <% end %>

          <div class="space-y-3">
            <div>
              <label for={"#{@id}-name"} class="block text-sm font-medium mb-1">Name</label>
              <input
                type="text"
                name="ai_provider[name]"
                id={"#{@id}-name"}
                value={@form.name}
                placeholder="My API Provider"
                class={["w-full input", Map.get(@errors, :name, []) != [] && "input-error"]}
              />
              <p :for={msg <- Map.get(@errors, :name, [])} class="mt-1.5 text-sm text-error">
                {msg}
              </p>
            </div>

            <div>
              <label for={"#{@id}-endpoint"} class="block text-sm font-medium mb-1">Endpoint</label>
              <input
                type="text"
                name="ai_provider[endpoint]"
                id={"#{@id}-endpoint"}
                value={@form.endpoint}
                placeholder="https://api.example.com/v1"
                class={["w-full input", Map.get(@errors, :endpoint, []) != [] && "input-error"]}
              />
              <p :for={msg <- Map.get(@errors, :endpoint, [])} class="mt-1.5 text-sm text-error">
                {msg}
              </p>
            </div>

            <div>
              <label for={"#{@id}-auth-token"} class="block text-sm font-medium mb-1">
                {if @editing, do: "New Auth Token (leave blank to keep current)", else: "Auth Token"}
              </label>
              <input
                type="password"
                name="ai_provider[auth_token]"
                id={"#{@id}-auth-token"}
                value={@form.auth_token}
                placeholder="sk-..."
                class={["w-full input", Map.get(@errors, :auth_token, []) != [] && "input-error"]}
              />
              <p :for={msg <- Map.get(@errors, :auth_token, [])} class="mt-1.5 text-sm text-error">
                {msg}
              </p>
            </div>
          </div>

          <%= for msg <- Map.get(@errors, :__all__, []) do %>
            <p class="text-sm text-error mt-2">{msg}</p>
          <% end %>

          <div class="flex gap-2 mt-4">
            <.button type="submit">
              {if @editing, do: "Update", else: "Add Provider"}
            </.button>

            <button
              :if={@editing}
              type="button"
              phx-click="cancel"
              phx-target={@myself}
              class="btn btn-ghost"
            >
              Cancel
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
