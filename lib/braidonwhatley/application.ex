defmodule App.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AppWeb.Telemetry,
      App.Repo,
      {DNSCluster, query: Application.get_env(:braidonwhatley, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: App.PubSub},
      # Stockfish engine for the contact-gate puzzle's bot defense (degrades
      # gracefully to the core engine if the binary is missing).
      App.Chess.Stockfish,
      # Start to serve requests, typically the last entry
      AppWeb.Endpoint
    ]

    Application.started_applications()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: App.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
