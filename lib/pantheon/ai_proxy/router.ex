defmodule Pantheon.AiProxy.Router do
  use GenServer
  require Logger

  defstruct [
    :queue,
    queue_size: 0
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @type request_data :: %{
          provider: map(),
          path: String.t(),
          body: map()
        }

  @spec dispatch(request_data(), pid()) :: :ok | {:error, :no_capacity}
  def dispatch(request_data, client_pid) do
    GenServer.call(__MODULE__, {:dispatch, request_data, client_pid})
  end

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{queue: :queue.new()}}
  end

  @impl true
  def handle_call({:dispatch, request_data, client_pid}, _from, %__MODULE__{} = state) do
    case Pantheon.AiProxy.PoolManager.request_worker() do
      pid when is_pid(pid) ->
        Pantheon.AiProxy.Worker.handle_request(pid, request_data, client_pid)
        {:reply, :ok, state}

      nil ->
        if state.queue_size >= 100 do
          send(client_pid, {:proxy_stream_init, 503})

          error_json =
            Jason.encode!(%{
              error: %{message: "Too many requests — proxy pool at capacity", type: "rate_limit"}
            })

          send(client_pid, {:proxy_stream_chunk, "data: #{error_json}\n\n"})
          send(client_pid, {:proxy_stream_done})
          {:reply, {:error, :no_capacity}, state}
        else
          new_queue = :queue.in({request_data, client_pid}, state.queue)
          GenServer.cast(__MODULE__, :process_queue)
          {:reply, :ok, %{state | queue: new_queue, queue_size: state.queue_size + 1}}
        end
    end
  end

  @impl true
  def handle_cast(:process_queue, %__MODULE__{queue: queue} = state) do
    case :queue.out(queue) do
      {:empty, _rest} ->
        {:noreply, %{state | queue_size: 0}}

      {{:value, {request_data, client_pid}}, rest} ->
        case Pantheon.AiProxy.PoolManager.request_worker() do
          pid when is_pid(pid) ->
            Pantheon.AiProxy.Worker.handle_request(pid, request_data, client_pid)
            new_size = :queue.len(rest)
            {:noreply, %{state | queue: rest, queue_size: new_size}}

          nil ->
            new_queue = :queue.in({request_data, client_pid}, rest)
            Process.send_after(self(), {:process_queue}, 100)
            {:noreply, %{state | queue: new_queue}}
        end
    end
  end
end
