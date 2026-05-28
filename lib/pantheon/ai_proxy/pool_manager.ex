defmodule Pantheon.AiProxy.PoolManager do
  use GenServer
  require Logger

  @supervisor Pantheon.AiProxy.WorkersSupervisor
  @min_workers 2
  @max_workers 50
  @scale_up_batch 3
  @topic "ai_providers"

  defstruct [
    :worker_pids,
    min_workers: @min_workers,
    max_workers: @max_workers,
    scale_up_batch: @scale_up_batch
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec request_worker() :: pid() | nil
  def request_worker() do
    case Registry.lookup(Pantheon.AiProxy.WorkerRegistry, :idle) do
      [{pid, _}] -> pid
      [] -> GenServer.call(__MODULE__, :request_worker)
    end
  end

  @spec worker_count() :: non_neg_integer()
  def worker_count() do
    GenServer.call(__MODULE__, :worker_count)
  end

  @impl true
  def init(_opts) do
    pool_config = Application.get_env(:pantheon, :ai_proxy_pool) || []
    min_workers = Keyword.get(pool_config, :min_workers, @min_workers)
    max_workers = Keyword.get(pool_config, :max_workers, @max_workers)
    scale_up_batch = Keyword.get(pool_config, :scale_up_batch, @scale_up_batch)

    Phoenix.PubSub.subscribe(Pantheon.PubSub, @topic)

    initial_pids = spawn_workers(min_workers, max_workers)

    {:ok,
     %__MODULE__{
       worker_pids: MapSet.new(initial_pids),
       min_workers: min_workers,
       max_workers: max_workers,
       scale_up_batch: scale_up_batch
     }}
  end

  @impl true
  def handle_call(:request_worker, _from, %__MODULE__{} = state) do
    case Registry.lookup(Pantheon.AiProxy.WorkerRegistry, :idle) do
      [{pid, _}] ->
        {:reply, pid, state}

      [] ->
        new_pids = scale_up(state)

        case Registry.lookup(Pantheon.AiProxy.WorkerRegistry, :idle) do
          [{pid, _}] ->
            {:reply, pid, %{state | worker_pids: Enum.into(new_pids, state.worker_pids)}}

          [] ->
            {:reply, nil, state}
        end
    end
  end

  def handle_call(:worker_count, _from, %__MODULE__{} = state) do
    count = MapSet.size(state.worker_pids)
    {:reply, count, state}
  end

  @impl true
  def handle_cast({:terminate_idle, pid}, %__MODULE__{} = state) do
    if pid in state.worker_pids do
      new_pids = MapSet.delete(state.worker_pids, pid)
      count = MapSet.size(new_pids)

      if count < state.min_workers do
        {:noreply, state}
      else
        DynamicSupervisor.terminate_child(@supervisor, pid)
        Logger.debug("Terminated idle worker (pool: #{count})")
        {:noreply, %{state | worker_pids: new_pids}}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %__MODULE__{} = state) do
    Logger.debug("Worker process went down: #{inspect(pid)}")
    {:noreply, %{state | worker_pids: MapSet.delete(state.worker_pids, pid)}}
  end

  def handle_info({_event, _payload}, %__MODULE__{} = state) do
    {:noreply, state}
  end

  defp spawn_workers(count, _max) do
    for _ <- 1..count do
      case DynamicSupervisor.start_child(@supervisor, {Pantheon.AiProxy.Worker, %{}}) do
        {:ok, pid} ->
          Process.monitor(pid)
          pid

        {:error, _reason} ->
          nil
      end
    end
    |> Enum.filter(&(&1 != nil))
  end

  defp scale_up(state) do
    current = MapSet.size(state.worker_pids)

    if current >= state.max_workers do
      Logger.warning(
        "Cannot scale up proxy worker pool — already at max workers (#{state.max_workers})"
      )

      []
    else
      to_spawn = min(state.scale_up_batch, state.max_workers - current)

      Logger.info("Scaling up proxy worker pool: #{current} → #{current + to_spawn}")
      spawn_workers(to_spawn, state.max_workers)
    end
  end
end
