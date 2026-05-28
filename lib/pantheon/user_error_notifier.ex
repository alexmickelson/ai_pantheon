defmodule Pantheon.UserErrorNotifier do
  @topic_prefix "user_error:"

  @spec broadcast_error(String.t(), String.t()) :: :ok
  def broadcast_error(user_id, message) do
    Phoenix.PubSub.broadcast(
      Pantheon.PubSub,
      "#{@topic_prefix}#{user_id}",
      {:error_broadcast, message}
    )

    :ok
  end
end
