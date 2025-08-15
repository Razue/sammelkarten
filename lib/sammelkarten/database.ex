defmodule Sammelkarten.Database do
  @moduledoc """
  Database management module for Mnesia configuration and initialization.

  This module handles:
  - Mnesia node configuration and startup
  - Table creation and schema management
  - Database initialization and seeding
  """

  require Logger

  @doc """
  Initialize Mnesia database with required tables.
  """
  def init do
    Logger.info("Initializing Mnesia database...")

    # Create schema if it doesn't exist
    case :mnesia.create_schema([node()]) do
      :ok ->
        Logger.info("Mnesia schema created successfully")

      {:error, {_, {:already_exists, _}}} ->
        Logger.info("Mnesia schema already exists")

      {:error, reason} ->
        Logger.error("Failed to create Mnesia schema: #{inspect(reason)}")
    end

    # Start Mnesia
    case :mnesia.start() do
      :ok ->
        Logger.info("Mnesia started successfully")

      {:error, reason} ->
        Logger.error("Failed to start Mnesia: #{inspect(reason)}")
        raise "Cannot start Mnesia: #{inspect(reason)}"
    end

    # Create tables
    create_tables()

    Logger.info("Mnesia database initialization complete")
  end

  @doc """
  Create all required Mnesia tables.
  """
  def create_tables do
    # Create cards table
    create_cards_table()

    # Create price_history table
    create_price_history_table()

    # Create user_preferences table
    create_user_preferences_table()

    # Create Nostr-related tables
    create_nostr_users_table()
    create_user_collections_table()
    create_user_trades_table()
    create_user_portfolios_table()

    # Wait for tables to be available
    :mnesia.wait_for_tables(
      [
        :cards,
        :price_history,
        :user_preferences,
        :nostr_users,
        :user_collections,
        :user_trades,
        :user_portfolios
      ],
      5000
    )
  end

  defp create_cards_table do
    table_def = [
      attributes: [
        :id,
        :name,
        :slug,
        :image_path,
        :current_price,
        :price_change_24h,
        :price_change_percentage,
        :rarity,
        :description,
        :last_updated
      ],
      ram_copies: [node()],
      type: :set
    ]

    case :mnesia.create_table(:cards, table_def) do
      {:atomic, :ok} ->
        Logger.info("Cards table created successfully")

      {:aborted, {:already_exists, :cards}} ->
        Logger.info("Cards table already exists")

      {:aborted, reason} ->
        Logger.error("Failed to create cards table: #{inspect(reason)}")
    end
  end

  defp create_price_history_table do
    table_def = [
      attributes: [
        :id,
        :card_id,
        :price,
        :timestamp,
        :volume
      ],
      ram_copies: [node()],
      type: :ordered_set,
      index: [:card_id, :timestamp]
    ]

    case :mnesia.create_table(:price_history, table_def) do
      {:atomic, :ok} ->
        Logger.info("Price history table created successfully")

      {:aborted, {:already_exists, :price_history}} ->
        Logger.info("Price history table already exists")

      {:aborted, reason} ->
        Logger.error("Failed to create price history table: #{inspect(reason)}")
    end
  end

  defp create_user_preferences_table do
    table_def = [
      attributes: [
        :user_id,
        :refresh_rate,
        :theme,
        :notifications_enabled,
        :sound_enabled,
        :auto_refresh,
        :cards_per_page,
        :default_sort,
        :default_sort_direction,
        :show_ticker,
        :ticker_speed,
        :chart_style,
        :price_alerts,
        :created_at,
        :updated_at
      ],
      ram_copies: [node()],
      type: :set
    ]

    case :mnesia.create_table(:user_preferences, table_def) do
      {:atomic, :ok} ->
        Logger.info("User preferences table created successfully")

      {:aborted, {:already_exists, :user_preferences}} ->
        Logger.info("User preferences table already exists")

      {:aborted, reason} ->
        Logger.error("Failed to create user preferences table: #{inspect(reason)}")
    end
  end

  @doc """
  Stop Mnesia database.
  """
  def stop do
    Logger.info("Stopping Mnesia database...")
    :mnesia.stop()
  end

  @doc """
  Get information about Mnesia tables.
  """
  def info do
    Logger.info("Mnesia system info:")
    :mnesia.info()
  end

  defp create_nostr_users_table do
    table_def = [
      attributes: [
        # Primary key - hex public key
        :pubkey,
        # Bech32 encoded public key
        :npub,
        # User name from metadata
        :name,
        # Display name from metadata
        :display_name,
        # About text from metadata
        :about,
        # Profile picture URL
        :picture,
        # NIP-05 identifier
        :nip05,
        # Lightning address
        :lud16,
        # When metadata was last updated
        :metadata_updated_at,
        # When user record was created
        :created_at,
        # Last activity timestamp
        :last_seen
      ],
      ram_copies: [node()],
      type: :set
    ]

    case :mnesia.create_table(:nostr_users, table_def) do
      {:atomic, :ok} ->
        Logger.info("Nostr users table created successfully")

      {:aborted, {:already_exists, :nostr_users}} ->
        Logger.info("Nostr users table already exists")

      {:aborted, reason} ->
        Logger.error("Failed to create nostr users table: #{inspect(reason)}")
    end
  end

  defp create_user_collections_table do
    table_def = [
      attributes: [
        # Unique identifier
        :id,
        # Owner's public key
        :user_pubkey,
        # Card identifier
        :card_id,
        # Number of cards owned
        :quantity,
        # When the cards were acquired
        :acquired_at,
        # Price paid for the cards
        :acquisition_price,
        # Optional notes
        :notes
      ],
      ram_copies: [node()],
      type: :set,
      index: [:user_pubkey, :card_id]
    ]

    case :mnesia.create_table(:user_collections, table_def) do
      {:atomic, :ok} ->
        Logger.info("User collections table created successfully")

      {:aborted, {:already_exists, :user_collections}} ->
        Logger.info("User collections table already exists")

      {:aborted, reason} ->
        Logger.error("Failed to create user collections table: #{inspect(reason)}")
    end
  end

  defp create_user_trades_table do
    table_def = [
      attributes: [
        # Unique trade identifier
        :id,
        # Trader's public key
        :user_pubkey,
        # Card being traded
        :card_id,
        # "buy" or "sell"
        :trade_type,
        # Number of cards
        :quantity,
        # Price per card in cents
        :price,
        # Total trade value
        :total_value,
        # Other party's pubkey (if completed)
        :counterparty_pubkey,
        # "open", "completed", "cancelled"
        :status,
        # When trade was created
        :created_at,
        # When trade was completed
        :completed_at,
        # Associated Nostr event ID
        :nostr_event_id
      ],
      ram_copies: [node()],
      type: :ordered_set,
      index: [:user_pubkey, :card_id, :status, :created_at]
    ]

    case :mnesia.create_table(:user_trades, table_def) do
      {:atomic, :ok} ->
        Logger.info("User trades table created successfully")

      {:aborted, {:already_exists, :user_trades}} ->
        Logger.info("User trades table already exists")

      {:aborted, reason} ->
        Logger.error("Failed to create user trades table: #{inspect(reason)}")
    end
  end

  defp create_user_portfolios_table do
    table_def = [
      attributes: [
        # Primary key - user's public key
        :user_pubkey,
        # Total portfolio value in cents
        :total_value,
        # Total number of cards owned
        :total_cards,
        # Number of unique cards owned
        :unique_cards,
        # When portfolio was last calculated
        :last_calculated,
        # 24h performance percentage
        :performance_24h,
        # 7d performance percentage
        :performance_7d,
        # 30d performance percentage
        :performance_30d
      ],
      ram_copies: [node()],
      type: :set
    ]

    case :mnesia.create_table(:user_portfolios, table_def) do
      {:atomic, :ok} ->
        Logger.info("User portfolios table created successfully")

      {:aborted, {:already_exists, :user_portfolios}} ->
        Logger.info("User portfolios table already exists")

      {:aborted, reason} ->
        Logger.error("Failed to create user portfolios table: #{inspect(reason)}")
    end
  end

  @doc """
  Reset all tables (WARNING: This will delete all data!)
  """
  def reset_tables do
    Logger.warning("Resetting all Mnesia tables - ALL DATA WILL BE LOST!")

    # Delete Nostr tables
    :mnesia.delete_table(:user_portfolios)
    :mnesia.delete_table(:user_trades)
    :mnesia.delete_table(:user_collections)
    :mnesia.delete_table(:nostr_users)

    # Delete existing tables
    :mnesia.delete_table(:user_preferences)
    :mnesia.delete_table(:price_history)
    :mnesia.delete_table(:cards)

    create_tables()

    Logger.info("Tables reset complete")
  end
end
