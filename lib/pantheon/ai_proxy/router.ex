defmodule Pantheon.AiProxy.Router do
  use GenServer

  defstruct active_refs: MapSet.new()

  @type request_data :: %{
          user_id: binary() | nil,
          provider: map(),
          path: String.t(),
          body: map()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @spec dispatch(request_data(), pid()) :: :ok
  def dispatch(request_data, client_pid) do
    GenServer.call(__MODULE__, {:dispatch, request_data, client_pid})
  end

  @spec spawn_worker(request_data(), pid()) :: :ok
  def spawn_worker(request_data, client_pid) do
    GenServer.call(__MODULE__, {:spawn_worker, request_data, client_pid})
  end

  @spec in_flight_count() :: non_neg_integer()
  def in_flight_count() do
    GenServer.call(__MODULE__, :in_flight_count)
  end

  @spec recent_completions(pos_integer()) :: [%{}]
  def recent_completions(limit \\ 100) do
    Pantheon.Data.CompletionMetricsDB.list_recent(limit)
  end

  @spec stats(non_neg_integer()) :: [%{}]
  def stats(hours \\ 24) do
    Pantheon.Data.CompletionMetricsDB.aggregate_by_provider(hours)
  end

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:dispatch, request_data, client_pid}, _from, state) do
    new_state = spawn_task(request_data, client_pid, state)
    {:reply, :ok, new_state}
  end

  def handle_call({:spawn_worker, request_data, client_pid}, _from, state) do
    new_state = spawn_task(request_data, client_pid, state)
    {:reply, :ok, new_state}
  end

  def handle_call(:in_flight_count, _from, state) do
    count = MapSet.size(state.active_refs)
    {:reply, count, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %__MODULE__{} = state) do
    new_state = %{state | active_refs: MapSet.delete(state.active_refs, ref)}
    {:noreply, new_state}
  end

  def handle_info({ref, _result}, %__MODULE__{} = state) when is_reference(ref) do
    # async_nolink sends {ref, result} on completion; we track lifecycle via DOWN only
    {:noreply, state}
  end

  defp spawn_task(request_data, client_pid, state) do
    task =
      Task.Supervisor.async_nolink(
        Pantheon.AiProxy.TaskSupervisor,
        Pantheon.AiProxy.RequestWorker,
        :run,
        [request_data, client_pid]
      )

    %{state | active_refs: MapSet.put(state.active_refs, task.ref)}
  end
end
