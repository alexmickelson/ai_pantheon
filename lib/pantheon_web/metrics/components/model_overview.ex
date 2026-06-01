defmodule PantheonWeb.Metrics.Components.ModelOverview do
  @moduledoc """
  Renders a grid of model cards, each displaying aggregated completion metrics.
  """
  use Phoenix.Component

  attr :models, :list, required: true, doc: "list of model stat maps from aggregate_by_model"
  attr :time_range, :string, default: "24h", doc: "human-readable time range label"

  def model_overview(assigns) do
    ~H"""
    <div class="mb-8">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold text-white tracking-tight">Model Overview</h2>
        <span class="text-xs font-medium text-slate-500 uppercase tracking-wider">
          Last {@time_range}
        </span>
      </div>

      <%= if Enum.empty?(@models) do %>
        <div class="rounded-xl border border-dashed border-slate-800 bg-slate-900/30 p-8 text-center">
          <p class="text-sm text-slate-500">No models have been queried in this time period.</p>
        </div>
      <% else %>
        <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          <%= for model <- @models do %>
            <div class="rounded-xl border border-slate-800 bg-slate-900/50 p-5 hover:border-slate-700 transition-colors">
              <div class="flex items-center justify-between mb-4">
                <h3 class="text-base font-semibold text-white truncate">{model["label"]}</h3>
                <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-blue-600/20 text-blue-400 shrink-0 ml-2">
                  {model["requests"]} req
                </span>
              </div>

              <dl class="grid grid-cols-2 gap-x-4 gap-y-3">
                <!-- Throughput (most important) -->
                <div class="flex items-baseline gap-1.5">
                  <dt class="text-xl font-bold text-white">
                    {format_throughput(model["avg_prediction_throughput"])}
                  </dt>
                  <dd class="text-xs text-slate-500 leading-none">predicted t/s</dd>
                </div>

                <div class="flex items-baseline gap-1.5">
                  <dt class="text-xl font-bold text-white">
                    {format_throughput(model["avg_prompt_throughput"])}
                  </dt>
                  <dd class="text-xs text-slate-500 leading-none">prompt t/s</dd>
                </div>
                
    <!-- Draft acceptance & cache rate -->
                <div class="flex items-baseline gap-1.5">
                  <dt class="text-lg font-bold text-violet-400">
                    {format_percent(model["avg_draft_accepted"])}
                  </dt>
                  <dd class="text-xs text-slate-500 leading-none">draft acceptance</dd>
                </div>

                <div class="flex items-baseline gap-1.5">
                  <dt class="text-lg font-bold text-cyan-400">
                    {format_percent(model["cache_rate"])}
                  </dt>
                  <dd class="text-xs text-slate-500 leading-none">cache rate</dd>
                </div>
                
    <!-- Errors -->
                <div class="flex items-baseline gap-1.5">
                  <dt class={[
                    "text-lg font-bold",
                    if(model["error_count"] && model["error_count"] > 0,
                      do: "text-red-400",
                      else: "text-emerald-400"
                    )
                  ]}>
                    {model["error_count"] || 0}
                  </dt>
                  <dd class="text-xs text-slate-500 leading-none">errors</dd>
                </div>
                
    <!-- Token counts -->
                <div class="flex items-baseline gap-1.5">
                  <dt class="text-lg font-bold text-white">
                    {format_tokens(model["total_tokens"])}
                  </dt>
                  <dd class="text-xs text-slate-500 leading-none">total tokens</dd>
                </div>
                
    <!-- Latency -->
                <div class="flex items-baseline gap-1.5">
                  <dt class="text-lg font-bold text-white">
                    {format_latency(model["avg_latency_ms"])}
                  </dt>
                  <dd class="text-xs text-slate-500 leading-none">avg latency</dd>
                </div>
              </dl>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Formatting helpers ---

  defp format_latency(nil), do: "—"
  defp format_latency(ms) when ms < 1000, do: "#{round(ms)}ms"
  defp format_latency(ms), do: "#{Float.round(ms / 1000, 2)}s"

  defp format_tokens(nil), do: "—"
  defp format_tokens(0), do: "0"
  defp format_tokens(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_tokens(n) when n >= 1_000, do: "#{div(n, 1_000)}K"
  defp format_tokens(n), do: to_string(n)

  defp format_percent(nil), do: "—"
  defp format_percent(pct), do: "#{Float.round(pct, 1)}%"

  defp format_throughput(nil), do: "—"
  defp format_throughput(n) when n >= 1000, do: "#{Float.round(n / 1000, 1)}K"
  defp format_throughput(n), do: "#{Float.round(n, 1)}"
end
