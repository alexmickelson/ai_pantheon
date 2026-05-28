defmodule Pantheon.Data.UserApiKeyDB do
  alias Pantheon.Data.DbHelpers

  @key_length 48
  @prefix "sk-panth-"
  @datetime_columns [:expires_at, :last_used_at, :inserted_at]

  def schema do
    Zoi.object(%{
      id: Zoi.uuid(),
      user_id: Zoi.uuid(),
      name: Zoi.string(),
      key_hash: Zoi.string(),
      key_prefix: Zoi.string(),
      expires_at: Zoi.nullish(Zoi.datetime()),
      last_used_at: Zoi.nullish(Zoi.datetime()),
      inserted_at: Zoi.datetime()
    })
  end

  def generate(user_id, name, expires_at \\ nil) do
    full_key =
      "#{@prefix}#{:crypto.strong_rand_bytes(@key_length) |> Base.encode16(case: :lower)}"

    key_hash = :crypto.hash(:sha256, full_key) |> Base.encode16(case: :lower)
    key_prefix = String.slice(full_key, 0, min(14, String.length(full_key)))

    sql = """
    INSERT INTO user_api_keys (user_id, name, key_hash, key_prefix, expires_at)
    VALUES ($(user_id), $(name), $(key_hash), $(key_prefix), $(expires_at))
    RETURNING id, user_id, name, key_hash, key_prefix, expires_at, last_used_at, inserted_at
    """

    params = %{
      "user_id" => user_id,
      "name" => name,
      "key_hash" => key_hash,
      "key_prefix" => key_prefix,
      "expires_at" => expires_at
    }

    case DbHelpers.run_sql(sql, params)
         |> DbHelpers.rows_apply_datetime_conversion(@datetime_columns)
         |> DbHelpers.validate_rows(schema()) do
      [record | _] ->
        {:ok, %{full_key: full_key, key_record: record}}

      [] ->
        {:error, "Could not generate API key. Insert returned no data."}

      {:error, {:db_error, reason}} ->
        {:error, "Could not generate API key. Database error: #{reason}"}

      {:error, {:validation_error, _reason}} ->
        {:error, "Could not generate API key. Returned data failed validation."}
    end
  end

  def list_by_user(user_id) do
    # Exclude the stored hash from results returned to the UI
    sql = """
    SELECT id, user_id, name, key_prefix, expires_at, last_used_at, inserted_at
    FROM user_api_keys
    WHERE user_id = $(user_id)
    ORDER BY inserted_at DESC
    """

    list_schema =
      Zoi.object(%{
        id: Zoi.uuid(),
        user_id: Zoi.uuid(),
        name: Zoi.string(),
        key_prefix: Zoi.string(),
        expires_at: Zoi.nullish(Zoi.datetime()),
        last_used_at: Zoi.nullish(Zoi.datetime()),
        inserted_at: Zoi.datetime()
      })

    case DbHelpers.run_sql(sql, %{"user_id" => user_id})
         |> DbHelpers.rows_apply_datetime_conversion(@datetime_columns)
         |> DbHelpers.validate_rows(list_schema) do
      results when is_list(results) -> results
      {:error, reason} -> {:error, reason}
    end
  end

  def delete(key_id, user_id) do
    sql = """
    DELETE FROM user_api_keys
    WHERE id = $(id) AND user_id = $(user_id)
    RETURNING id
    """

    case DbHelpers.run_sql(sql, %{"id" => key_id, "user_id" => user_id}) do
      [_row] ->
        :ok

      [] ->
        {:error,
         "API key not found or does not belong to you. Key id: #{key_id}. User id: #{user_id}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def validate_key(key_string) do
    key_hash = :crypto.hash(:sha256, key_string) |> Base.encode16(case: :lower)

    lookup_sql = """
    SELECT uak.id, uak.user_id, uak.expires_at
    FROM user_api_keys uak
    INNER JOIN users u ON u.id = uak.user_id
    WHERE uak.key_hash = $(key_hash)
    LIMIT 1
    """

    case DbHelpers.run_sql(lookup_sql, %{"key_hash" => key_hash}) do
      [] ->
        {:error, :invalid_key}

      [%{"id" => key_id, "user_id" => user_id, "expires_at" => expires_at} | _] ->
        case is_expired(expires_at) do
          true ->
            {:error, :key_expired}

          false ->
            touch_last_used(key_id)
            {:ok, user_id}
        end

      {:error, _reason} ->
        {:error, :db_error}
    end
  end

  defp touch_last_used(key_id) do
    update_sql = """
    UPDATE user_api_keys
    SET last_used_at = NOW()
    WHERE id = $(id)
    """

    case DbHelpers.run_sql(update_sql, %{"id" => key_id}) do
      {:error, _reason} -> {:error, :db_error}
      _ -> :ok
    end
  end

  defp is_expired(nil), do: false

  defp is_expired(expires_at) when is_binary(expires_at) do
    case DateTime.from_iso8601(expires_at) do
      {:ok, dt, _offset} -> DateTime.compare(dt, DateTime.utc_now()) != :gt
      {:error, _reason} -> false
    end
  end

  defp is_expired(%DateTime{} = expires_at) do
    DateTime.compare(expires_at, DateTime.utc_now()) != :gt
  end
end
