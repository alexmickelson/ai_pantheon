defmodule Pantheon.Data.CompletionMetricsDB do
  require Logger
  alias Pantheon.Data.DbHelpers

  def schema do
    Zoi.object(%{
      id: Zoi.uuid(),
      user_id: Zoi.uuid(),
      provider_id: Zoi.uuid(),
      model: Zoi.string(),
      status_code: Zoi.integer(),
      prompt_tokens: Zoi.optional(Zoi.integer()),
      completion_tokens: Zoi.optional(Zoi.integer()),
      total_tokens: Zoi.optional(Zoi.integer()),
      cached_tokens: Zoi.optional(Zoi.integer()),
      prompt_ms: Zoi.nullish(Zoi.float()),
      predicted_ms: Zoi.nullish(Zoi.float()),
      prompt_per_token_ms: Zoi.nullish(Zoi.float()),
      predicted_per_token_ms: Zoi.nullish(Zoi.float()),
      prompt_per_second: Zoi.nullish(Zoi.float()),
      predicted_per_second: Zoi.nullish(Zoi.float()),
      cache_n: Zoi.optional(Zoi.integer()),
      draft_n: Zoi.optional(Zoi.integer()),
      draft_n_accepted: Zoi.optional(Zoi.integer()),
      response_latency_ms: Zoi.float(),
      error_message: Zoi.optional(Zoi.string()),
      inserted_at: Zoi.datetime()
    })
  end

  @doc """
  Inserts a completion metrics record. Fire-and-forget friendly.
  """
  def insert(%{} = attrs) do
    sql = """
    INSERT INTO completion_metrics (
      user_id, provider_id, model, status_code,
      prompt_tokens, completion_tokens, total_tokens, cached_tokens,
      prompt_ms, predicted_ms, prompt_per_token_ms, predicted_per_token_ms,
      prompt_per_second, predicted_per_second,
      cache_n, draft_n, draft_n_accepted,
      response_latency_ms, error_message
    ) VALUES (
      $(user_id), $(provider_id), $(model), $(status_code),
      $(prompt_tokens), $(completion_tokens), $(total_tokens), $(cached_tokens),
      $(prompt_ms), $(predicted_ms), $(prompt_per_token_ms), $(predicted_per_token_ms),
      $(prompt_per_second), $(predicted_per_second),
      $(cache_n), $(draft_n), $(draft_n_accepted),
      $(response_latency_ms), $(error_message)
    ) RETURNING id, inserted_at
    """

    params = %{
      "user_id" => Map.get(attrs, :user_id),
      "provider_id" => Map.get(attrs, :provider_id),
      "model" => Map.get(attrs, :model),
      "status_code" => Map.get(attrs, :status_code),
      "prompt_tokens" => Map.get(attrs, :prompt_tokens),
      "completion_tokens" => Map.get(attrs, :completion_tokens),
      "total_tokens" => Map.get(attrs, :total_tokens),
      "cached_tokens" => Map.get(attrs, :cached_tokens),
      "prompt_ms" => Map.get(attrs, :prompt_ms),
      "predicted_ms" => Map.get(attrs, :predicted_ms),
      "prompt_per_token_ms" => Map.get(attrs, :prompt_per_token_ms),
      "predicted_per_token_ms" => Map.get(attrs, :predicted_per_token_ms),
      "prompt_per_second" => Map.get(attrs, :prompt_per_second),
      "predicted_per_second" => Map.get(attrs, :predicted_per_second),
      "cache_n" => Map.get(attrs, :cache_n),
      "draft_n" => Map.get(attrs, :draft_n),
      "draft_n_accepted" => Map.get(attrs, :draft_n_accepted),
      "response_latency_ms" => Map.get(attrs, :response_latency_ms),
      "error_message" => Map.get(attrs, :error_message)
    }

    case DbHelpers.run_sql(sql, params) do
      [_result | _] ->
        :ok

      [] ->
        Logger.warning(
          "Completion metrics insert returned no rows for model '#{Map.get(attrs, :model)}'"
        )

        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to insert completion metrics for model '#{Map.get(attrs, :model)}': #{inspect(reason)}"
        )

        :ok
    end
  end

  @doc """
  Returns the most recent completions (up to limit), ordered by inserted_at DESC.
  """
  def list_recent(limit \\ 100) do
    sql = """
    SELECT cm.id, cm.provider_id, p.name AS provider_name, cm.model, cm.status_code,
           cm.prompt_tokens, cm.completion_tokens, cm.total_tokens, cm.cached_tokens,
           cm.prompt_ms, cm.predicted_ms, cm.prompt_per_token_ms, cm.predicted_per_token_ms,
           cm.prompt_per_second, cm.predicted_per_second,
           cm.cache_n, cm.draft_n, cm.draft_n_accepted,
           cm.response_latency_ms, cm.error_message, cm.inserted_at
    FROM completion_metrics cm
    LEFT JOIN ai_providers p ON p.id = cm.provider_id
    ORDER BY cm.inserted_at DESC
    LIMIT $(limit)
    """

    case DbHelpers.run_sql(sql, %{"limit" => limit})
         |> DbHelpers.rows_apply_datetime_conversion([:inserted_at]) do
      results when is_list(results) ->
        results

      {:error, reason} ->
        Logger.error("Failed to query recent completion metrics: #{inspect(reason)}")
        []
    end
  end

  @doc """
  Aggregates metrics grouped by provider and model for the last N hours.
  """
  def aggregate_by_provider(hours \\ 24) do
    sql = """
    SELECT cm.provider_id, p.name AS provider_name, cm.model,
           COUNT(*) AS request_count,
           AVG(cm.response_latency_ms) AS avg_response_latency_ms,
           MIN(cm.response_latency_ms) AS min_response_latency_ms,
           MAX(cm.response_latency_ms) AS max_response_latency_ms,
           SUM(cm.prompt_tokens) AS total_prompt_tokens,
           SUM(cm.completion_tokens) AS total_completion_tokens,
           AVG(cm.prompt_per_second) AS avg_prompt_throughput,
           AVG(cm.predicted_per_second) AS avg_generation_throughput,
           COUNT(CASE WHEN cm.error_message IS NOT NULL THEN 1 END) AS error_count
    FROM completion_metrics cm
    LEFT JOIN ai_providers p ON p.id = cm.provider_id
    WHERE cm.inserted_at >= NOW() - INTERVAL '1 hour' * $(hours)
    GROUP BY cm.provider_id, p.name, cm.model
    ORDER BY request_count DESC
    """

    case DbHelpers.run_sql(sql, %{"hours" => hours}) do
      results when is_list(results) ->
        results

      {:error, reason} ->
        Logger.error("Failed to query aggregated completion metrics: #{inspect(reason)}")
        []
    end
  end
end
