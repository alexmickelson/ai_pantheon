defmodule Pantheon.Data.AIProviderDB do
  require Logger
  alias Pantheon.Data.DbHelpers

  def schema do
    Zoi.object(%{
      id: Zoi.uuid(),
      name: Zoi.string(),
      endpoint: Zoi.string(),
      auth_token: Zoi.string(),
      inserted_at: Zoi.datetime(),
      updated_at: Zoi.datetime()
    })
  end

  def list_all() do
    sql = """
    SELECT id, name, endpoint, auth_token, inserted_at, updated_at
    FROM ai_providers
    ORDER BY name ASC
    """

    case DbHelpers.run_sql(sql, %{}, schema()) do
      results when is_list(results) ->
        results

      {:error, reason} ->
        Logger.error("Could not load AI providers: #{inspect(reason)}")

        []
    end
  end

  def create(%{"name" => name, "endpoint" => endpoint, "auth_token" => auth_token}) do
    sql = """
    INSERT INTO ai_providers (name, endpoint, auth_token)
    VALUES ($(name), $(endpoint), $(auth_token))
    RETURNING id, name, endpoint, auth_token, inserted_at, updated_at
    """

    params = %{
      "name" => name,
      "endpoint" => endpoint,
      "auth_token" => auth_token
    }

    case DbHelpers.run_sql(sql, params, schema()) do
      [provider | _] ->
        {:ok, provider}

      [] ->
        {:error, "Could not create AI provider '#{name}'. Insert returned no data."}

      {:error, {:db_error, reason}} ->
        msg = "Could not create AI provider '#{name}'. Database error: #{reason}"
        Logger.error(msg)
        {:error, msg}

      {:error, {:validation_error, reason}} ->
        Logger.error(
          "Creating AI provider '#{name}' failed schema validation on returned data: #{inspect(reason)}"
        )

        {:error, "Could not create AI provider '#{name}'. Returned data failed validation."}
    end
  end

  def update(provider_id, %{"name" => name, "endpoint" => endpoint, "auth_token" => auth_token}) do
    sql = """
    UPDATE ai_providers
    SET name = COALESCE($(name), name),
        endpoint = COALESCE($(endpoint), endpoint),
        auth_token = COALESCE($(auth_token), auth_token)
    WHERE id = $(id)
    RETURNING id, name, endpoint, auth_token, inserted_at, updated_at
    """

    params = %{
      "id" => provider_id,
      "name" => name,
      "endpoint" => endpoint,
      "auth_token" => auth_token
    }

    case DbHelpers.run_sql(sql, params, schema()) do
      [provider | _] ->
        {:ok, provider}

      [] ->
        {:error,
         "Could not update AI provider #{inspect(provider_id)}. No provider found with that ID."}

      {:error, {:db_error, reason}} ->
        msg = "Could not update AI provider #{inspect(provider_id)}. Database error: #{reason}"
        Logger.error(msg)
        {:error, msg}

      {:error, {:validation_error, reason}} ->
        Logger.error(
          "Updating AI provider #{inspect(provider_id)} failed schema validation on returned data: #{inspect(reason)}"
        )

        {:error, "Could not update AI provider. Returned data failed validation."}
    end
  end

  def delete(provider_id) do
    sql = "DELETE FROM ai_providers WHERE id = $(id)"

    case DbHelpers.run_sql(sql, %{"id" => provider_id}) do
      [] ->
        :ok

      {:error, {:db_error, reason}} ->
        msg = "Could not delete AI provider #{inspect(provider_id)}. Database error: #{reason}"
        Logger.error(msg)
        {:error, msg}
    end
  end

  def load_all_for_cache() do
    sql = """
    SELECT id, name, endpoint, auth_token, inserted_at, updated_at
    FROM ai_providers
    """

    case DbHelpers.run_sql(sql, %{}, schema()) do
      results when is_list(results) ->
        results

      {:error, reason} ->
        Logger.error("Could not load AI providers into cache on startup: #{inspect(reason)}")
        []
    end
  end
end
