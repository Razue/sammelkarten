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

    # Wait for tables to be available
    :mnesia.wait_for_tables([:cards, :price_history, :user_preferences], 5000)
  end

  defp create_cards_table do
    table_def = [
      attributes: [
        :id,
        :name,
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

  @doc """
  Reset all tables (WARNING: This will delete all data!)
  """
  def reset_tables do
    Logger.warning("Resetting all Mnesia tables - ALL DATA WILL BE LOST!")

    :mnesia.delete_table(:user_preferences)
    :mnesia.delete_table(:price_history)
    :mnesia.delete_table(:cards)

    create_tables()

    Logger.info("Tables reset complete")
  end
end
