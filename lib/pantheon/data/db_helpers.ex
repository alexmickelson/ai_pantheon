defmodule Pantheon.Data.DbHelpers do
  require Logger

  @get_named_param ~r/\$\((\w+)\)/

  def run_sql(sql, params, schema) when not is_nil(schema) do
    run_sql(sql, params) |> validate_rows(schema)
  end

  def run_sql(sql, params) do
    original_sql = sql
    original_params = params
    {sql, params} = named_params_to_positional_params(sql, params)

    try do
      result = Ecto.Adapters.SQL.query!(Pantheon.Repo, sql, params)

      Enum.map(result.rows || [], fn row ->
        Enum.zip(result.columns, row)
        |> Enum.map(fn {col, val} -> {col, format_db_value(col, val)} end)
        |> Enum.into(%{})
      end)
    rescue
      exception ->
        Logger.error("Database query failed: #{Exception.message(exception)}")
        Logger.error("Failed SQL: #{original_sql}")
        Logger.error("SQL params: #{inspect(original_params, pretty: true)}")
        {:error, {:db_error, Exception.message(exception)}}
    end
  end

  def named_params_to_positional_params(query, params) do
    param_occurrences = Regex.scan(@get_named_param, query)

    {param_to_index, ordered_values} =
      Enum.reduce(param_occurrences, {%{}, []}, fn [_full, param_name], {index_map, values} ->
        if Map.has_key?(index_map, param_name) do
          {index_map, values}
        else
          next_index = map_size(index_map) + 1
          param_value = params |> Map.fetch!(param_name) |> parse_uuid_string_to_binary()
          {Map.put(index_map, param_name, next_index), values ++ [param_value]}
        end
      end)

    positional_sql =
      Regex.replace(@get_named_param, query, fn _full, param_name ->
        "$#{param_to_index[param_name]}"
      end)

    {positional_sql, ordered_values}
  end

  defp parse_uuid_string_to_binary(
         <<_::binary-size(8), ?-, _::binary-size(4), ?-, _::binary-size(4), ?-, _::binary-size(4),
           ?-, _::binary-size(12)>> = val
       ) do
    val |> String.replace("-", "") |> Base.decode16!(case: :lower)
  end

  defp parse_uuid_string_to_binary(val), do: val

  @datetime_columns ~w(inserted_at updated_at)a

  defp format_db_value(col, val) when col in @datetime_columns do
    convert_datetime(val)
  end

  defp format_db_value(_col, val) do
    format_uuid_binary(val)
  end

  defp convert_datetime({{{y, m, d}, {h, min, s, us}}, {_timezone, offset_min, _tz}})
       when is_integer(us) do
    microsecond = rem(us, 1_000_000)

    %NaiveDateTime{
      year: y,
      month: m,
      day: d,
      hour: h,
      minute: min,
      second: s,
      microsecond: {microsecond, 6}
    }
    |> DateTime.from_naive!(timezone_from_offset(offset_min))
  rescue
    _ -> convert_datetime_fallback(y, m, d, h, min, s, us)
  end

  defp convert_datetime({{{y, m, d}, {h, min, s}}, _}) when is_integer(s) do
    convert_datetime_fallback(y, m, d, h, min, s, 0)
  end

  defp convert_datetime(val), do: val

  defp convert_datetime_fallback(y, m, d, h, min, s, us) do
    %NaiveDateTime{
      year: y,
      month: m,
      day: d,
      hour: h,
      minute: min,
      second: s,
      microsecond: {rem(us, 1_000_000), 6}
    }
    |> DateTime.from_naive!("Etc/UTC")
  end

  defp timezone_from_offset(offset_min) do
    cond do
      offset_min == 0 -> "Etc/UTC"
      offset_min > 0 -> "Etc/GMT-#{Integer.to_string(div(offset_min, 60))}"
      true -> "Etc/GMT+#{Integer.to_string(div(abs(offset_min), 60))}"
    end
  end

  defp format_uuid_binary(<<a::4-bytes, b::2-bytes, c::2-bytes, d::2-bytes, e::6-bytes>>) do
    [a, b, c, d, e]
    |> Enum.map(&Base.encode16(&1, case: :lower))
    |> Enum.join("-")
  end

  defp format_uuid_binary(val), do: val

  def transaction(fun) when is_function(fun, 0) do
    Pantheon.Repo.transaction(fn ->
      result =
        try do
          fun.()
        rescue
          e ->
            Logger.error("Database transaction failed inside callback: #{Exception.message(e)}")
            {:error, e}
        end

      case result do
        {:error, reason} ->
          Logger.error("Database transaction rolled back: #{inspect(reason)}")
          Pantheon.Repo.rollback(reason)

        other ->
          other
      end
    end)
    |> case do
      {:ok, result} ->
        result

      {:error, reason} = err ->
        Logger.error("Database transaction failed to commit: #{inspect(reason)}")
        err
    end
  end

  defp validate_rows({:error, reason}, _schema), do: {:error, reason}

  defp validate_rows(rows, schema) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case Zoi.parse(schema, row, coerce: true) do
        {:ok, valid} ->
          {:cont, {:ok, [valid | acc]}}

        {:error, errors} ->
          Logger.error("Database query result did not match expected schema: #{inspect(errors)}")
          {:halt, {:error, {:validation_error, inspect(errors)}}}
      end
    end)
    |> then(fn
      {:ok, valid_rows} -> Enum.reverse(valid_rows)
      error -> error
    end)
  end
end
