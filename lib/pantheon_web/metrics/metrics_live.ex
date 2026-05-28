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

  embed_templates "/"
end
