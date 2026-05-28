defmodule Pantheon.AiProxy.CompletionMetrics do
  @moduledoc """
  Record struct and extraction helpers for AI completion metrics.

  Captures both provider-reported data (usage, timings) and proxy-side
  measurements (wall-clock latency).
  """

  @type t :: %__MODULE__{
          user_id: binary() | nil,
          provider_id: binary(),
          model: String.t(),
          status_code: integer(),

          # Usage (from provider `usage` block)
          prompt_tokens: non_neg_integer() | nil,
          completion_tokens: non_neg_integer() | nil,
          total_tokens: non_neg_integer() | nil,
          cached_tokens: non_neg_integer() | nil,

          # Timings (from llama.cpp `timings` block; NULL for other providers)
          prompt_ms: float() | nil,
          predicted_ms: float() | nil,
          prompt_per_token_ms: float() | nil,
          predicted_per_token_ms: float() | nil,
          prompt_per_second: float() | nil,
          predicted_per_second: float() | nil,
          cache_n: integer() | nil,
          draft_n: integer() | nil,
          draft_n_accepted: integer() | nil,

          # Proxy-side
          response_latency_ms: float(),
          error_message: String.t() | nil
        }

  defstruct user_id: nil,
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
            response_latency_ms: 0.0,
            error_message: nil

  @spec extract_final_chunk(String.t()) :: map() | nil
  def extract_final_chunk(chunk) do
    case chunk |> parse_sse_data() |> Jason.decode() do
      {:ok, json} -> json
      _ -> %{}
    end
  rescue
    _ -> %{}
  end

  @spec from_stream(
          binary() | nil,
          binary() | nil,
          String.t(),
          integer(),
          integer(),
          list(binary()) | nil
        ) :: t()

  def from_stream(
        user_id,
        provider_id,
        model,
        status_code,
        elapsed_ms,
        final_chunks
      ) do
    parsed = extract_final_chunks(final_chunks)
    usage = Map.get(parsed, "usage", %{})
    timings = Map.get(parsed, "timings", %{})

    base = %__MODULE__{
      user_id: user_id,
      provider_id: provider_id,
      model: model,
      status_code: status_code,
      response_latency_ms: elapsed_ms
    }

    base
    |> apply_usage(usage)
    |> apply_timings(timings)
  end

  @spec from_error(
          binary() | nil,
          binary() | nil,
          String.t(),
          integer() | nil,
          integer() | float() | {integer(), integer(), integer()},
          String.t()
        ) :: t()

  def from_error(user_id, provider_id, model, status_code, elapsed_ms, error_message) do
    %__MODULE__{
      user_id: user_id,
      provider_id: provider_id,
      model: model,
      status_code: status_code || 0,
      response_latency_ms: elapsed_ms,
      error_message: error_message
    }
  end

  @spec to_db_map(t()) :: map()
  def to_db_map(%__MODULE__{} = m) do
    Map.from_struct(m)
  end

  # --- Private ---

  defp apply_usage(metrics, usage) do
    metrics
    |> maybe_put(:prompt_tokens, extract_int(usage, "prompt_tokens"))
    |> maybe_put(:completion_tokens, extract_int(usage, "completion_tokens"))
    |> maybe_put(:total_tokens, extract_int(usage, "total_tokens"))
    |> maybe_put(:cached_tokens, extract_cached_tokens(usage))
  end

  defp apply_timings(metrics, timings) do
    metrics
    |> maybe_put(:prompt_ms, extract_float(timings, "prompt_ms"))
    |> maybe_put(:predicted_ms, extract_float(timings, "predicted_ms"))
    |> maybe_put(:prompt_per_token_ms, extract_float(timings, "prompt_per_token_ms"))
    |> maybe_put(:predicted_per_token_ms, extract_float(timings, "predicted_per_token_ms"))
    |> maybe_put(:prompt_per_second, extract_float(timings, "prompt_per_second"))
    |> maybe_put(:predicted_per_second, extract_float(timings, "predicted_per_second"))
    |> maybe_put(:cache_n, extract_int(timings, "cache_n"))
    |> maybe_put(:draft_n, extract_int(timings, "draft_n"))
    |> maybe_put(:draft_n_accepted, extract_int(timings, "draft_n_accepted"))
  end

  defp extract_final_chunks(nil), do: %{}

  defp extract_final_chunks(chunks) do
    chunks
    |> Enum.reduce(%{}, fn chunk, acc ->
      case extract_final_chunk(chunk) do
        json when is_map(json) and map_size(json) > 0 -> Map.merge(acc, json)
        _ -> acc
      end
    end)
  end

  defp parse_sse_data("data: " <> rest), do: rest
  defp parse_sse_data(data), do: data

  defp extract_int(map, key) do
    case Map.get(map, key) do
      val when is_integer(val) -> val
      _ -> nil
    end
  end

  defp extract_float(map, key) do
    case Map.get(map, key) do
      val when is_number(val) -> val
      _ -> nil
    end
  end

  defp extract_cached_tokens(usage) do
    details = Map.get(usage, "prompt_tokens_details", %{})
    extract_int(details, "cached_tokens")
  end

  defp maybe_put(struct, key, nil), do: Map.put(struct, key, nil)
  defp maybe_put(struct, key, val), do: Map.put(struct, key, val)
end
