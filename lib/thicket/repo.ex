defmodule Thicket.Repo do
  use Ecto.Repo,
    otp_app: :thicket,
    adapter: Ecto.Adapters.Postgres
end
