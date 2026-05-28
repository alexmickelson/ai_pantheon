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

  @impl true
  def init(_opts) do
    parent = self()

    Task.async(fn ->
      providers = AIProviderDB.load_all_for_cache()
      send(parent, {:db_loaded, providers})
    end)

    {:ok, %__MODULE__{}}
  end

  def handle_call(:list, _from, %__MODULE__{} = state) do
    {:reply, state.providers, state}
  end

  @impl true
  def handle_call({:create, attrs}, _from, %__MODULE__{} = state) do
    case AIProviderDB.create(attrs) do
      {:ok, provider} ->
        provider_with_models = Map.put(provider, :models, [])
        new_state = %__MODULE__{state | providers: [provider_with_models | state.providers]}

        spawn_model_fetch(new_state, provider)

        broadcast(:provider_created, provider_with_models)
        {:reply, {:ok, provider_with_models}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:update, provider_id, attrs}, _from, %__MODULE__{} = state) do
    case AIProviderDB.update(provider_id, attrs) do
      {:ok, provider} ->
        provider_with_models = Map.put(provider, :models, [])

        new_state = %__MODULE__{
          state
          | providers:
              Enum.map(state.providers, fn p ->
                if p.id == provider_id, do: provider_with_models, else: p
              end)
        }

        spawn_model_fetch(new_state, provider)

        broadcast(:provider_updated, provider_with_models)
        {:reply, {:ok, provider_with_models}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

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

  defp broadcast(event, payload) do
    Phoenix.PubSub.broadcast(Pantheon.PubSub, @topic, {event, payload})
  end

  @impl true
  def handle_info({:db_loaded, providers}, %__MODULE__{} = state) do
    with_empty_models = Enum.map(providers, &Map.put(&1, :models, []))

    for provider <- providers do
      spawn_model_fetch(state, provider)
    end

    {:noreply, %__MODULE__{state | providers: with_empty_models}}
  end

  def handle_info({_ref, {:db_loaded, providers}}, %__MODULE__{} = state) do
    handle_info({:db_loaded, providers}, state)
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, %__MODULE__{} = state) do
    {:noreply,
     %__MODULE__{state | pending_model_fetches: Map.delete(state.pending_model_fetches, ref)}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %__MODULE__{} = state) do
    case Map.pop(state.pending_model_fetches, ref) do
      {nil, ^state} ->
        {:noreply, state}

      {{%{provider_id: provider_id}}, new_state} ->
        Logger.warning(
          "Model fetch task crashed for provider #{inspect(provider_id)} with reason: #{inspect(reason)}"
        )

        {:noreply, new_state}

      {_, new_state} ->
        {:noreply, new_state}
    end
  end

  def handle_info({:models_fetched, provider_id, models}, %__MODULE__{} = state) do
    case Enum.find(state.providers, &(&1.id == provider_id)) do
      nil ->
        {:noreply, state}

      _provider ->
        new_state = %__MODULE__{
          state
          | providers:
              Enum.map(state.providers, fn p ->
                if p.id == provider_id, do: Map.put(p, :models, models), else: p
              end)
        }

        updated = Enum.find(new_state.providers, &(&1.id == provider_id))
        broadcast(:provider_updated, updated)
        {:noreply, new_state}
    end
  end

  def handle_info({_ref, {:models_fetched, provider_id, models}}, %__MODULE__{} = state) do
    handle_info({:models_fetched, provider_id, models}, state)
  end

  def handle_info(msg, %__MODULE__{} = state) do
    Logger.warning("Unhandled message received in AIProviders GenServer: #{inspect(msg)}")
    {:noreply, state}
  end

  defp spawn_model_fetch(state, provider) do
    parent = self()
    provider_id = provider.id

    task =
      Task.async(fn ->
        models =
          case OpenAICompatible.fetch_models(provider.endpoint, provider.auth_token) do
            {:ok, fetched} ->
              Enum.map(fetched, & &1.id)

            {:error, reason} ->
              Logger.warning("Failed to fetch models for provider #{provider.name}: #{reason}")
              []
          end

        send(parent, {:models_fetched, provider_id, models})
      end)

    ref = Process.monitor(task.pid)

    %{
      state
      | pending_model_fetches:
          Map.put(state.pending_model_fetches, ref, %{provider_id: provider_id})
    }
  end
end
