defmodule Pantheon.AIProviders do
  use GenServer
  require Logger
  alias Pantheon.Data.AIProviderDB
  alias Pantheon.AIProviders.OpenAICompatible

  @topic "ai_providers"

  defstruct providers: [], pending_model_fetches: %{}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def list() do
    GenServer.call(__MODULE__, :list)
  end

  def subscribe() do
    Phoenix.PubSub.subscribe(Pantheon.PubSub, @topic)
  end

  def create(attrs) do
    GenServer.call(__MODULE__, {:create, attrs})
  end

  def update(provider_id, attrs) do
    GenServer.call(__MODULE__, {:update, provider_id, attrs})
  end

  def delete(provider_id) do
    GenServer.call(__MODULE__, {:delete, provider_id})
  end

  def refresh_models(provider_id, user_id) do
    GenServer.call(__MODULE__, {:refresh_models, provider_id, user_id})
  end

  @impl true
  def init(_opts) do
    Task.Supervisor.async_nolink(Pantheon.AIProviders.TaskSupervisor, fn ->
      {:db_loaded, AIProviderDB.load_all_for_cache()}
    end)

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:list, _from, %__MODULE__{} = state) do
    {:reply, state.providers, state}
  end

  @impl true
  def handle_call({:create, attrs}, _from, %__MODULE__{} = state) do
    case AIProviderDB.create(attrs) do
      {:ok, provider} ->
        provider_with_models = Map.put(provider, :models, [])

        state_with_provider = %__MODULE__{
          state
          | providers: [provider_with_models | state.providers]
        }

        new_state = spawn_model_fetch(state_with_provider, provider)
        broadcast(:provider_created, provider_with_models)
        {:reply, {:ok, provider_with_models}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:update, provider_id, attrs}, _from, %__MODULE__{} = state) do
    case AIProviderDB.update(provider_id, attrs) do
      {:ok, provider} ->
        provider_with_models = Map.put(provider, :models, [])

        state_with_provider = %__MODULE__{
          state
          | providers:
              Enum.map(state.providers, fn p ->
                if p.id == provider_id, do: provider_with_models, else: p
              end)
        }

        new_state = spawn_model_fetch(state_with_provider, provider)
        broadcast(:provider_updated, provider_with_models)
        {:reply, {:ok, provider_with_models}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:delete, provider_id}, _from, %__MODULE__{} = state) do
    case AIProviderDB.delete(provider_id) do
      :ok ->
        new_state = %__MODULE__{
          state
          | providers: Enum.reject(state.providers, fn p -> p.id == provider_id end)
        }

        broadcast(:provider_deleted, %{id: provider_id})
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:refresh_models, provider_id, user_id}, _from, %__MODULE__{} = state) do
    case Enum.find(state.providers, &(&1.id == provider_id)) do
      nil ->
        {:reply, {:error, "Provider not found"}, state}

      provider ->
        new_state = spawn_model_fetch(state, provider, user_id)
        {:reply, :ok, new_state}
    end
  end

  defp broadcast(event, payload) do
    Phoenix.PubSub.broadcast(Pantheon.PubSub, @topic, {event, payload})
  end

  @impl true
  def handle_info({ref, {:db_loaded, providers}}, %__MODULE__{} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    with_empty_models = Enum.map(providers, &Map.put(&1, :models, []))

    new_state =
      Enum.reduce(providers, %__MODULE__{state | providers: with_empty_models}, fn provider,
                                                                                   acc ->
        spawn_model_fetch(acc, provider)
      end)

    {:noreply, new_state}
  end

  def handle_info({ref, models}, %__MODULE__{} = state)
      when is_reference(ref) and is_list(models) do
    Process.demonitor(ref, [:flush])

    case Map.pop(state.pending_model_fetches, ref) do
      {nil, _} ->
        {:noreply, state}

      {provider_id, remaining_fetches} ->
        new_state =
          %__MODULE__{state | pending_model_fetches: remaining_fetches}
          |> apply_fetched_models(provider_id, models)

        {:noreply, new_state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %__MODULE__{} = state) do
    case Map.pop(state.pending_model_fetches, ref) do
      {nil, _} ->
        {:noreply, state}

      {provider_id, remaining_fetches} ->
        Logger.warning(
          "Model fetch task exited unexpectedly for provider #{inspect(provider_id)}: #{inspect(reason)}"
        )

        {:noreply, %__MODULE__{state | pending_model_fetches: remaining_fetches}}
    end
  end

  def handle_info(msg, %__MODULE__{} = state) do
    Logger.warning("Unhandled message received in AIProviders GenServer: #{inspect(msg)}")
    {:noreply, state}
  end

  defp apply_fetched_models(%__MODULE__{} = state, provider_id, models) do
    case Enum.find(state.providers, &(&1.id == provider_id)) do
      nil ->
        state

      _provider ->
        new_providers =
          Enum.map(state.providers, fn p ->
            if p.id == provider_id, do: Map.put(p, :models, models), else: p
          end)

        updated = Enum.find(new_providers, &(&1.id == provider_id))
        broadcast(:provider_updated, updated)
        %__MODULE__{state | providers: new_providers}
    end
  end

  defp spawn_model_fetch(%__MODULE__{} = state, provider, user_id \\ nil) do
    provider_id = provider.id

    task =
      Task.Supervisor.async_nolink(Pantheon.AIProviders.TaskSupervisor, fn ->
        case OpenAICompatible.fetch_models(provider.endpoint, provider.auth_token) do
          {:ok, fetched} ->
            Enum.map(fetched, & &1.id)

          {:error, reason} ->
            error_msg = "Could not fetch models for provider '#{provider.name}': #{reason}"
            Logger.warning(error_msg)

            if user_id do
              Pantheon.UserErrorNotifier.broadcast_error(user_id, error_msg)
            end

            []
        end
      end)

    %__MODULE__{
      state
      | pending_model_fetches: Map.put(state.pending_model_fetches, task.ref, provider_id)
    }
  end
end
