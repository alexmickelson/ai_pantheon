defmodule Pantheon.AiProxy.CompletionMetrics do
  defstruct user_id: nil,
            api_key_id: nil,
            provider_id: nil,
            model: nil,
            status_code: nil,
            prompt_tokens: nil,
            completion_tokens: nil,
            total_tokens: nil,
            cached_tokens: nil,
            prompt_ms: nil,
            predicted_ms: nil,
            prompt_per_token_ms: nil,
            predicted_per_token_ms: nil,
            prompt_per_second: nil,
            predicted_per_second: nil,
            cache_n: nil,
            draft_n: nil,
            draft_n_accepted: nil,
            response_latency_ms: 0,
            error_message: nil

  def from_stream(user_id, api_key_id, provider_id, model, status_code, elapsed_ms, chunks) do
    extracted = extracted_metrics(chunks)

    %__MODULE__{
      user_id: user_id,
      api_key_id: api_key_id,
      provider_id: provider_id,
      model: model,
      status_code: status_code,
      response_latency_ms: elapsed_ms,
      prompt_tokens: extracted[:prompt_tokens],
      completion_tokens: extracted[:completion_tokens],
      total_tokens: extracted[:total_tokens],
      cached_tokens: extracted[:cached_tokens],
      prompt_ms: extracted[:prompt_ms],
      predicted_ms: extracted[:predicted_ms],
      prompt_per_token_ms: extracted[:prompt_per_token_ms],
      predicted_per_token_ms: extracted[:predicted_per_token_ms],
      prompt_per_second: extracted[:prompt_per_second],
      predicted_per_second: extracted[:predicted_per_second],
      cache_n: extracted[:cache_n],
      draft_n: extracted[:draft_n],
      draft_n_accepted: extracted[:draft_n_accepted]
    }
  end

  def from_error(user_id, api_key_id, provider_id, model, status_code, elapsed_ms, error_message) do
    %__MODULE__{
      user_id: user_id,
      api_key_id: api_key_id,
      provider_id: provider_id,
      model: model,
      status_code: status_code || 0,
      response_latency_ms: elapsed_ms,
      error_message: error_message
    }
  end

  def from_response(
        user_id,
        api_key_id,
        provider_id,
        model,
        status_code,
        elapsed_ms,
        resp_body
      ) do
    usage = Map.get(resp_body, "usage", %{})
    timings = Map.get(resp_body, "timings", %{})

    extracted =
      empty_metric_fields()
      |> merge_usage(usage)
      |> merge_timings(timings)
      |> backfill_tokens_from_timings(timings)

    %__MODULE__{
      user_id: user_id,
      api_key_id: api_key_id,
      provider_id: provider_id,
      model: model,
      status_code: status_code,
      response_latency_ms: elapsed_ms,
      prompt_tokens: extracted[:prompt_tokens],
      completion_tokens: extracted[:completion_tokens],
      total_tokens: extracted[:total_tokens],
      cached_tokens: extracted[:cached_tokens],
      prompt_ms: extracted[:prompt_ms],
      predicted_ms: extracted[:predicted_ms],
      prompt_per_token_ms: extracted[:prompt_per_token_ms],
      predicted_per_token_ms: extracted[:predicted_per_token_ms],
      prompt_per_second: extracted[:prompt_per_second],
      predicted_per_second: extracted[:predicted_per_second],
      cache_n: extracted[:cache_n],
      draft_n: extracted[:draft_n],
      draft_n_accepted: extracted[:draft_n_accepted]
    }
  end

  def extract_metrics(chunks \\ [])

  def extract_metrics(nil), do: empty_metric_fields()
  def extract_metrics([]), do: empty_metric_fields()

  def extract_metrics(raw_chunks) do
    parsed = decode_sse_list(raw_chunks)
    usage = find_map_key(parsed, :usage)
    timings = find_last_map_key(parsed, :timings) || %{}

    empty_metric_fields()
    |> merge_usage(usage)
    |> merge_timings(timings)
    |> backfill_tokens_from_timings(timings)
  end

  defp extracted_metrics(nil), do: %{}
  defp extracted_metrics([]), do: %{}

  defp extracted_metrics(raw_chunks) do
    parsed = decode_sse_list(raw_chunks)
    usage = find_map_key(parsed, :usage)
    timings = find_last_map_key(parsed, :timings) || %{}

    empty_metric_fields()
    |> merge_usage(usage)
    |> merge_timings(timings)
    |> backfill_tokens_from_timings(timings)
  end

  defp empty_metric_fields do
    %{
      prompt_tokens: nil,
      completion_tokens: nil,
      total_tokens: nil,
      cached_tokens: nil,
      prompt_ms: nil,
      predicted_ms: nil,
      prompt_per_token_ms: nil,
      predicted_per_token_ms: nil,
      prompt_per_second: nil,
      predicted_per_second: nil,
      cache_n: nil,
      draft_n: nil,
      draft_n_accepted: nil
    }
  end

  defp decode_sse_list(list) when is_list(list) do
    for raw <- list,
        json = decode_sse(raw),
        is_map(json),
        into: [],
        do: json
  end

  defp decode_sse("data: " <> rest) do
    decode_json(rest)
  end

  defp decode_sse(raw) do
    decode_json(raw)
  end

  defp decode_json(raw) do
    case Jason.decode(raw, keys: :atoms) do
      {:ok, json} -> json
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp find_map_key(chunks, key) do
    Enum.find_value(chunks, %{}, fn chunk ->
      if Map.has_key?(chunk, key) do
        Map.get(chunk, key)
      else
        nil
      end
    end)
  end

  defp find_last_map_key(chunks, key) do
    chunks
    |> Enum.reverse()
    |> find_map_key(key)
  end

  @usage_schema Zoi.object(%{
                  prompt_tokens: Zoi.optional(Zoi.integer()),
                  completion_tokens: Zoi.optional(Zoi.integer()),
                  total_tokens: Zoi.optional(Zoi.integer()),
                  prompt_tokens_details:
                    Zoi.optional(Zoi.object(%{cached_tokens: Zoi.optional(Zoi.integer())}))
                })

  @timings_schema Zoi.object(%{
                    prompt_n: Zoi.optional(Zoi.integer()),
                    predicted_n: Zoi.optional(Zoi.integer()),
                    prompt_ms: Zoi.nullish(Zoi.float()),
                    predicted_ms: Zoi.nullish(Zoi.float()),
                    prompt_per_token_ms: Zoi.nullish(Zoi.float()),
                    predicted_per_token_ms: Zoi.nullish(Zoi.float()),
                    prompt_per_second: Zoi.nullish(Zoi.float()),
                    predicted_per_second: Zoi.nullish(Zoi.float()),
                    cache_n: Zoi.optional(Zoi.integer()),
                    draft_n: Zoi.optional(Zoi.integer()),
                    draft_n_accepted: Zoi.optional(Zoi.integer())
                  })

  defp merge_usage(result, %{} = raw) do
    with {:ok, usage} <- Zoi.parse(@usage_schema, raw, coerce: true) do
      cached_tokens = Map.get(Map.get(usage, :prompt_tokens_details, %{}), :cached_tokens)

      result
      |> put_field(:prompt_tokens, usage, :prompt_tokens)
      |> put_field(:completion_tokens, usage, :completion_tokens)
      |> put_field(:total_tokens, usage, :total_tokens)
      |> maybe_put(:cached_tokens, if(is_integer(cached_tokens), do: cached_tokens))
    else
      _ -> result
    end
  end

  defp merge_usage(result, _), do: result

  defp merge_timings(result, %{} = raw) do
    with {:ok, timings} <- Zoi.parse(@timings_schema, raw, coerce: true) do
      result
      |> put_field(:prompt_ms, timings, :prompt_ms)
      |> put_field(:predicted_ms, timings, :predicted_ms)
      |> put_field(:prompt_per_token_ms, timings, :prompt_per_token_ms)
      |> put_field(:predicted_per_token_ms, timings, :predicted_per_token_ms)
      |> put_field(:prompt_per_second, timings, :prompt_per_second)
      |> put_field(:predicted_per_second, timings, :predicted_per_second)
      |> put_field(:cache_n, timings, :cache_n)
      |> put_field(:draft_n, timings, :draft_n)
      |> put_field(:draft_n_accepted, timings, :draft_n_accepted)
    else
      _ -> result
    end
  end

  defp merge_timings(result, _), do: result

  defp backfill_tokens_from_timings(%{prompt_tokens: pt, completion_tokens: ct} = m, _)
       when is_integer(pt) and is_integer(ct) do
    m
  end

  defp backfill_tokens_from_timings(result, %{} = raw) do
    case Zoi.parse(@timings_schema, raw, coerce: true) do
      {:ok, t} ->
        prompt_n = Map.get(t, :prompt_n)
        predicted_n = Map.get(t, :predicted_n)
        cache_n = Map.get(t, :cache_n)

        result
        |> maybe_put(:prompt_tokens, if(is_integer(prompt_n), do: prompt_n))
        |> maybe_put(:completion_tokens, if(is_integer(predicted_n), do: predicted_n))
        |> maybe_put(
          :total_tokens,
          if(is_integer(prompt_n) and is_integer(predicted_n), do: prompt_n + predicted_n)
        )
        |> maybe_put(:cached_tokens, if(is_integer(cache_n), do: cache_n))

      _ ->
        result
    end
  end

  defp backfill_tokens_from_timings(result, _), do: result

  defp put_field(acc, dest_key, source, source_key) do
    case Map.get(source, source_key) do
      val when is_number(val) or is_nil(val) -> Map.put(acc, dest_key, val)
      _ -> acc
    end
  end

  defp maybe_put(acc, _key, nil), do: acc
  defp maybe_put(acc, key, val), do: Map.put(acc, key, val)
end
