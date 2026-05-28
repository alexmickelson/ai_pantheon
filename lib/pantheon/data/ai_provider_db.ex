defmodule Pantheon.Data.AIProviderDB do
  require Logger
  alias Pantheon.Data.DbHelpers

  def schema do
    Zoi.object(%{
      id: Zoi.uuid(),
      name: Zoi.string(),
      endpoint: Zoi.string(),
      auth_token: Zoi.string(),
      user_id: Zoi.uuid(),
      inserted_at: Zoi.datetime(),
      updated_at: Zoi.datetime()
    })
  end

  def list_by_user(user_id) do
    sql = """
    SELECT id, name, endpoint, auth_token, user_id, inserted_at, updated_at
    FROM ai_providers
    WHERE user_id = $(user_id)
    ORDER BY name ASC
    """

    case DbHelpers.run_sql(sql, %{"user_id" => user_id}, schema()) do
      results when is_list(results) ->
        results

      {:error, reason} ->
        Logger.error(
          "Failed to list ai_providers for user #{inspect(user_id)}: #{inspect(reason)}"
        )

        []
    end
  end

  def create(user_id, attrs) do
    sql = """
    INSERT INTO ai_providers (name, endpoint, auth_token, user_id)
    VALUES ($(name), $(endpoint), $(auth_token), $(user_id))
    RETURNING id, name, endpoint, auth_token, user_id, inserted_at, updated_at
    """

    params = Map.merge(%{"user_id" => user_id}, attrs)

    case DbHelpers.run_sql(sql, params, schema()) do
      [provider | _] ->
        {:ok, provider}

      [] ->
        {:error, :not_found}

      {:error, :db_error} ->
        if unique_violation?(sql, params) do
          {:error, :duplicate_name}
        else
          {:error, :db_error}
        end
    end
  end

  def update(provider_id, attrs) do
    sql = """
    UPDATE ai_providers
    SET name = COALESCE($(name), name),
        endpoint = COALESCE($(endpoint), endpoint),
        auth_token = COALESCE($(auth_token), auth_token)
    WHERE id = $(id)
    RETURNING id, name, endpoint, auth_token, user_id, inserted_at, updated_at
    """

    params = Map.merge(attrs, %{"id" => provider_id})

    case DbHelpers.run_sql(sql, params, schema()) do
      [provider | _] -> {:ok, provider}
      [] -> {:error, :not_found}
      err -> err
    end
  end

  def delete(provider_id) do
    sql = "DELETE FROM ai_providers WHERE id = $(id)"

    case DbHelpers.run_sql(sql, %{"id" => provider_id}) do
      [] -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def load_all_for_cache() do
    sql = """
    SELECT p.id, p.name, p.endpoint, p.auth_token, p.user_id, p.inserted_at, p.updated_at
    FROM ai_providers p
    """

    case DbHelpers.run_sql(sql, %{}, schema()) do
      results when is_list(results) ->
        results

      {:error, reason} ->
        Logger.error("Failed to load all ai_providers for cache: #{inspect(reason)}")
        []
    end
  end

  defp unique_violation?(_sql, _params) do
    false
  end
end
