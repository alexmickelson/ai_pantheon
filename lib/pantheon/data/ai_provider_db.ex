defmodule Pantheon.Data.AIProviderDB do
  require Logger
  alias Pantheon.Data.DbHelpers

  @datetime_columns [:inserted_at, :updated_at]

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
    WHERE deleted_at IS NULL
    ORDER BY name ASC
    """

    case DbHelpers.run_sql(sql, %{})
         |> DbHelpers.rows_apply_datetime_conversion(@datetime_columns)
         |> DbHelpers.validate_rows(schema()) do
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

    case DbHelpers.run_sql(sql, params)
         |> DbHelpers.rows_apply_datetime_conversion(@datetime_columns)
         |> DbHelpers.validate_rows(schema()) do
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
    WHERE id = $(id) AND deleted_at IS NULL
    RETURNING id, name, endpoint, auth_token, inserted_at, updated_at
    """

    params = %{
      "id" => provider_id,
      "name" => name,
      "endpoint" => endpoint,
      "auth_token" => auth_token
    }

    case DbHelpers.run_sql(sql, params)
         |> DbHelpers.rows_apply_datetime_conversion(@datetime_columns)
         |> DbHelpers.validate_rows(schema()) do
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
    sql = "UPDATE ai_providers SET deleted_at = NOW() WHERE id = $(id) AND deleted_at IS NULL"

    case DbHelpers.run_sql(sql, %{"id" => provider_id}) do
      [_] ->
        :ok

      [] ->
        {:error,
         "Could not delete AI provider #{inspect(provider_id)}. No active provider found with that ID."}

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
    WHERE deleted_at IS NULL
    """

    case DbHelpers.run_sql(sql, %{})
         |> DbHelpers.rows_apply_datetime_conversion(@datetime_columns)
         |> DbHelpers.validate_rows(schema()) do
      results when is_list(results) ->
        results

      {:error, reason} ->
        Logger.error("Could not load AI providers into cache on startup: #{inspect(reason)}")
        []
    end
  end
end
