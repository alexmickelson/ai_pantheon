defmodule Pantheon.UserApiKeys do
  use GenServer

  alias Pantheon.Data.UserApiKeyDB
  alias Pantheon.UserErrorNotifier

  @topic "user_api_keys"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec generate(String.t(), String.t(), DateTime.t() | nil) ::
          {:ok, %{full_key: String.t(), key_record: map()}} | {:error, String.t()}
  def generate(user_id, name, expires_at \\ nil) do
    GenServer.call(__MODULE__, {:generate, user_id, name, expires_at})
  end

  @spec list_by_user(String.t()) :: [map()] | {:error, String.t()}
  def list_by_user(user_id) do
    GenServer.call(__MODULE__, {:list_by_user, user_id})
  end

  @spec delete(String.t(), String.t()) :: :ok | {:error, String.t()}
  def delete(key_id, user_id) do
    GenServer.call(__MODULE__, {:delete, key_id, user_id})
  end

  @spec validate_key(String.t()) ::
          {:ok, %{user_id: binary(), api_key_id: binary()}} | {:error, atom()}
  def validate_key(key_string) do
    UserApiKeyDB.validate_key(key_string)
  end

  @spec subscribe(String.t()) :: :ok
  def subscribe(user_id) do
    Phoenix.PubSub.subscribe(Pantheon.PubSub, "#{@topic}:#{user_id}")
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:generate, user_id, name, expires_at}, _from, state) do
    case UserApiKeyDB.generate(user_id, name, expires_at) do
      {:ok, %{full_key: _full_key, key_record: key_record} = result} ->
        broadcast(user_id, :key_created, key_record)
        {:reply, {:ok, result}, state}

      {:error, reason} ->
        UserErrorNotifier.broadcast_error(user_id, "Could not generate API key: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:list_by_user, user_id}, _from, state) do
    result = UserApiKeyDB.list_by_user(user_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:delete, key_id, user_id}, _from, state) do
    case UserApiKeyDB.delete(key_id, user_id) do
      :ok ->
        broadcast(user_id, :key_deleted, %{id: key_id})
        {:reply, :ok, state}

      {:error, reason} ->
        UserErrorNotifier.broadcast_error(user_id, "Could not delete API key: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end

  defp broadcast(user_id, event, payload) do
    Phoenix.PubSub.broadcast(
      Pantheon.PubSub,
      "#{@topic}:#{user_id}",
      {event, payload}
    )
  end
end
