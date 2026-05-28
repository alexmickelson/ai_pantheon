defmodule PantheonWeb.Settings.ProviderFormComponent do
  use PantheonWeb, :live_component
  require Logger

  alias Pantheon.AIProviders
  alias Pantheon.AIProviders.OpenAICompatible

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
     |> assign(:errors, %{})
     |> assign(:test_models, nil)
     |> assign(:test_error, nil)}
  end

  def handle_event("save", %{"ai_provider" => params}, socket) do
    form_params = string_keys_to_atoms(params)

    case validate_new(form_params) do
      {:error, errors} ->
        {:noreply, assign(socket, errors: errors)}

      :ok ->
        attrs = Map.take(params, ["name", "endpoint", "auth_token"])

        case AIProviders.create(attrs) do
          {:ok, _provider} ->
            {:noreply,
             socket
             |> assign(:form, @empty_form)
             |> assign(:errors, %{})
             |> assign(:test_models, nil)
             |> assign(:test_error, nil)}

          {:error, :duplicate_name} ->
            {:noreply,
             assign(socket, errors: %{name: ["A provider with that name already exists"]})}

          {:error, msg} when is_binary(msg) ->
            {:noreply, assign(socket, errors: %{__all__: [msg]})}
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
        {:noreply, assign(socket, errors: %{})}

      {:error, msg} when is_binary(msg) ->
        {:noreply, assign(socket, errors: %{__all__: [msg]})}

      {:error, reason} ->
        Logger.error(
          "Unexpected error response from AI providers service while editing form: #{inspect(reason)}"
        )

        {:noreply,
         assign(socket,
           errors: %{__all__: ["An unexpected error occurred while updating the provider."]}
         )}
    end
  end

  def handle_event("change", %{"ai_provider" => params}, socket) do
    form = %{
      name: Map.get(params, "name", @empty_form.name),
      endpoint: Map.get(params, "endpoint", @empty_form.endpoint),
      auth_token: Map.get(params, "auth_token", @empty_form.auth_token)
    }

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("test_connection", _params, socket) do
    endpoint = socket.assigns.form.endpoint
    auth_token = socket.assigns.form.auth_token

    cond do
      endpoint == "" ->
        {:noreply, assign(socket, test_error: "Endpoint is required")}

      auth_token == "" ->
        {:noreply, assign(socket, test_error: "Auth token is required")}

      true ->
        result = OpenAICompatible.fetch_models(endpoint, auth_token)

        case result do
          {:ok, models} ->
            {:noreply,
             socket
             |> assign(:test_models, models)
             |> assign(:test_error, nil)}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:test_models, nil)
             |> assign(:test_error, reason)}
        end
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

  def render(assigns) do
    assigns = assign(assigns, :editing, !is_nil(assigns.provider))

    ~H"""
    <div id={@id} class="bg-slate-900 rounded-xl border border-slate-800 mb-8">
      <div class="p-6">
        <h2 class="text-base font-semibold mb-4">
          {if @editing, do: "Edit Provider", else: "Add Provider"}
        </h2>

        <.form
          for={%{}}
          id={if @editing, do: "edit-provider-form", else: "add-provider-form"}
          phx-target={@myself}
          phx-change="change"
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
                class={[
                  "w-full px-3 py-2 text-sm bg-slate-800 border border-slate-700 rounded-lg text-slate-200 focus:outline-none focus:ring-2 focus:ring-blue-500/50 focus:border-blue-500",
                  Map.get(@errors, :name, []) != [] && "border-red-500"
                ]}
              />
              <p
                :for={msg <- Map.get(@errors, :name, [])}
                class="mt-1.5 text-xs text-red-100 bg-red-900 rounded px-2 py-1"
              >
                {msg}
              </p>
            </div>

            <div>
              <label for={"#{@id}-endpoint"} class="block text-sm font-medium mb-1">
                OpenAI Compatible Endpoint
              </label>
              <input
                type="text"
                name="ai_provider[endpoint]"
                id={"#{@id}-endpoint"}
                value={@form.endpoint}
                placeholder="https://api.example.com/v1"
                class={[
                  "w-full px-3 py-2 text-sm bg-slate-800 border border-slate-700 rounded-lg text-slate-200 focus:outline-none focus:ring-2 focus:ring-blue-500/50 focus:border-blue-500",
                  Map.get(@errors, :endpoint, []) != [] && "border-red-500"
                ]}
              />
              <p
                :for={msg <- Map.get(@errors, :endpoint, [])}
                class="mt-1.5 text-xs text-red-100 bg-red-900 rounded px-2 py-1"
              >
                {msg}
              </p>
              <p
                :if={@form.endpoint != ""}
                class="mt-1.5 text-xs text-slate-500 font-mono"
              >
                Models endpoint: {OpenAICompatible.models_url(@form.endpoint)}
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
                class={[
                  "w-full px-3 py-2 text-sm bg-slate-800 border border-slate-700 rounded-lg text-slate-200 focus:outline-none focus:ring-2 focus:ring-blue-500/50 focus:border-blue-500",
                  Map.get(@errors, :auth_token, []) != [] && "border-red-500"
                ]}
              />
              <p
                :for={msg <- Map.get(@errors, :auth_token, [])}
                class="mt-1.5 text-xs text-red-100 bg-red-900 rounded px-2 py-1"
              >
                {msg}
              </p>
            </div>
          </div>

          <%= for msg <- Map.get(@errors, :__all__, []) do %>
            <p class="text-xs text-red-100 bg-red-900 rounded px-2 py-1 mt-2">{msg}</p>
          <% end %>

          <div class="mt-4 pt-4 border-t border-slate-800">
            <div class="flex items-center gap-3">
              <button
                type="button"
                phx-click="test_connection"
                phx-target={@myself}
                phx-disable-with="Testing..."
                class="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-slate-300 bg-slate-800 border border-slate-700 rounded-lg hover:bg-slate-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="w-4 h-4"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09z"
                  />
                </svg>
                Test Connection
              </button>
            </div>

            <div :if={@test_error} class="mt-3 p-3 bg-red-900/50 border border-red-800 rounded-lg">
              <p class="text-sm text-red-200">{@test_error}</p>
            </div>

            <div
              :if={@test_models}
              class="mt-3 p-3 bg-green-900/50 border border-green-800 rounded-lg"
            >
              <p class="text-sm text-green-200 font-medium mb-2">
                Found {length(@test_models)} model{if length(@test_models) != 1, do: "s"}
              </p>
              <div class="flex flex-wrap gap-1.5 max-h-32 overflow-y-auto">
                <span
                  :for={model <- @test_models}
                  class="inline-block px-2 py-0.5 text-xs bg-green-900/70 text-green-200 rounded"
                >
                  {model.id}
                </span>
              </div>
            </div>
          </div>

          <div class="flex gap-2 mt-4">
            <.button type="submit">
              {if @editing, do: "Update", else: "Add Provider"}
            </.button>

            <button
              :if={@editing}
              type="button"
              phx-click="cancel"
              phx-target={@myself}
              class="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-slate-300 bg-slate-800 border border-slate-700 rounded-lg hover:bg-slate-700 transition-colors"
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
