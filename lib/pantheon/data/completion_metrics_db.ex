defmodule Pantheon.Data.CompletionMetricsDB do
  require Logger
  alias Pantheon.Data.DbHelpers

  def schema do
    Zoi.object(%{
      id: Zoi.optional(Zoi.uuid()),
      user_id: Zoi.uuid(),
      api_key_id: Zoi.uuid(),
      provider_id: Zoi.uuid(),
      model: Zoi.string(),
      status_code: Zoi.integer(),
      prompt_tokens: Zoi.nullish(Zoi.integer()),
      completion_tokens: Zoi.nullish(Zoi.integer()),
      total_tokens: Zoi.nullish(Zoi.integer()),
      cached_tokens: Zoi.nullish(Zoi.integer()),
      prompt_ms: Zoi.nullish(Zoi.float()),
      predicted_ms: Zoi.nullish(Zoi.float()),
      prompt_per_token_ms: Zoi.nullish(Zoi.float()),
      predicted_per_token_ms: Zoi.nullish(Zoi.float()),
      prompt_per_second: Zoi.nullish(Zoi.float()),
      predicted_per_second: Zoi.nullish(Zoi.float()),
      cache_n: Zoi.nullish(Zoi.integer()),
      draft_n: Zoi.nullish(Zoi.integer()),
      draft_n_accepted: Zoi.nullish(Zoi.integer()),
      response_latency_ms: Zoi.integer(),
      error_message: Zoi.nullish(Zoi.string()),
      inserted_at: Zoi.nullish(Zoi.datetime())
    })
  end

  def summary_schema do
    Zoi.object(%{
      total_requests: Zoi.integer(),
      avg_latency_ms: Zoi.nullish(Zoi.float()),
      min_latency_ms: Zoi.nullish(Zoi.float()),
      max_latency_ms: Zoi.nullish(Zoi.float()),
      total_tokens: Zoi.integer(),
      total_completion_tokens: Zoi.integer(),
      error_count: Zoi.integer()
    })
  end

  def bar_chart_schema do
    Zoi.object(%{
      label: Zoi.string(),
      requests: Zoi.integer(),
      avg_latency_ms: Zoi.nullish(Zoi.float()),
      min_latency_ms: Zoi.nullish(Zoi.float()),
      max_latency_ms: Zoi.nullish(Zoi.float()),
      total_tokens: Zoi.integer(),
      total_prompt_tokens: Zoi.nullish(Zoi.integer()),
      total_completion_tokens: Zoi.nullish(Zoi.integer()),
      cached_tokens: Zoi.nullish(Zoi.integer()),
      avg_predicted_ms: Zoi.nullish(Zoi.float()),
      avg_prediction_throughput: Zoi.nullish(Zoi.float()),
      avg_prompt_throughput: Zoi.nullish(Zoi.float()),
      cache_rate: Zoi.nullish(Zoi.float()),
      avg_draft_accepted: Zoi.nullish(Zoi.float()),
      error_count: Zoi.integer()
    })
  end

  def insert(%Pantheon.AiProxy.CompletionMetrics{} = metrics) do
    atom_attrs = Map.from_struct(metrics)
    sanitized = sanitize_timing_data(atom_attrs)

    case Zoi.parse(schema(), sanitized) do
      {:ok, _validated} ->
        string_attrs = to_string_keyed(sanitized)
        do_insert(string_attrs)

      {:error, errors} ->
        Logger.error(
          "Completion metrics insert failed validation for model '#{Map.get(atom_attrs, :model)}': #{inspect(errors)}"
        )

        :ok
    end
  end

  defp sanitize_timing_data(attrs) do
    {attrs, predicted_reasons} =
      case Map.get(attrs, :predicted_per_second) do
        val when is_number(val) and val > 1000 ->
          {Map.put(attrs, :predicted_per_second, nil),
           ["predicted_per_second=#{val} exceeds 1000 t/s"]}

        _ ->
          {attrs, []}
      end

    {attrs, ms_reasons} =
      case Map.get(attrs, :predicted_ms) do
        val when is_number(val) and val < 100 ->
          {attrs
           |> Map.put(:predicted_ms, nil)
           |> Map.put(:predicted_per_token_ms, nil)
           |> Map.put(:predicted_per_second, nil), ["predicted_ms=#{val} is below 100ms minimum"]}

        _ ->
          {attrs, []}
      end

    reasons = predicted_reasons ++ ms_reasons

    case reasons do
      [] ->
        attrs

      _ ->
        model = Map.get(attrs, :model)
        message = "Sanitized timing data: #{Enum.join(reasons, "; ")}"

        Logger.warning("Sanitizing implausible timing data for model '#{model}': #{message}")

        Map.put(attrs, :error_message, message)
    end
  end

  defp do_insert(%{} = attrs) do
    sql = """
    INSERT INTO completion_metrics (
      user_id, api_key_id, provider_id, model, status_code,
      prompt_tokens, completion_tokens, total_tokens, cached_tokens,
      prompt_ms, predicted_ms, prompt_per_token_ms, predicted_per_token_ms,
      prompt_per_second, predicted_per_second,
      cache_n, draft_n, draft_n_accepted,
      response_latency_ms, error_message
    ) VALUES (
      $(user_id), $(api_key_id), $(provider_id), $(model), $(status_code),
      $(prompt_tokens), $(completion_tokens), $(total_tokens), $(cached_tokens),
      $(prompt_ms), $(predicted_ms), $(prompt_per_token_ms), $(predicted_per_token_ms),
      $(prompt_per_second), $(predicted_per_second),
      $(cache_n), $(draft_n), $(draft_n_accepted),
      $(response_latency_ms), $(error_message)
    ) RETURNING id, inserted_at
    """

    case DbHelpers.run_sql(sql, attrs) do
      [_result | _] ->
        :ok

      [] ->
        Logger.warning(
          "Completion metrics insert returned no rows for model '#{Map.get(attrs, "model")}'"
        )

        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to insert completion metrics for model '#{Map.get(attrs, "model")}': #{inspect(reason)}"
        )

        :ok
    end
  end

  defp to_string_keyed(attrs) when is_map(attrs) do
    for {k, v} <- attrs, into: %{}, do: {to_string(k), v}
  end

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

  def aggregate_by_provider(hours \\ 24) do
    sql = """
    SELECT cm.provider_id, p.name AS provider_name, cm.model,
           COUNT(*) AS requests,
           AVG(cm.response_latency_ms) AS avg_latency_ms,
           MIN(cm.response_latency_ms) AS min_latency_ms,
           MAX(cm.response_latency_ms) AS max_latency_ms,
           COALESCE(SUM(cm.total_tokens), 0) AS total_tokens,
           COALESCE(SUM(cm.prompt_tokens), 0) AS total_prompt_tokens,
           COALESCE(SUM(cm.completion_tokens), 0) AS total_completion_tokens,
           COALESCE(SUM(cm.cached_tokens), 0) AS cached_tokens,
           AVG(CASE WHEN cm.prompt_tokens > 0 THEN cm.cached_tokens::float / cm.prompt_tokens * 100 ELSE NULL END) AS cache_rate,
           AVG(cm.predicted_ms) AS avg_predicted_ms,
           AVG(cm.predicted_per_second) AS avg_prediction_throughput,
           AVG(cm.prompt_per_second) AS avg_prompt_throughput,
           AVG(CASE WHEN cm.draft_n > 0 THEN cm.draft_n_accepted::float / cm.draft_n * 100 ELSE NULL END) AS avg_draft_accepted,
           COUNT(CASE WHEN cm.error_message IS NOT NULL THEN 1 END) AS error_count
    FROM completion_metrics cm
    LEFT JOIN ai_providers p ON p.id = cm.provider_id
    WHERE cm.inserted_at >= NOW() - INTERVAL '1 hour' * $(hours)
    GROUP BY cm.provider_id, p.name, cm.model
    ORDER BY requests DESC
    """

    case DbHelpers.run_sql(sql, %{"hours" => hours}) do
      results when is_list(results) ->
        results

      {:error, reason} ->
        Logger.error(
          "Failed to query aggregated completion metrics by provider: #{inspect(reason)}"
        )

        []
    end
  end

  def aggregate_summary(hours) do
    sql = """
    SELECT COUNT(*) AS total_requests,
           AVG(response_latency_ms) AS avg_latency_ms,
           MIN(response_latency_ms) AS min_latency_ms,
           MAX(response_latency_ms) AS max_latency_ms,
           COALESCE(SUM(total_tokens), 0) AS total_tokens,
           COALESCE(SUM(completion_tokens), 0) AS total_completion_tokens,
           COUNT(CASE WHEN error_message IS NOT NULL THEN 1 END) AS error_count
    FROM completion_metrics
    WHERE inserted_at >= NOW() - INTERVAL '1 hour' * $(hours)
    """

    case DbHelpers.run_sql(sql, %{"hours" => hours}) do
      [row] ->
        row

      [] ->
        %{total_requests: 0, total_tokens: 0, total_completion_tokens: 0, error_count: 0}

      {:error, reason} ->
        Logger.error("Failed to query completion metrics summary: #{inspect(reason)}")
        %{total_requests: 0, total_tokens: 0, total_completion_tokens: 0, error_count: 0}
    end
  end

  def aggregate_by_model(hours) do
    sql = """
    SELECT cm.model AS label,
           COUNT(*) AS requests,
           AVG(cm.response_latency_ms) AS avg_latency_ms,
           MIN(cm.response_latency_ms) AS min_latency_ms,
           MAX(cm.response_latency_ms) AS max_latency_ms,
           COALESCE(SUM(cm.total_tokens), 0) AS total_tokens,
           COALESCE(SUM(cm.prompt_tokens), 0) AS total_prompt_tokens,
           COALESCE(SUM(cm.completion_tokens), 0) AS total_completion_tokens,
           COALESCE(SUM(cm.cached_tokens), 0) AS cached_tokens,
           AVG(CASE WHEN cm.prompt_tokens > 0 THEN cm.cached_tokens::float / cm.prompt_tokens * 100 ELSE NULL END) AS cache_rate,
           AVG(cm.predicted_ms) AS avg_predicted_ms,
           AVG(cm.predicted_per_second) AS avg_prediction_throughput,
           AVG(cm.prompt_per_second) AS avg_prompt_throughput,
           AVG(CASE WHEN cm.draft_n > 0 THEN cm.draft_n_accepted::float / cm.draft_n * 100 ELSE NULL END) AS avg_draft_accepted,
           COUNT(CASE WHEN cm.error_message IS NOT NULL THEN 1 END) AS error_count
    FROM completion_metrics cm
    WHERE cm.inserted_at >= NOW() - INTERVAL '1 hour' * $(hours)
    GROUP BY cm.model
    ORDER BY requests DESC
    """

    case DbHelpers.run_sql(sql, %{"hours" => hours}) do
      results when is_list(results) ->
        results

      {:error, reason} ->
        Logger.error("Failed to query completion metrics by model: #{inspect(reason)}")
        []
    end
  end

  def aggregate_by_user(hours) do
    sql = """
    SELECT u.email AS label,
           COUNT(*) AS requests,
           AVG(cm.response_latency_ms) AS avg_latency_ms,
           MIN(cm.response_latency_ms) AS min_latency_ms,
           MAX(cm.response_latency_ms) AS max_latency_ms,
           COALESCE(SUM(cm.total_tokens), 0) AS total_tokens,
           COALESCE(SUM(cm.prompt_tokens), 0) AS total_prompt_tokens,
           COALESCE(SUM(cm.completion_tokens), 0) AS total_completion_tokens,
           COALESCE(SUM(cm.cached_tokens), 0) AS cached_tokens,
           AVG(CASE WHEN cm.prompt_tokens > 0 THEN cm.cached_tokens::float / cm.prompt_tokens * 100 ELSE NULL END) AS cache_rate,
           AVG(cm.predicted_ms) AS avg_predicted_ms,
           AVG(cm.predicted_per_second) AS avg_prediction_throughput,
           AVG(cm.prompt_per_second) AS avg_prompt_throughput,
           AVG(CASE WHEN cm.draft_n > 0 THEN cm.draft_n_accepted::float / cm.draft_n * 100 ELSE NULL END) AS avg_draft_accepted,
           COUNT(CASE WHEN cm.error_message IS NOT NULL THEN 1 END) AS error_count
    FROM completion_metrics cm
    INNER JOIN users u ON u.id = cm.user_id
    WHERE cm.inserted_at >= NOW() - INTERVAL '1 hour' * $(hours)
      AND cm.user_id IS NOT NULL
    GROUP BY u.email
    ORDER BY requests DESC
    """

    case DbHelpers.run_sql(sql, %{"hours" => hours}) do
      results when is_list(results) ->
        results

      {:error, reason} ->
        Logger.error("Failed to query completion metrics by user: #{inspect(reason)}")
        []
    end
  end

  def aggregate_by_api_key(hours) do
    sql = """
    SELECT COALESCE(uak.name, uak.key_prefix) AS label,
           COUNT(*) AS requests,
           AVG(cm.response_latency_ms) AS avg_latency_ms,
           MIN(cm.response_latency_ms) AS min_latency_ms,
           MAX(cm.response_latency_ms) AS max_latency_ms,
           COALESCE(SUM(cm.total_tokens), 0) AS total_tokens,
           COALESCE(SUM(cm.prompt_tokens), 0) AS total_prompt_tokens,
           COALESCE(SUM(cm.completion_tokens), 0) AS total_completion_tokens,
           COALESCE(SUM(cm.cached_tokens), 0) AS cached_tokens,
           AVG(CASE WHEN cm.prompt_tokens > 0 THEN cm.cached_tokens::float / cm.prompt_tokens * 100 ELSE NULL END) AS cache_rate,
           AVG(cm.predicted_ms) AS avg_predicted_ms,
           AVG(cm.predicted_per_second) AS avg_prediction_throughput,
           AVG(cm.prompt_per_second) AS avg_prompt_throughput,
           AVG(CASE WHEN cm.draft_n > 0 THEN cm.draft_n_accepted::float / cm.draft_n * 100 ELSE NULL END) AS avg_draft_accepted,
           COUNT(CASE WHEN cm.error_message IS NOT NULL THEN 1 END) AS error_count
    FROM completion_metrics cm
    INNER JOIN user_api_keys uak ON uak.id = cm.api_key_id
    WHERE cm.inserted_at >= NOW() - INTERVAL '1 hour' * $(hours)
      AND cm.api_key_id IS NOT NULL
    GROUP BY uak.name, uak.key_prefix
    ORDER BY requests DESC
    """

    case DbHelpers.run_sql(sql, %{"hours" => hours}) do
      results when is_list(results) ->
        results

      {:error, reason} ->
        Logger.error("Failed to query completion metrics by api key: #{inspect(reason)}")
        []
    end
  end

  def timeline_tokens_by_model(hours \\ 24) do
    bucket_minutes =
      cond do
        hours <= 6 -> 15
        hours <= 24 -> 60
        true -> 360
      end

    sql = """
    SELECT
      to_timestamp(
        (extract(epoch from date_trunc('minute', cm.inserted_at))::bigint / $(bucket)::bigint) * $(bucket)::bigint
      ) AS time_bucket,
      cm.model,
      COALESCE(SUM(cm.completion_tokens), 0) AS completion_tokens,
      COALESCE(SUM(cm.prompt_tokens), 0) AS prompt_tokens,
      COALESCE(SUM(cm.cached_tokens), 0) AS cached_tokens
    FROM completion_metrics cm
    WHERE cm.inserted_at >= NOW() - INTERVAL '1 hour' * $(hours)
    GROUP BY time_bucket, cm.model
    ORDER BY time_bucket ASC
    """

    case DbHelpers.run_sql(sql, %{"hours" => hours, "bucket" => bucket_minutes * 60}) do
      results when is_list(results) ->
        results
        |> DbHelpers.rows_apply_datetime_conversion([:time_bucket])

      {:error, reason} ->
        Logger.error("Failed to query token timeline by model: #{inspect(reason)}")
        []
    end
  end
end
