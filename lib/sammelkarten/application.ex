defmodule Sammelkarten.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize Mnesia database before starting other services
    Sammelkarten.Database.init()

    # Seed database if empty
    Sammelkarten.Seeds.seed_if_empty()

    children = [
      SammelkartenWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:sammelkarten, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Sammelkarten.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Sammelkarten.Finch},
      # Start the market settings manager
      Sammelkarten.MarketSettings,
      # Start the price updater for background price simulation
      Sammelkarten.PriceUpdater,
      # Start the Nostr client for relay connections
      Sammelkarten.Nostr.Client,
      # Start the Nostr indexer for event processing
      Sammelkarten.Nostr.Indexer,
      # Start the price alert watcher
      Sammelkarten.Nostr.PriceAlertWatcher,
      # Start the trading bot system
      Sammelkarten.TradingBot,
      # Start the market maker system
      {Sammelkarten.MarketMaker, [pubkey: "sammelkarten_market_maker"]},
      # Start Nostr relay components
      # {Sammelkarten.Nostr.Relay.Storage, []},
      {Sammelkarten.Nostr.Relay, []},
      # Start to serve requests, typically the last entry
      SammelkartenWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sammelkarten.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SammelkartenWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
