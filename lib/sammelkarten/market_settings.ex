defmodule Sammelkarten.MarketSettings do
  @moduledoc """
  Settings module for MarketMaker and PriceUpdater control.
  
  Provides configuration management without requiring database reset.
  Manages start/stop states for market making components.
  """

  use GenServer
  require Logger

  @settings_file "market_settings.json"
  @settings_path Path.join([Application.compile_env(:sammelkarten, :data_dir, "data"), @settings_file])

  # Default settings
  @default_settings %{
    market_maker_enabled: false,
    price_updater_enabled: true,
    market_maker_auto_start: false,
    price_update_interval: 420_000,
    last_updated: DateTime.utc_now()
  }

  defstruct [
    :market_maker_enabled,
    :price_updater_enabled,
    :market_maker_auto_start,
    :price_update_interval,
    :last_updated
  ]

  # Client API

  @doc """
  Start the settings manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current market settings.
  """
  def get_settings do
    GenServer.call(__MODULE__, :get_settings)
  end

  @doc """
  Update market settings.
  """
  def update_settings(changes) when is_map(changes) do
    GenServer.call(__MODULE__, {:update_settings, changes})
  end

  @doc """
  Enable/disable MarketMaker.
  """
  def set_market_maker_enabled(enabled) when is_boolean(enabled) do
    update_settings(%{market_maker_enabled: enabled})
  end

  @doc """
  Enable/disable PriceUpdater.
  """
  def set_price_updater_enabled(enabled) when is_boolean(enabled) do
    update_settings(%{price_updater_enabled: enabled})
  end

  @doc """
  Set MarketMaker auto-start on application boot.
  """
  def set_market_maker_auto_start(enabled) when is_boolean(enabled) do
    update_settings(%{market_maker_auto_start: enabled})
  end

  @doc """
  Set price update interval in milliseconds.
  """
  def set_price_update_interval(interval) when is_integer(interval) and interval > 0 do
    update_settings(%{price_update_interval: interval})
  end

  @doc """
  Check if MarketMaker is enabled.
  """
  def market_maker_enabled? do
    get_settings().market_maker_enabled
  end

  @doc """
  Check if PriceUpdater is enabled.
  """
  def price_updater_enabled? do
    get_settings().price_updater_enabled
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    # Ensure data directory exists
    ensure_data_dir()

    # Load settings from file or use defaults
    settings = load_settings_from_file()
    
    Logger.info("Market settings loaded: MarketMaker=#{settings.market_maker_enabled}, PriceUpdater=#{settings.price_updater_enabled}")
    
    {:ok, settings}
  end

  @impl true
  def handle_call(:get_settings, _from, settings) do
    {:reply, settings, settings}
  end

  @impl true
  def handle_call({:update_settings, changes}, _from, current_settings) do
    # Merge changes with current settings
    updated_settings = struct(current_settings, Map.put(changes, :last_updated, DateTime.utc_now()))
    
    # Persist to file
    case save_settings_to_file(updated_settings) do
      :ok ->
        Logger.info("Market settings updated: #{inspect(changes)}")
        apply_settings_changes(current_settings, updated_settings)
        {:reply, {:ok, updated_settings}, updated_settings}
        
      {:error, reason} ->
        Logger.error("Failed to save market settings: #{inspect(reason)}")
        {:reply, {:error, reason}, current_settings}
    end
  end

  # Private Functions

  defp ensure_data_dir do
    data_dir = Path.dirname(@settings_path)
    File.mkdir_p!(data_dir)
  end

  defp load_settings_from_file do
    case File.read(@settings_path) do
      {:ok, content} ->
        try do
          json_data = Jason.decode!(content)
          settings_map = atomize_keys(json_data)
          
          # Convert string datetime back to DateTime struct
          settings_map = 
            if settings_map[:last_updated] do
              {:ok, datetime, _} = DateTime.from_iso8601(settings_map.last_updated)
              Map.put(settings_map, :last_updated, datetime)
            else
              Map.put(settings_map, :last_updated, DateTime.utc_now())
            end
          
          struct(__MODULE__, Map.merge(@default_settings, settings_map))
        rescue
          error ->
            Logger.warning("Failed to parse settings file, using defaults: #{inspect(error)}")
            struct(__MODULE__, @default_settings)
        end
        
      {:error, :enoent} ->
        Logger.info("Settings file not found, creating with defaults")
        settings = struct(__MODULE__, @default_settings)
        save_settings_to_file(settings)
        settings
        
      {:error, reason} ->
        Logger.warning("Failed to read settings file: #{inspect(reason)}")
        struct(__MODULE__, @default_settings)
    end
  end

  defp save_settings_to_file(settings) do
    # Convert struct to map for JSON encoding
    settings_map = Map.from_struct(settings)
    
    # Convert DateTime to ISO8601 string for JSON compatibility
    settings_map = Map.put(settings_map, :last_updated, DateTime.to_iso8601(settings.last_updated))
    
    json_content = Jason.encode!(settings_map, pretty: true)
    
    case File.write(@settings_path, json_content) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
  end

  defp apply_settings_changes(old_settings, new_settings) do
    # Apply MarketMaker changes
    if old_settings.market_maker_enabled != new_settings.market_maker_enabled do
      if new_settings.market_maker_enabled do
        start_market_maker()
      else
        stop_market_maker()
      end
    end

    # Apply PriceUpdater changes
    if old_settings.price_updater_enabled != new_settings.price_updater_enabled do
      if new_settings.price_updater_enabled do
        start_price_updater()
      else
        stop_price_updater()
      end
    end

    # Apply price update interval changes
    if old_settings.price_update_interval != new_settings.price_update_interval do
      update_price_update_interval(new_settings.price_update_interval)
    end
  end

  defp start_market_maker do
    try do
      case Process.whereis(Sammelkarten.MarketMaker) do
        nil ->
          Logger.info("MarketMaker process not running, cannot start")
        pid when is_pid(pid) ->
          Sammelkarten.MarketMaker.start_market_making()
          Logger.info("MarketMaker started")
      end
    rescue
      error ->
        Logger.error("Failed to start MarketMaker: #{inspect(error)}")
    end
  end

  defp stop_market_maker do
    try do
      case Process.whereis(Sammelkarten.MarketMaker) do
        nil ->
          Logger.info("MarketMaker process not running")
        pid when is_pid(pid) ->
          Sammelkarten.MarketMaker.stop_market_making()
          Logger.info("MarketMaker stopped")
      end
    rescue
      error ->
        Logger.error("Failed to stop MarketMaker: #{inspect(error)}")
    end
  end

  defp start_price_updater do
    try do
      case Process.whereis(Sammelkarten.PriceUpdater) do
        nil ->
          Logger.info("PriceUpdater process not running, cannot start")
        pid when is_pid(pid) ->
          Sammelkarten.PriceUpdater.resume()
          Logger.info("PriceUpdater started")
      end
    rescue
      error ->
        Logger.error("Failed to start PriceUpdater: #{inspect(error)}")
    end
  end

  defp stop_price_updater do
    try do
      case Process.whereis(Sammelkarten.PriceUpdater) do
        nil ->
          Logger.info("PriceUpdater process not running")
        pid when is_pid(pid) ->
          Sammelkarten.PriceUpdater.pause()
          Logger.info("PriceUpdater stopped")
      end
    rescue
      error ->
        Logger.error("Failed to stop PriceUpdater: #{inspect(error)}")
    end
  end

  defp update_price_update_interval(new_interval) do
    try do
      case Process.whereis(Sammelkarten.PriceUpdater) do
        nil ->
          Logger.info("PriceUpdater process not running, cannot update interval")
        pid when is_pid(pid) ->
          Sammelkarten.PriceUpdater.set_interval(new_interval)
          Logger.info("PriceUpdater interval updated to #{new_interval}ms")
      end
    rescue
      error ->
        Logger.error("Failed to update PriceUpdater interval: #{inspect(error)}")
    end
  end
end