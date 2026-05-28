defmodule Pantheon.Repo do
  use Ecto.Repo,
    otp_app: :pantheon,
    adapter: Ecto.Adapters.Postgres
end
