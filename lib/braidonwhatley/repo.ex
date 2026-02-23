defmodule App.Repo do
  use Ecto.Repo,
    otp_app: :braidonwhatley,
    adapter: Ecto.Adapters.Postgres
end
