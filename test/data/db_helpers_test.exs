defmodule Pantheon.Data.DbHelpersTest do
  use ExUnit.Case, async: true

  alias Pantheon.Data.DbHelpers

  describe "convert_datetime/1" do
    test "returns nil for nil input" do
      assert DbHelpers.convert_datetime(nil) == nil
    end

    test "converts PG datetime tuple with microseconds" do
      # Format: {{{year, month, day}, {hour, min, sec, microsec}}, {tz_info, offset_min, tz_name}}
      pg_tuple = {{{2026, 5, 28}, {14, 30, 0, 500_000}}, {"Etc/UTC", 0, "Etc/UTC"}}

      result = DbHelpers.convert_datetime(pg_tuple)

      assert %DateTime{} = result
      assert result.year == 2026
      assert result.month == 5
      assert result.day == 28
      assert result.hour == 14
      assert result.minute == 30
      assert result.second == 0
      assert result.microsecond == {500_000, 6}
      assert result.time_zone == "Etc/UTC"
    end

    test "converts PG datetime tuple without microseconds" do
      pg_tuple = {{{2024, 1, 15}, {8, 0, 0}}, {"Etc/UTC", 0, "Etc/UTC"}}

      result = DbHelpers.convert_datetime(pg_tuple)

      assert %DateTime{} = result
      assert result.year == 2024
      assert result.month == 1
      assert result.day == 15
      assert result.hour == 8
      assert result.second == 0
    end

    test "converts PG datetime tuple with timezone offset" do
      # +30 min offset
      pg_tuple = {{{2025, 12, 25}, {12, 0, 0, 0}}, {"Etc/GMT", 30, "Etc/GMT"}}

      result = DbHelpers.convert_datetime(pg_tuple)

      assert %DateTime{} = result
      assert result.year == 2025
      assert result.month == 12
      assert result.day == 25
    end
  end

  describe "format_uuid_binary/1" do
    test "converts 16-byte binary to hyphenated UUID string" do
      # UUID: 18eb94d0-676e-4c9c-9176-6208ebbdc674
      uuid_binary =
        <<0x18, 0xEB, 0x94, 0xD0, 0x67, 0x6E, 0x4C, 0x9C, 0x91, 0x76, 0x62, 0x08, 0xEB, 0xBD,
          0xC6, 0x74>>

      assert DbHelpers.format_uuid_binary(uuid_binary) ==
               "18eb94d0-676e-4c9c-9176-6208ebbdc674"
    end

    test "returns non-uuid values unchanged" do
      assert DbHelpers.format_uuid_binary(nil) == nil
      assert DbHelpers.format_uuid_binary("short") == "short"
      assert DbHelpers.format_uuid_binary(123) == 123
      # 16-byte strings are treated as UUIDs (same as raw PG binaries)
      # This is intentional — PG returns UUIDs as 16-byte binaries
    end
  end

  describe "rows_apply_datetime_conversion/2" do
    setup do
      now_tuple = {{{2026, 5, 28}, {14, 0, 0, 0}}, {"Etc/UTC", 0, "Etc/UTC"}}

      %{now_tuple: now_tuple}
    end

    test "converts specified datetime columns in row maps" do
      now_tuple = {{{2026, 5, 28}, {14, 0, 0, 0}}, {"Etc/UTC", 0, "Etc/UTC"}}

      rows = [
        %{id: "abc", inserted_at: now_tuple, updated_at: now_tuple, name: "test"}
      ]

      result = DbHelpers.rows_apply_datetime_conversion(rows, [:inserted_at, :updated_at])

      assert [%{inserted_at: %DateTime{}, updated_at: %DateTime{}}] = result
    end

    test "leaves nil datetime values as nil" do
      rows = [
        %{id: "abc", expires_at: nil, last_used_at: nil, inserted_at: nil}
      ]

      result =
        DbHelpers.rows_apply_datetime_conversion(
          rows,
          [:expires_at, :last_used_at, :inserted_at]
        )

      assert [%{expires_at: nil, last_used_at: nil, inserted_at: nil}] = result
    end

    test "leaves non-datetime columns untouched" do
      now_tuple = {{{2026, 5, 28}, {14, 0, 0, 0}}, {"Etc/UTC", 0, "Etc/UTC"}}

      rows = [%{id: "abc", name: "provider", inserted_at: now_tuple}]

      result = DbHelpers.rows_apply_datetime_conversion(rows, [:inserted_at])

      assert [%{name: "provider"}] = result
    end

    test "handles empty row list" do
      assert DbHelpers.rows_apply_datetime_conversion([], [:inserted_at]) == []
    end

    test "handles missing datetime columns in row map" do
      rows = [%{id: "abc", name: "test"}]

      result = DbHelpers.rows_apply_datetime_conversion(rows, [:inserted_at, :updated_at])

      assert [%{id: "abc", name: "test"}] = result
    end
  end

  describe "validate_rows/2" do
    test "validates rows against Zoi schema successfully" do
      now = DateTime.utc_now()

      schema =
        Zoi.object(%{
          id: Zoi.uuid(),
          name: Zoi.string(),
          inserted_at: Zoi.datetime()
        })

      rows = [
        %{id: "18eb94d0-676e-4c9c-9176-6208ebbdc674", name: "test", inserted_at: now}
      ]

      result = DbHelpers.validate_rows(rows, schema)

      assert is_list(result)
      assert length(result) == 1
    end

    test "validates rows with nullable datetime fields and nil values" do
      now = DateTime.utc_now()

      schema =
        Zoi.object(%{
          id: Zoi.uuid(),
          name: Zoi.string(),
          expires_at: Zoi.nullish(Zoi.datetime()),
          last_used_at: Zoi.nullish(Zoi.datetime()),
          inserted_at: Zoi.datetime()
        })

      rows = [
        %{
          id: "18eb94d0-676e-4c9c-9176-6208ebbdc674",
          name: "test",
          expires_at: nil,
          last_used_at: nil,
          inserted_at: now
        }
      ]

      result = DbHelpers.validate_rows(rows, schema)

      assert is_list(result)
      assert [%{expires_at: nil, last_used_at: nil}] = result
    end

    test "returns validation error for invalid data" do
      schema = Zoi.object(%{id: Zoi.uuid()})

      rows = [%{id: "not-a-uuid"}]

      result = DbHelpers.validate_rows(rows, schema)

      assert {:error, {:validation_error, _}} = result
    end

    test "passes through error tuples unchanged" do
      result = DbHelpers.validate_rows({:error, {:db_error, "connection failed"}}, nil)

      assert {:error, {:db_error, "connection failed"}} = result
    end

    test "returns empty list for empty input" do
      schema = Zoi.object(%{id: Zoi.uuid()})
      assert DbHelpers.validate_rows([], schema) == []
    end
  end

  describe "full pipeline: raw PG data → conversion → validation" do
    @raw_uuid <<0x18, 0xEB, 0x94, 0xD0, 0x67, 0x6E, 0x4C, 0x9C, 0x91, 0x76, 0x62, 0x08, 0xEB,
                0xBD, 0xC6, 0x74>>

    @now_tuple {{{2026, 5, 28}, {14, 0, 0, 0}}, {"Etc/UTC", 0, "Etc/UTC"}}

    test "user API key row with nullable datetimes" do
      # Simulates: INSERT INTO user_api_keys ... RETURNING all columns
      # PostgreSQL returns UUIDs as binaries, datetimes as tuples, nulls as nil
      # run_sql/2 applies format_uuid_binary to all values, then datetime conversion,
      # then Zoi validates
      uuid_str = DbHelpers.format_uuid_binary(@raw_uuid)

      raw_rows = [
        %{
          id: uuid_str,
          user_id: uuid_str,
          name: "test-key",
          key_hash: "014e7e3b40b11ac5f337ba6389a58b33c7686a8c",
          key_prefix: "sk-panth-66405",
          expires_at: nil,
          last_used_at: nil,
          inserted_at: @now_tuple
        }
      ]

      pipeline_result =
        raw_rows
        |> DbHelpers.rows_apply_datetime_conversion([:expires_at, :last_used_at, :inserted_at])
        |> DbHelpers.validate_rows(Pantheon.Data.UserApiKeyDB.schema())

      assert is_list(pipeline_result)
      assert [%{key_prefix: "sk-panth-66405"} = record] = pipeline_result
      assert record.expires_at == nil
      assert record.last_used_at == nil
      assert %DateTime{} = record.inserted_at
    end

    test "user API key row with non-null expires_at" do
      expires_tuple = {{{2027, 1, 1}, {0, 0, 0, 0}}, {"Etc/UTC", 0, "Etc/UTC"}}
      uuid_str = DbHelpers.format_uuid_binary(@raw_uuid)

      raw_rows = [
        %{
          id: uuid_str,
          user_id: uuid_str,
          name: "test-key-expiry",
          key_hash: "abc123hash",
          key_prefix: "sk-panth-abc12",
          expires_at: expires_tuple,
          last_used_at: nil,
          inserted_at: @now_tuple
        }
      ]

      pipeline_result =
        raw_rows
        |> DbHelpers.rows_apply_datetime_conversion([:expires_at, :last_used_at, :inserted_at])
        |> DbHelpers.validate_rows(Pantheon.Data.UserApiKeyDB.schema())

      assert [%{expires_at: expires_at}] = pipeline_result
      assert %DateTime{} = expires_at
      assert expires_at.year == 2027
    end

    test "user row with all datetime fields populated" do
      updated_tuple = {{{2026, 5, 29}, {10, 30, 0, 0}}, {"Etc/UTC", 0, "Etc/UTC"}}
      uuid_str = DbHelpers.format_uuid_binary(@raw_uuid)

      raw_rows = [
        %{
          id: uuid_str,
          email: "test@example.com",
          inserted_at: @now_tuple,
          updated_at: updated_tuple
        }
      ]

      pipeline_result =
        raw_rows
        |> DbHelpers.rows_apply_datetime_conversion([:inserted_at, :updated_at])
        |> DbHelpers.validate_rows(Pantheon.Data.UserDB.schema())

      assert [%{email: "test@example.com", inserted_at: %DateTime{}, updated_at: %DateTime{}}] =
               pipeline_result
    end
  end
end
