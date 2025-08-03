defmodule Sammelkarten.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize Mnesia database before starting other services
    Sammelkarten.Database.init()

    children = [
      SammelkartenWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:sammelkarten, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Sammelkarten.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Sammelkarten.Finch},
      # Start a worker by calling: Sammelkarten.Worker.start_link(arg)
      # {Sammelkarten.Worker, arg},
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
