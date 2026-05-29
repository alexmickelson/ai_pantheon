defmodule PantheonWeb.Metrics.Components.MetricsChart do
  @moduledoc """
  Reusable Chart.js bar chart component with LiveView integration.

  Renders a horizontal bar chart container with a colocated JS hook that
  receives configuration updates via `push_event`. The parent LiveView
  is responsible for calling `build_config/2` and pushing the result.
  """
  use Phoenix.Component

  @doc """
  Builds the Chart.js configuration from raw row data and metric definitions.

  ## Parameters

    - `chart_data` — list of maps with at least a `"label"` key.
    - `all_chart_metrics` — list of `{display_name, key}` tuples.
    - `selected_chart_metrics` — `MapSet` of display names to include.

  """
  @spec build_config([map()], [{String.t(), atom()}], MapSet.t()) :: map()
  def build_config(chart_data, all_chart_metrics, selected_chart_metrics) do
    labels = Enum.map(chart_data, & &1["label"])

    datasets =
      for {display_name, key} <- all_chart_metrics,
          display_name in selected_chart_metrics,
          into: [] do
        values =
          Enum.map(chart_data, fn row ->
            Map.get(row, to_string(key), 0) || 0
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

  @doc """
  Renders the chart container with a colocated JS hook.

  The parent LiveView should push a `chart_config_{suffix}` event
  with the result of `build_config/2`.
  """
  attr :id, :string, required: true, doc: "unique DOM id for the chart container"
  attr :height, :string, default: "350px", doc: "CSS height of the chart area"

  def metrics_chart(assigns) do
    suffix = String.replace_prefix(assigns.id, "metrics-chart", "")
    canvas_id = assigns.id <> "-canvas"
    hook_name = ".MetricsChart#{suffix}"
    event_name = "chart_config#{suffix}"

    ~H"""
    <div
      id={@id}
      phx-hook={hook_name}
      phx-update="ignore"
      class="relative"
      style={"height: #{@height};"}
      data-event-name={event_name}
      data-canvas-id={canvas_id}
    >
      <canvas id={canvas_id}></canvas>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name={hook_name}>
      export default {
        mounted() {
          const eventName = this.el.dataset.eventName;
          const canvasId = this.el.dataset.canvasId;

          this.handleEvent(eventName, (config) => {
            if (this.chart) {
              this.updateChart(config);
            } else {
              this.initChart(config);
            }
          });

          this.pushEvent(eventName);
        },

        initChart(config) {
          const ctx = document.getElementById(this.el.dataset.canvasId).getContext('2d');
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
    """
  end

  # --- Private ---

  defp dataset_color("Requests"), do: "rgba(59, 130, 246, 0.8)"
  defp dataset_color("Avg Latency (ms)"), do: "rgba(251, 146, 60, 0.8)"
  defp dataset_color("Min Latency (ms)"), do: "rgba(139, 92, 246, 0.8)"
  defp dataset_color("Max Latency (ms)"), do: "rgba(236, 72, 153, 0.8)"
  defp dataset_color("Total Tokens"), do: "rgba(34, 197, 94, 0.8)"
  defp dataset_color("Prompt Tokens"), do: "rgba(6, 182, 212, 0.8)"
  defp dataset_color("Completion Tokens"), do: "rgba(234, 179, 8, 0.8)"
  defp dataset_color("Cached Tokens"), do: "rgba(244, 63, 94, 0.8)"
  defp dataset_color("Avg Prediction (ms)"), do: "rgba(168, 85, 247, 0.8)"
  defp dataset_color("Prediction Throughput (t/s)"), do: "rgba(239, 68, 68, 0.8)"
  defp dataset_color("Draft Acceptance (%)"), do: "rgba(14, 165, 233, 0.8)"
  defp dataset_color("Errors"), do: "rgba(220, 38, 38, 0.8)"
end
