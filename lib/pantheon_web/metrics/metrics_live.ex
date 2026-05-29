defmodule PantheonWeb.Metrics.MetricsLive do
  use PantheonWeb, :live_view

  alias Pantheon.Data.CompletionMetricsDB

  @time_ranges %{
    "1h" => 1,
    "6h" => 6,
    "24h" => 24,
    "7d" => 168,
    "30d" => 720
  }

  @aggregation_tabs ["Provider", "Model", "User", "Token"]

  @chart_metrics [
    {"Requests", :requests},
    {"Avg Latency (ms)", :avg_latency_ms},
    {"Total Tokens", :total_tokens},
    {"Errors", :error_count}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :load, 0)
    end

    {:ok,
     socket
     |> assign(:time_ranges, @time_ranges)
     |> assign(:time_range, "24h")
     |> assign(:time_hours, 24)
     |> assign(:aggregation_tab, "Provider")
     |> assign(:chart_metrics, MapSet.new(["Requests"]))
     |> assign(:summary, %{})
     |> assign(:chart_data, [])}
  end

  @impl true
  def handle_event("time_range", %{"range" => range}, socket) do
    hours = Map.get(@time_ranges, range, socket.assigns.time_hours)

    {:noreply,
     socket
     |> assign(:time_range, range)
     |> assign(:time_hours, hours)
     |> load_data()
     |> push_chart_event()}
  end

  @impl true
  def handle_event("aggregation_tab", %{"tab" => tab}, socket) when tab in @aggregation_tabs do
    {:noreply,
     socket
     |> assign(:aggregation_tab, tab)
     |> load_data()
     |> push_chart_event()}
  end

  @impl true
  def handle_event("toggle_chart_metric", %{"metric" => metric}, socket) do
    new_metrics =
      if MapSet.member?(socket.assigns.chart_metrics, metric) do
        MapSet.delete(socket.assigns.chart_metrics, metric)
      else
        MapSet.put(socket.assigns.chart_metrics, metric)
      end

    {:noreply,
     socket
     |> assign(:chart_metrics, new_metrics)
     |> load_data()
     |> push_chart_event()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply,
     socket
     |> load_data()
     |> push_chart_event()}
  end

  @impl true
  def handle_event("get_chart_config", _params, socket) do
    {:noreply, push_event(socket, "update_chart", build_chart_config(socket))}
  end

  @impl true
  def handle_info(:load, socket) do
    {:noreply,
     socket
     |> load_data()
     |> push_chart_event()}
  end

  defp load_data(socket) do
    socket
    |> load_summary()
    |> load_chart_data()
  end

  defp load_summary(socket) do
    summary = CompletionMetricsDB.aggregate_summary(socket.assigns.time_hours)
    assign(socket, :summary, summary)
  end

  defp load_chart_data(socket) do
    data =
      case socket.assigns.aggregation_tab do
        "Provider" -> CompletionMetricsDB.aggregate_by_provider(socket.assigns.time_hours)
        "Model" -> CompletionMetricsDB.aggregate_by_model(socket.assigns.time_hours)
        "User" -> CompletionMetricsDB.aggregate_by_user(socket.assigns.time_hours)
        "Token" -> CompletionMetricsDB.aggregate_by_api_key(socket.assigns.time_hours)
      end

    assign(socket, :chart_data, data)
  end

  # --- Rendering helpers ---

  defp format_latency(nil), do: "—"
  defp format_latency(ms) when ms < 1000, do: "#{round(ms)}ms"
  defp format_latency(ms), do: "#{Float.round(ms / 1000, 2)}s"

  defp format_tokens(n) when n >= 1_000_000, do: "#{div(n, 1_000_000)}M"
  defp format_tokens(n) when n >= 1_000, do: "#{div(n, 1_000)}K"
  defp format_tokens(n), do: to_string(n)

  defp push_chart_event(socket) do
    if not Enum.empty?(socket.assigns.chart_data) and
         MapSet.size(socket.assigns.chart_metrics) > 0 do
      push_event(socket, "update_chart", build_chart_config(socket))
    else
      socket
    end
  end

  defp build_chart_config(socket) do
    labels = Enum.map(socket.assigns.chart_data, & &1["label"])

    datasets =
      for {display_name, key} <- @chart_metrics,
          display_name in socket.assigns.chart_metrics,
          into: [] do
        values =
          Enum.map(socket.assigns.chart_data, fn row ->
            row[key] || 0
          end)

        %{
          label: display_name,
          data: values,
          backgroundColor: dataset_color(display_name),
          borderRadius: 6,
          barThickness: "flex",
          maxBarThickness: 80
        }
      end

    %{
      type: "bar",
      data: %{labels: labels, datasets: datasets},
      options: %{
        indexAxis: "y",
        responsive: true,
        maintainAspectRatio: false,
        plugins: %{
          legend: %{display: true, position: "top"},
          tooltip: %{enabled: true}
        },
        scales: %{
          x: %{
            beginAtZero: true,
            grid: %{color: "rgba(255, 255, 255, 0.06)"}
          },
          y: %{
            grid: %{display: false}
          }
        }
      }
    }
  end

  defp dataset_color("Requests"), do: "rgba(59, 130, 246, 0.8)"
  defp dataset_color("Avg Latency (ms)"), do: "rgba(251, 146, 60, 0.8)"
  defp dataset_color("Total Tokens"), do: "rgba(34, 197, 94, 0.8)"
  defp dataset_color("Errors"), do: "rgba(239, 68, 68, 0.8)"

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-8">
        <h1 class="text-2xl font-bold text-white tracking-tight">Performance Metrics</h1>

        <button
          phx-click="refresh"
          class="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium text-slate-300 rounded-lg hover:bg-slate-800 transition-colors"
        >
          <.icon name="hero-arrow-path" class="size-4" /> Refresh
        </button>
      </div>

      <div class="flex items-center gap-2 mb-6">
        <span class="text-xs font-medium text-slate-500 uppercase tracking-wider mr-1">Period</span>
        <div class="flex rounded-lg bg-slate-800/50 p-1">
          <%= for {label, _hours} <- @time_ranges do %>
            <button
              phx-click="time_range"
              phx-value-range={Enum.find(@time_ranges, fn {k, _} -> k == label end) |> elem(0)}
              class={[
                "px-3 py-1.5 text-xs font-medium rounded-md transition-all",
                if @time_range == label do
                  "bg-blue-600 text-white shadow-sm"
                else
                  "text-slate-400 hover:text-slate-200"
                end
              ]}
            >
              {label}
            </button>
          <% end %>
        </div>
      </div>

      <div class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <div class="rounded-xl border border-slate-800 bg-slate-900/50 p-5">
          <dt class="text-xs font-medium text-slate-500 uppercase tracking-wider mb-1">
            Total Requests
          </dt>
          <dd class="text-2xl font-bold text-white">{@summary["total_requests"] || 0}</dd>
        </div>

        <div class="rounded-xl border border-slate-800 bg-slate-900/50 p-5">
          <dt class="text-xs font-medium text-slate-500 uppercase tracking-wider mb-1">
            Avg Latency
          </dt>
          <dd class="text-2xl font-bold text-white">{format_latency(@summary["avg_latency_ms"])}</dd>
        </div>

        <div class="rounded-xl border border-slate-800 bg-slate-900/50 p-5">
          <dt class="text-xs font-medium text-slate-500 uppercase tracking-wider mb-1">
            Total Tokens
          </dt>
          <dd class="text-2xl font-bold text-white">
            {format_tokens(@summary["total_completion_tokens"] || 0)}
          </dd>
        </div>

        <div class="rounded-xl border border-slate-800 bg-slate-900/50 p-5">
          <dt class="text-xs font-medium text-slate-500 uppercase tracking-wider mb-1">Errors</dt>
          <dd class={[
            "text-2xl font-bold",
            if(@summary["error_count"] && @summary["error_count"] > 0,
              do: "text-red-400",
              else: "text-emerald-400"
            )
          ]}>
            {@summary["error_count"] || 0}
          </dd>
        </div>
      </div>

      <div class="flex flex-col sm:flex-row sm:items-center gap-4 mb-6">
        <div class="flex rounded-lg bg-slate-800/50 p-1">
          <%= for tab <- ["Provider", "Model", "User", "Token"] do %>
            <button
              phx-click="aggregation_tab"
              phx-value-tab={tab}
              class={[
                "px-4 py-2 text-sm font-medium rounded-md transition-all",
                if @aggregation_tab == tab do
                  "bg-blue-600 text-white shadow-sm"
                else
                  "text-slate-400 hover:text-slate-200"
                end
              ]}
            >
              {tab}
            </button>
          <% end %>
        </div>

        <div class="flex items-center gap-4 ml-auto">
          <span class="text-xs font-medium text-slate-500 uppercase tracking-wider">Show:</span>
          <%= for {display_name, _key} <- @chart_metrics do %>
            <label class="flex items-center gap-2 cursor-pointer group">
              <input
                type="checkbox"
                phx-change="toggle_chart_metric"
                phx-value-metric={display_name}
                checked={display_name in @chart_metrics}
                class="w-4 h-4 rounded border-slate-600 bg-slate-800 text-blue-600 focus:ring-blue-500 focus:ring-offset-0 cursor-pointer"
              />
              <span class="text-sm text-slate-400 group-hover:text-slate-200 transition-colors">
                {display_name}
              </span>
            </label>
          <% end %>
        </div>
      </div>

      <div class="rounded-xl border border-slate-800 bg-slate-900/50 p-6">
        <%= if Enum.empty?(@chart_data) do %>
          <div class="flex flex-col items-center justify-center py-16 text-center">
            <p class="text-lg font-medium text-slate-400 mb-1">No metrics data</p>
            <p class="text-sm text-slate-500">
              No completions found for this time period. Try extending the range or making some requests.
            </p>
          </div>
        <% else %>
          <div
            id="metrics-chart"
            phx-hook=".MetricsChart"
            phx-update="ignore"
            class="relative"
            style="height: 350px;"
          >
            <canvas id="metrics-chart-canvas"></canvas>
          </div>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".MetricsChart">
            export default {
              mounted() {
                this.handleEvent("get_chart_config", (config) => {
                  if (this.chart) {
                    this.updateChart(config);
                  } else {
                    this.initChart(config);
                  }
                });

                this.pushEvent("get_chart_config");
              },

              initChart(config) {
                const ctx = document.getElementById('metrics-chart-canvas').getContext('2d');
                this.chart = new Chart(ctx, config);
              },

              updateChart(config) {
                config.data.datasets.forEach((newDataset, i) => {
                  const existing = this.chart.data.datasets[i];
                  if (existing) {
                    existing.data = newDataset.data;
                    existing.backgroundColor = newDataset.backgroundColor;
                    existing.label = newDataset.label;
                  }
                });

                if (config.data.datasets.length !== this.chart.data.datasets.length) {
                  this.chart.data.datasets = config.data.datasets.map(ds => ({...ds}));
                }

                this.chart.data.labels = [...config.data.labels];
                this.chart.update('active');
              }
            }
          </script>
        <% end %>
      </div>
    </div>
    """
  end
end
