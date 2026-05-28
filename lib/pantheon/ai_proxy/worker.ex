defmodule Pantheon.AiProxy.Worker do
  use GenServer
  require Logger

  @registry Pantheon.AiProxy.WorkerRegistry
  @pool_manager Pantheon.AiProxy.PoolManager
  @stream_timeout 30_000

  defstruct [
    :client_pid,
    registered_as: nil,
    status: :idle,
    idle_timer_ref: nil
  ]

  @type request_data :: %{
          provider: map(),
          path: String.t(),
          body: map()
        }

  def start_link(_opts \\ %{}) do
    GenServer.start_link(__MODULE__, %{}, name: nil)
  end

  def handle_request(worker_pid, request_data, client_pid) do
    GenServer.call(worker_pid, {:request, request_data, client_pid})
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    Registry.register(@registry, :idle, self())
    {:ok, %__MODULE__{registered_as: :idle}}
  end

  @impl true
  def terminate(_reason, state) do
    cancel_idle_timer(state)

    if state.registered_as do
      Registry.unregister(@registry, state.registered_as)
    end

    :ok
  end

  @impl true
  def handle_call({:request, request_data, client_pid}, _from, %__MODULE__{} = state) do
    cancel_idle_timer(state)

    new_state =
      switch_registry(state, :busy)
      |> Map.put(:status, :busy)
      |> Map.put(:client_pid, client_pid)

    forward_request(request_data, self())
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:stream_init, status}, %__MODULE__{client_pid: pid} = state) do
    send(pid, {:proxy_stream_init, status})
    {:noreply, state}
  end

  def handle_info({_ref, {:stream_init, status}}, %__MODULE__{client_pid: pid} = state) do
    send(pid, {:proxy_stream_init, status})
    {:noreply, state}
  end

  def handle_info({:stream_chunk, chunk}, %__MODULE__{client_pid: pid} = state) do
    send(pid, {:proxy_stream_chunk, chunk})
    {:noreply, state}
  end

  def handle_info({_ref, {:stream_chunk, chunk}}, %__MODULE__{client_pid: pid} = state) do
    send(pid, {:proxy_stream_chunk, chunk})
    {:noreply, state}
  end

  def handle_info({:stream_error, message}, %__MODULE__{client_pid: pid} = state) do
    error_json = Jason.encode!(%{error: %{message: message, type: "api_error"}})
    send(pid, {:proxy_stream_chunk, "data: #{error_json}\n\n"})
    send(pid, {:proxy_stream_done})

    new_state =
      switch_registry(state, :idle)
      |> Map.put(:status, :idle)
      |> Map.put(:client_pid, nil)

    idle_timeout =
      Application.get_env(:pantheon, :ai_proxy_pool)[:worker_idle_timeout] || 60_000

    timer_ref = Process.send_after(self(), {:idle_timeout}, idle_timeout)
    {:noreply, %{new_state | idle_timer_ref: timer_ref}}
  end

  def handle_info({_ref, {:stream_error, message}}, %__MODULE__{client_pid: pid} = state) do
    error_json = Jason.encode!(%{error: %{message: message, type: "api_error"}})
    send(pid, {:proxy_stream_chunk, "data: #{error_json}\n\n"})
    send(pid, {:proxy_stream_done})

    new_state =
      switch_registry(state, :idle)
      |> Map.put(:status, :idle)
      |> Map.put(:client_pid, nil)

    idle_timeout =
      Application.get_env(:pantheon, :ai_proxy_pool)[:worker_idle_timeout] || 60_000

    timer_ref = Process.send_after(self(), {:idle_timeout}, idle_timeout)
    {:noreply, %{new_state | idle_timer_ref: timer_ref}}
  end

  def handle_info({:stream_done}, %__MODULE__{client_pid: pid} = state) do
    send(pid, {:proxy_stream_done})

    new_state =
      switch_registry(state, :idle)
      |> Map.put(:status, :idle)
      |> Map.put(:client_pid, nil)

    idle_timeout =
      Application.get_env(:pantheon, :ai_proxy_pool)[:worker_idle_timeout] || 60_000

    timer_ref = Process.send_after(self(), {:idle_timeout}, idle_timeout)
    {:noreply, %{new_state | idle_timer_ref: timer_ref}}
  end

  def handle_info({_ref, {:stream_done}}, %__MODULE__{client_pid: pid} = state) do
    send(pid, {:proxy_stream_done})

    new_state =
      switch_registry(state, :idle)
      |> Map.put(:status, :idle)
      |> Map.put(:client_pid, nil)

    idle_timeout =
      Application.get_env(:pantheon, :ai_proxy_pool)[:worker_idle_timeout] || 60_000

    timer_ref = Process.send_after(self(), {:idle_timeout}, idle_timeout)
    {:noreply, %{new_state | idle_timer_ref: timer_ref}}
  end

  def handle_info({:idle_timeout}, %__MODULE__{} = state) do
    cancel_idle_timer(state)
    GenServer.cast(@pool_manager, {:terminate_idle, self()})
    {:stop, :normal, state}
  end

  defp switch_registry(state, new_status) do
    if state.registered_as == new_status do
      state
    else
      if state.registered_as do
        Registry.unregister(@registry, state.registered_as)
      end

      Registry.register(@registry, new_status, self())
      %{state | registered_as: new_status}
    end
  end

  defp forward_request(request_data, worker_pid) do
    %{provider: provider, path: path, body: body} = request_data

    base_url = String.trim_trailing(provider.endpoint, "/")
    url = build_url(base_url, path, body)

    headers = [
      {"Authorization", "Bearer #{provider.auth_token}"},
      {"Content-Type", "application/json"},
      {"Accept", "text/event-stream"}
    ]

    Task.async(fn ->
      case Req.post(url, headers: headers, json: body, into: :self) do
        {:ok, %Req.Response{status: 200} = resp} ->
          send(worker_pid, {:stream_init, 200})
          stream_loop(resp)
          send(worker_pid, {:stream_done})

        {:ok, %Req.Response{status: status, body: body_map}} when status >= 400 ->
          send(worker_pid, {:stream_init, status})
          error_detail = Map.get(body_map, "detail", inspect(body_map))
          send(worker_pid, {:stream_error, error_detail})

        {:error, reason} ->
          send(worker_pid, {:stream_error, Exception.message(reason)})
      end
    end)
  end

  defp stream_loop(resp) do
    receive do
      message ->
        case Req.parse_message(resp, message) do
          {:ok, [data: chunk]} ->
            send(self(), {:stream_chunk, chunk})
            stream_loop(resp)

          {:ok, [:done]} ->
            :ok

          {:ok, [trailers: _trailers]} ->
            stream_loop(resp)

          {:error, reason} ->
            Logger.warning(
              "Stream error proxying request to provider endpoint: #{Exception.message(reason)}"
            )

            send(self(), {:stream_error, Exception.message(reason)})

          :unknown ->
            stream_loop(resp)
        end
    after
      @stream_timeout ->
        Req.cancel_async_response(resp)
        Logger.warning("Timeout waiting for stream response from provider endpoint")
        send(self(), {:stream_error, "Provider endpoint did not respond within timeout"})
    end
  end

  defp build_url(base, path, body) do
    query = if Map.get(body, "stream", false), do: "?stream=true", else: ""
    "#{base}#{path}#{query}"
  end

  defp cancel_idle_timer(%{idle_timer_ref: nil}), do: :ok
  defp cancel_idle_timer(%{idle_timer_ref: ref}), do: Process.cancel_timer(ref)
end
