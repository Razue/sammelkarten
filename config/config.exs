# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :sammelkarten,
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :sammelkarten, SammelkartenWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SammelkartenWeb.ErrorHTML, json: SammelkartenWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Sammelkarten.PubSub,
  live_view: [signing_salt: "wWDyip/0"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  sammelkarten: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  sammelkarten: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Nostr configuration
config :sammelkarten, :nostr,
  # Default Nostr relays for the application
  relays: [
    "wss://relay.damus.io",
    "wss://nos.lol",
    "wss://relay.nostr.band",
    "wss://nostr.wine",
    "wss://relay.snort.social"
  ],
  # Optional dedicated Sammelkarten relay (set to nil to disable)
  dedicated_relay: nil,
  # Custom Sammelkarten event kinds
  custom_kinds: %{
    card_collection: 32121,
    trade_offer: 32122,
    trade_execution: 32123,
    price_alert: 32124,
    portfolio_snapshot: 32125
  },
  # Connection settings
  connection_timeout: 10_000,
  reconnect_interval: 5_000,
  max_reconnect_attempts: 10,
  # Relay discovery settings
  discovery_enabled: true,
  discovery_cache_ttl: 3600,  # 1 hour in seconds
  # Relay performance settings
  health_check_interval: 30_000,  # 30 seconds
  min_relay_count: 2  # Minimum number of connected relays

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
