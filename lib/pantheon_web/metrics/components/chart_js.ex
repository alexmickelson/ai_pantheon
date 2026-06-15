defmodule PantheonWeb.Metrics.Components.ChartJs do
  @moduledoc """
  Generic Chart.js LiveComponent that renders a pre-built chart configuration map.

  Accepts a fully-formed Chart.js config map and handles the JS interop
  (canvas rendering, push_event, hook). All data processing happens upstream
  in the calling component before the config is passed here.
  """
  use Phoenix.LiveComponent

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:canvas_id, fn -> "#{assigns[:id]}-canvas" end)
     |> assign_new(:height, fn -> "350px" end)
     |> push_chart_config()}
  end

  @impl true
  def handle_event("chart_config", _params, socket) do
    {:noreply, push_chart_config(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div
        id={@id}
        phx-hook=".ChartJs"
        phx-update="ignore"
        phx-target={@myself}
        class="relative"
        style={"height: #{@height};"}
        data-canvas-id={@canvas_id}
      >
        <canvas id={@canvas_id}></canvas>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ChartJs">
        export default {
          mounted() {
            this.handleEvent(`chart_config:${this.el.id}`, (config) => {
              if (this.chart) {
                this.updateChart(config);
              } else {
                this.initChart(config);
              }
            });

            this.pushEventTo(this.el, "chart_config", {});
          },

          initChart(config) {
            const ctx = document.getElementById(this.el.dataset.canvasId).getContext('2d');
            this.chart = new Chart(ctx, config);
          },

          updateChart(config) {
            if (this.chart.config.type === 'line') {
              this.chart.data.datasets = config.data.datasets.map(ds => ({...ds}));
              this.chart.data.labels = [...config.data.labels];
            } else {
              this.chart.data.datasets = config.data.datasets.map(ds => ({...ds}));
              this.chart.data.labels = [...config.data.labels];
            }

            this.chart.update('active');
          }
        }
      </script>
    </div>
    """
  end

  defp push_chart_config(socket) do
    push_event(socket, "chart_config:#{socket.assigns.id}", socket.assigns.chart_config)
  end
end
