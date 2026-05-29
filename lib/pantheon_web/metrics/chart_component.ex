defmodule PantheonWeb.Metrics.ChartComponent do
  use PantheonWeb, :html

  @doc """
  Renders a Chart.js bar chart driven by a `phx_hook` event.

  ## Attrs
    - `id`            – unique DOM id for the wrapper (required)
    - `config_event`  – name of the server->client event that carries the chart config
    - `push_event`    – name of the client->server event pushed on mount to request config
    - `chart_data`    – list of row maps; when empty an empty-state is shown instead
    - `height`        – CSS height string for the chart container

  The component exposes a colocated JS hook that listens for `config_event` and
  creates/updates the Chart.js instance. It does NOT send any data itself — all
  configuration flows from the server via `push_event/3`.
  """
  attr :id, :string, required: true
  attr :config_event, :string, default: "chart_config"
  attr :push_event_name, :string, default: "request_chart_config"
  attr :chart_data, :list, default: []
  attr :height, :string, default: "350px"

  def bar_chart(assigns) do
    ~H"""
    <div class="rounded-xl border border-slate-800 bg-slate-900/50 p-6">
      <%= if Enum.empty?(@chart_data) do %>
        <div class="flex flex-col items-center justify-center py-16 text-center">
          <p class="text-lg font-medium text-slate-400 mb-1">No chart data</p>
          <p class="text-sm text-slate-500">
            No data available for the current filters. Try adjusting your selection.
          </p>
        </div>
      <% else %>
        <div
          id={@id}
          phx-hook=".BarChart"
          phx-update="ignore"
          class="relative"
          style={"height: #{@height};"}
          data-config-event={@config_event}
          data-push-event={@push_event_name}
        >
          <canvas id={"#{@id}-canvas"}></canvas>
        </div>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".BarChart">
          export default {
            mounted() {
              const configEvent = this.el.dataset.configEvent;
              const pushEventName = this.el.dataset.pushEvent;

              this.handleEvent(configEvent, (config) => {
                if (this.chart) {
                  this.updateChart(config);
                } else {
                  this.initChart(config);
                }
              });

              this.pushEvent(pushEventName);
            },

            initChart(config) {
              const canvasId = this.el.id + '-canvas';
              const ctx = document.getElementById(canvasId).getContext('2d');
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
    """
  end
end
