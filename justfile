setup:
    mix deps.get && mix ecto.setup

reset:
    mix ecto.reset

run-app:
    docker compose up

dev:
    iex -S mix phx.server

test:
    mix test
