defmodule PantheonWeb.Metrics.Components.TokensOverTime do
  use Phoenix.LiveComponent

  alias Pantheon.Data.CompletionMetricsDB

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> load_timeline_data()}
  end

  defp load_timeline_data(socket) do
    data = CompletionMetricsDB.timeline_tokens_by_model(socket.assigns.time_hours)
    assign(socket, :timeline_data, data)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rounded-xl border border-slate-800 bg-slate-900/50 p-6 mb-8">
      <h2 class="text-lg font-semibold text-white mb-4">Tokens Over Time by Model</h2>
      <%= if Enum.empty?(@timeline_data) do %>
        <div class="flex flex-col items-center justify-center py-16 text-center">
          <p class="text-lg font-medium text-slate-400 mb-1">No timeline data</p>
          <p class="text-sm text-slate-500">
            No token usage found for this time period.
          </p>
        </div>
      <% else %>
        <.live_component
          module={PantheonWeb.Metrics.Components.ChartJs}
          id="timeline-chart"
          chart_config={build_timeline_config(@timeline_data)}
          height="400px"
        />
      <% end %>
    </div>
    """
  end

  # --- Timeline chart config builder ---

  defp build_timeline_config(timeline_data) do
    models = Enum.map(timeline_data, & &1["model"]) |> Enum.uniq()

    all_times =
      timeline_data
      |> Enum.map(& &1["time_bucket"])
      |> Enum.uniq()
      |> Enum.sort()

    labels = Enum.map(all_times, &format_datetime_label/1)

    datasets =
      for model <- models do
        values =
          for time <- all_times do
            row =
              Enum.find(timeline_data, fn r ->
                r["model"] == model and r["time_bucket"] == time
              end)

            Map.get(row || %{}, "completion_tokens", 0) || 0
          end

        %{
          label: model,
          data: values,
          borderColor: line_color(model),
          backgroundColor: line_bg(model),
          borderWidth: 2,
          tension: 0.3,
          fill: false,
          pointRadius: 0,
          pointHitRadius: 16,
          pointHoverRadius: 5,
          pointBackgroundColor: line_color(model),
          spanGaps: false
        }
      end

    %{
      type: "line",
      data: %{labels: labels, datasets: datasets},
      options: %{
        responsive: true,
        maintainAspectRatio: false,
        interaction: %{mode: "index", intersect: false},
        plugins: %{
          legend: %{display: true, position: "top"},
          tooltip: %{enabled: true}
        },
        scales: %{
          x: %{
            grid: %{color: "rgba(255, 255, 255, 0.06)"}
          },
          y: %{
            beginAtZero: true,
            grid: %{color: "rgba(255, 255, 255, 0.06)"},
            title: %{display: true, text: "Completion Tokens", color: "rgba(255, 255, 255, 0.5)"}
          }
        }
      }
    }
  end

  defp format_datetime_label(dt) when is_binary(dt) do
    case dt |> DateTime.from_iso8601() do
      {:ok, datetime, _offset} ->
        Calendar.strftime(datetime, "%b %d \n%H:%M")

      {:error, _reason} ->
        dt
    end
  end

  defp format_datetime_label(dt) do
    case dt do
      %DateTime{} -> Calendar.strftime(dt, "%b %d \n%H:%M")
      %NaiveDateTime{} -> Calendar.strftime(dt, "%b %d \n%H:%M")
      _ -> to_string(dt)
    end
  end

  defp line_color(model) do
    "hsl(#{:erlang.phash2(model, 360)}, 70%, 65%)"
  end

  defp line_bg(model) do
    "hsla(#{:erlang.phash2(model, 360)}, 70%, 65%, 0.1)"
  end
end
