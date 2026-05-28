defmodule Pantheon.AIProviders do
  use GenServer
  require Logger
  alias Pantheon.Data.AIProviderDB

  @topic "ai_providers"

  defstruct providers_by_user: %{}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def list(user_id) do
    GenServer.call(__MODULE__, {:list, user_id})
  end

  def subscribe(user_id) do
    Phoenix.PubSub.subscribe(Pantheon.PubSub, topic(user_id))
  end

  def create(user_id, attrs) do
    GenServer.call(__MODULE__, {:create, user_id, attrs})
  end

  def update(provider_id, attrs) do
    GenServer.call(__MODULE__, {:update, provider_id, attrs})
  end

  def delete(provider_id) do
    GenServer.call(__MODULE__, {:delete, provider_id})
  end

  @impl true
  def init(_opts) do
    state = load_from_db()
    {:ok, state}
  end

  def handle_call({:list, user_id}, _from, state) do
    providers = Map.get(state.providers_by_user, user_id, [])
    {:reply, providers, state}
  end

  @impl true
  def handle_call({:create, user_id, attrs}, _from, state) do
    case AIProviderDB.create(user_id, attrs) do
      {:ok, provider} ->
        new_state = update_cache(state, user_id, &[provider | &1])
        broadcast(user_id, :provider_created, provider)
        {:reply, {:ok, provider}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:update, provider_id, attrs}, _from, state) do
    case AIProviderDB.update(provider_id, attrs) do
      {:ok, provider} ->
        new_state =
          update_cache(state, provider.user_id, fn existing ->
            Enum.map(existing, fn p ->
              if p.id == provider_id, do: provider, else: p
            end)
          end)

        broadcast(provider.user_id, :provider_updated, provider)
        {:reply, {:ok, provider}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:delete, provider_id}, _from, state) do
    user_id = find_user_id(state, provider_id)

    case AIProviderDB.delete(provider_id) do
      :ok when not is_nil(user_id) ->
        new_state =
          update_cache(state, user_id, fn providers ->
            Enum.reject(providers, fn p -> p.id == provider_id end)
          end)

        broadcast(user_id, :provider_deleted, %{id: provider_id})
        {:reply, :ok, new_state}

      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp load_from_db() do
    providers = AIProviderDB.load_all_for_cache()

    by_user =
      Enum.group_by(providers, fn provider -> provider.user_id end)

    %__MODULE__{providers_by_user: by_user}
  end

  defp update_cache(%__MODULE__{} = state, user_id, updater) do
    providers = Map.get(state.providers_by_user, user_id, [])
    new_providers = updater.(providers)

    updated_map =
      if new_providers == [] do
        Map.delete(state.providers_by_user, user_id)
      else
        Map.put(state.providers_by_user, user_id, new_providers)
      end

    %__MODULE__{state | providers_by_user: updated_map}
  end

  defp broadcast(user_id, event, payload) do
    Phoenix.PubSub.broadcast(Pantheon.PubSub, topic(user_id), {event, payload})
  end

  defp topic(user_id) do
    "#{@topic}:user:#{user_id}"
  end

  defp find_user_id(state, provider_id) do
    Enum.reduce_while(state.providers_by_user, nil, fn {_user_id, providers}, _acc ->
      case Enum.find(providers, &(&1.id == provider_id)) do
        %{user_id: user_id} -> {:halt, user_id}
        nil -> {:cont, nil}
      end
    end)
  end
end
