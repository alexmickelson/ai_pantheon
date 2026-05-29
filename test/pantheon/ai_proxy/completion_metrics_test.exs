defmodule Pantheon.AiProxy.CompletionMetricsTest do
  use ExUnit.Case, async: true

  alias Pantheon.AiProxy.CompletionMetrics

  describe "extract_metrics/1" do
    test "returns empty metrics for nil input" do
      assert CompletionMetrics.extract_metrics(nil) == %{
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

    test "returns empty metrics for empty list" do
      assert CompletionMetrics.extract_metrics([]) == %{
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

    test "extracts usage from plain JSON chunks without data prefix" do
      # Req.parse_message strips the SSE "data: " prefix and returns plain JSON strings
      # This is what request_worker actually accumulates and passes to extract_metrics
      chunks = [
        "{\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}",
        "{\"choices\":[{\"finish_reason\":\"stop\",\"delta\":{}}],\"usage\":{\"prompt_tokens\":50,\"completion_tokens\":100,\"total_tokens\":150}}"
      ]

      result = CompletionMetrics.extract_metrics(chunks)

      assert result.prompt_tokens == 50,
             "expected prompt_tokens=50 but got #{inspect(result.prompt_tokens)}"

      assert result.completion_tokens == 100,
             "expected completion_tokens=100 but got #{inspect(result.completion_tokens)}"

      assert result.total_tokens == 150,
             "expected total_tokens=150 but got #{inspect(result.total_tokens)}"
    end

    test "extracts timings from plain JSON chunks without data prefix" do
      chunks = [
        "{\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}",
        "{\"choices\":[{\"finish_reason\":\"stop\",\"delta\":{}}],\"timings\":{\"prompt_n\":30,\"predicted_n\":60,\"prompt_ms\":5.5,\"predicted_ms\":55.5}}"
      ]

      result = CompletionMetrics.extract_metrics(chunks)

      assert result.prompt_tokens == 30,
             "expected prompt_tokens=30 but got #{inspect(result.prompt_tokens)}"

      assert result.completion_tokens == 60,
             "expected completion_tokens=60 but got #{inspect(result.completion_tokens)}"

      assert_in_delta(result.prompt_ms, 5.5, 0.01)
      assert_in_delta(result.predicted_ms, 55.5, 0.01)
    end

    test "extracts both usage and timings from plain JSON chunks" do
      chunks = [
        "{\"choices\":[{\"finish_reason\":\"stop\",\"delta\":{}}],\"usage\":{\"prompt_tokens\":100,\"completion_tokens\":200,\"total_tokens\":300},\"timings\":{\"prompt_n\":50,\"predicted_n\":80,\"prompt_ms\":10.0,\"predicted_ms\":100.0}}"
      ]

      result = CompletionMetrics.extract_metrics(chunks)

      assert result.prompt_tokens == 100,
             "expected prompt_tokens=100 but got #{inspect(result.prompt_tokens)}"

      assert result.completion_tokens == 200
      assert_in_delta(result.prompt_ms, 10.0, 0.01)
      assert_in_delta(result.predicted_ms, 100.0, 0.01)
    end

    test "extracts timings from llama.cpp-style stream (no usage block)" do
      chunks = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}",
        """
        data: {"choices":[{"finish_reason":"stop","delta":{}}],
        "timings":{"cache_n":0,"prompt_n":12,"prompt_ms":86.634,
        "prompt_per_token_ms":7.2195,"prompt_per_second":138.5137,
        "predicted_n":251,"predicted_ms":1937.619,
        "predicted_per_token_ms":9.4981,"predicted_per_second":105.2838,
        "draft_n":198,"draft_n_accepted":140}}
        """
      ]

      result = CompletionMetrics.extract_metrics(chunks)

      # Tokens derived from timings since no usage block exists
      assert result.prompt_tokens == 12
      assert result.completion_tokens == 251
      assert result.total_tokens == 263
      assert result.cached_tokens == 0

      # Timings extracted correctly
      assert_in_delta(result.prompt_ms, 86.634, 0.01)
      assert_in_delta(result.predicted_ms, 1937.619, 0.01)
      assert_in_delta(result.prompt_per_token_ms, 7.2195, 0.01)
      assert_in_delta(result.predicted_per_token_ms, 9.4981, 0.01)
      assert result.cache_n == 0
      assert result.draft_n == 198
      assert result.draft_n_accepted == 140
    end

    test "extracts usage from OpenAI-compatible stream with usage block" do
      chunks = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}",
        "data: {\"choices\":[{\"finish_reason\":\"stop\",\"delta\":{}}],\"usage\":{\"prompt_tokens\":50,\"completion_tokens\":100,\"total_tokens\":150,\"prompt_tokens_details\":{\"cached_tokens\":20}}}"
      ]

      result = CompletionMetrics.extract_metrics(chunks)

      assert result.prompt_tokens == 50
      assert result.completion_tokens == 100
      assert result.total_tokens == 150
      assert result.cached_tokens == 20

      # No timings present
      assert result.prompt_ms == nil
      assert result.predicted_ms == nil
    end

    test "extracts both usage and timings when both are present" do
      chunks = [
        "data: {\"choices\":[{\"finish_reason\":\"stop\",\"delta\":{}}],\"usage\":{\"prompt_tokens\":100,\"completion_tokens\":200,\"total_tokens\":300},\"timings\":{\"prompt_n\":50,\"predicted_n\":80,\"prompt_ms\":10.0,\"predicted_ms\":100.0}}"
      ]

      result = CompletionMetrics.extract_metrics(chunks)

      # Usage takes precedence over timings for token counts
      assert result.prompt_tokens == 100
      assert result.completion_tokens == 200
      assert result.total_tokens == 300

      # Timings still extracted
      assert_in_delta(result.prompt_ms, 10.0, 0.01)
      assert_in_delta(result.predicted_ms, 100.0, 0.01)
    end

    test "uses timings prompt_n/predicted_n when usage is missing" do
      chunks = [
        "data: {\"choices\":[{\"finish_reason\":\"stop\",\"delta\":{}}],\"timings\":{\"prompt_n\":30,\"predicted_n\":60,\"prompt_ms\":5.5,\"predicted_ms\":55.5}}"
      ]

      result = CompletionMetrics.extract_metrics(chunks)

      assert result.prompt_tokens == 30
      assert result.completion_tokens == 60
      assert result.total_tokens == 90
    end

    test "handles malformed chunks gracefully" do
      chunks = [
        "data: {invalid json",
        "not even sse format",
        "data: {\"choices\":[{\"finish_reason\":\"stop\"}],\"timings\":{\"prompt_n\":10,\"predicted_n\":20,\"prompt_ms\":1.0}}"
      ]

      result = CompletionMetrics.extract_metrics(chunks)

      assert result.prompt_tokens == 10
      assert result.completion_tokens == 20
    end

    test "prefers last timings block when multiple chunks have timings" do
      chunks = [
        "data: {\"timings\":{\"prompt_n\":5,\"predicted_n\":10}}",
        "data: {\"timings\":{\"prompt_n\":50,\"predicted_n\":60}}"
      ]

      result = CompletionMetrics.extract_metrics(chunks)

      assert result.prompt_tokens == 50
      assert result.completion_tokens == 60
    end

    test "extracts usage and timings from real final chunk (snow-ai-server response)" do
      # Real final chunk from snow-ai-server with both usage and timings blocks
      final_chunk = """
      data: {"choices":[],"created":1780070846,"id":"chatcmpl-GeuuwIVaKZnXsGl4x0Xu5MCo5rPZYWlm","model":"qwen3.6-27b","system_fingerprint":"b9404-241cbd41d","object":"chat.completion.chunk","usage":{"completion_tokens":248,"prompt_tokens":18,"total_tokens":266,"prompt_tokens_details":{"cached_tokens":14}},"timings":{"cache_n":14,"prompt_n":4,"prompt_ms":35.793,"prompt_per_token_ms":8.94825,"prompt_per_second":111.7536948565362,"predicted_n":248,"predicted_ms":2340.449,"predicted_per_token_ms":9.43729435483871,"predicted_per_second":105.9625738480095,"draft_n":243,"draft_n_accepted":169}}
      """

      chunks = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}",
        final_chunk
      ]

      result = CompletionMetrics.extract_metrics(chunks)

      # Usage takes precedence for token counts
      assert result.prompt_tokens == 18
      assert result.completion_tokens == 248
      assert result.total_tokens == 266
      assert result.cached_tokens == 14

      # All timing fields extracted from timings block
      assert_in_delta(result.prompt_ms, 35.793, 0.01)
      assert_in_delta(result.predicted_ms, 2340.449, 0.01)
      assert_in_delta(result.prompt_per_token_ms, 8.94825, 0.01)
      assert_in_delta(result.predicted_per_token_ms, 9.43729435483871, 0.01)
      assert_in_delta(result.prompt_per_second, 111.7536948565362, 0.01)
      assert_in_delta(result.predicted_per_second, 105.9625738480095, 0.01)
      assert result.cache_n == 14
      assert result.draft_n == 243
      assert result.draft_n_accepted == 169
    end

    test "usage token counts take precedence over timing-derived counts" do
      # prompt_tokens (18) != prompt_n (4), usage should win
      final_chunk = """
      data: {"usage":{"prompt_tokens":18,"completion_tokens":248,"total_tokens":266},"timings":{"prompt_n":4,"predicted_n":248}}
      """

      result = CompletionMetrics.extract_metrics([final_chunk])

      assert result.prompt_tokens == 18
      assert result.completion_tokens == 248
      assert result.total_tokens == 266
    end
  end

  describe "from_stream/7" do
    test "builds complete metrics struct from stream chunks" do
      chunks = [
        """
        data: {"choices":[{"finish_reason":"stop","delta":{}}],
        "timings":{"cache_n":2,"prompt_n":15,"prompt_ms":80.0,
        "prompt_per_token_ms":5.33,"prompt_per_second":187.5,
        "predicted_n":200,"predicted_ms":1500.0,
        "predicted_per_token_ms":7.5,"predicted_per_second":133.33,
        "draft_n":150,"draft_n_accepted":100}}
        """
      ]

      metrics =
        CompletionMetrics.from_stream(
          "user-uuid",
          "key-uuid",
          "provider-uuid",
          "gpt-4",
          200,
          1600,
          chunks
        )

      assert metrics.user_id == "user-uuid"
      assert metrics.api_key_id == "key-uuid"
      assert metrics.provider_id == "provider-uuid"
      assert metrics.model == "gpt-4"
      assert metrics.status_code == 200
      assert_in_delta(metrics.response_latency_ms, 1600, 1)
      assert metrics.prompt_tokens == 15
      assert metrics.completion_tokens == 200
      assert metrics.total_tokens == 215
      assert metrics.cached_tokens == 2
      assert_in_delta(metrics.prompt_ms, 80.0, 0.01)
      assert_in_delta(metrics.predicted_ms, 1500.0, 0.01)
      assert metrics.draft_n == 150
      assert metrics.draft_n_accepted == 100
    end

    test "returns all nil for token fields when no usage or timings" do
      chunks = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}"
      ]

      metrics =
        CompletionMetrics.from_stream(
          nil,
          nil,
          nil,
          "model",
          200,
          100,
          chunks
        )

      assert metrics.prompt_tokens == nil
      assert metrics.completion_tokens == nil
      assert metrics.total_tokens == nil
    end

    test "handles nil final_chunks" do
      metrics =
        CompletionMetrics.from_stream(
          "user",
          "key",
          "provider",
          "model",
          200,
          50,
          nil
        )

      assert metrics.prompt_tokens == nil
      assert metrics.response_latency_ms == 50
    end

    test "builds complete metrics from real snow-ai-server final chunk" do
      final_chunk = """
      data: {"choices":[],"created":1780070846,"id":"chatcmpl-GeuuwIVaKZnXsGl4x0Xu5MCo5rPZYWlm","model":"qwen3.6-27b","system_fingerprint":"b9404-241cbd41d","object":"chat.completion.chunk","usage":{"completion_tokens":248,"prompt_tokens":18,"total_tokens":266,"prompt_tokens_details":{"cached_tokens":14}},"timings":{"cache_n":14,"prompt_n":4,"prompt_ms":35.793,"prompt_per_token_ms":8.94825,"prompt_per_second":111.7536948565362,"predicted_n":248,"predicted_ms":2340.449,"predicted_per_token_ms":9.43729435483871,"predicted_per_second":105.9625738480095,"draft_n":243,"draft_n_accepted":169}}
      """

      metrics =
        CompletionMetrics.from_stream(
          "f3a1b2c3-d4e5-6f78-90ab-cdef12345678",
          "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
          "12345678-abcd-ef12-3456-7890abcdef12",
          "qwen3.6-27b",
          200,
          2400.5,
          [
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hello, how can I help you today?\"}}]}",
            final_chunk
          ]
        )

      assert metrics.user_id == "f3a1b2c3-d4e5-6f78-90ab-cdef12345678"
      assert metrics.api_key_id == "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      assert metrics.provider_id == "12345678-abcd-ef12-3456-7890abcdef12"
      assert metrics.model == "qwen3.6-27b"
      assert metrics.status_code == 200
      assert_in_delta(metrics.response_latency_ms, 2400.5, 0.01)

      # Token counts from usage
      assert metrics.prompt_tokens == 18
      assert metrics.completion_tokens == 248
      assert metrics.total_tokens == 266
      assert metrics.cached_tokens == 14

      # Timing fields
      assert_in_delta(metrics.prompt_ms, 35.793, 0.01)
      assert_in_delta(metrics.predicted_ms, 2340.449, 0.01)
      assert_in_delta(metrics.prompt_per_token_ms, 8.94825, 0.01)
      assert_in_delta(metrics.predicted_per_token_ms, 9.43729435483871, 0.01)
      assert_in_delta(metrics.prompt_per_second, 111.7536948565362, 0.01)
      assert_in_delta(metrics.predicted_per_second, 105.9625738480095, 0.01)
      assert metrics.cache_n == 14
      assert metrics.draft_n == 243
      assert metrics.draft_n_accepted == 169
    end
  end

  describe "from_error/7" do
    test "captures error details" do
      metrics =
        CompletionMetrics.from_error(
          "user-uuid",
          "key-uuid",
          "provider-uuid",
          "gpt-4",
          500,
          100,
          "Internal server error"
        )

      assert metrics.user_id == "user-uuid"
      assert metrics.provider_id == "provider-uuid"
      assert metrics.status_code == 500
      assert_in_delta(metrics.response_latency_ms, 100, 1)
      assert metrics.error_message == "Internal server error"
      assert metrics.prompt_tokens == nil
    end

    test "handles nil status code" do
      metrics =
        CompletionMetrics.from_error(
          nil,
          nil,
          nil,
          "model",
          nil,
          50,
          "connection refused"
        )

      assert metrics.status_code == 0
      assert metrics.error_message == "connection refused"
    end
  end
end
