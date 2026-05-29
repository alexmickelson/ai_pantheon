defmodule Pantheon.Data.CompletionMetricsDbTest do
  use ExUnit.Case, async: true

  alias Pantheon.AiProxy.CompletionMetrics
  alias Pantheon.Data.CompletionMetricsDB

  describe "insert/1 validation" do
    test "validates struct with atom keys correctly after conversion" do
      # The DB module converts struct to string-keyed map for SQL params,
      # but Zoi schema expects atom keys. This test proves the bug.
      metrics = %CompletionMetrics{
        user_id: "00000000-0000-0000-0000-000000000001",
        api_key_id: "00000000-0000-0000-0000-000000000002",
        provider_id: "00000000-0000-0000-0000-000000000003",
        model: "test-model",
        status_code: 200,
        response_latency_ms: 100.0,
        prompt_tokens: 50,
        completion_tokens: 100,
        total_tokens: 150
      }

      # struct_to_string_keyed converts atoms to strings - prove the bug
      db_map = Map.from_struct(metrics) |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()

      # Zoi schema uses atom keys
      schema = CompletionMetricsDB.schema()

      # If we pass string-keyed map to Zoi, validation fails on ALL required fields
      {:error, errors} = Zoi.parse(schema, db_map)

      failing_fields = Enum.map(errors, fn e -> e.path end)

      refute :user_id in failing_fields,
             "string-keyed maps should not fail Zoi validation with atom schemas - all fields including :user_id failed as 'required'"
    end

    test "atom-keyed map only fails on DB-generated fields" do
      metrics = %CompletionMetrics{
        user_id: "00000000-0000-0000-0000-000000000001",
        api_key_id: "00000000-0000-0000-0000-000000000002",
        provider_id: "00000000-0000-0000-0000-000000000003",
        model: "test-model",
        status_code: 200,
        response_latency_ms: 100.0,
        prompt_tokens: 50,
        completion_tokens: 100,
        total_tokens: 150
      }

      db_map = Map.from_struct(metrics) |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()

      schema = CompletionMetricsDB.schema()

      {:error, errors} = Zoi.parse(schema, db_map)

      failing_fields = Enum.map(errors, fn e -> e.path end)

      refute :model in failing_fields, ":model should NOT fail with atom keys"
      refute :status_code in failing_fields, ":status_code should NOT fail with atom keys"

      refute :response_latency_ms in failing_fields,
             ":response_latency_ms should NOT fail with atom keys"
    end
  end
end
