defmodule Sammelkarten.UserPreferences do
  @moduledoc """
  Schema and data structure for user preferences.

  This module defines the structure for storing user customization settings
  including refresh rates, theme preferences, notification settings, and more.
  """

  @enforce_keys [:user_id]
  defstruct [
    :user_id,
    # Price update interval in milliseconds (default: 21 seconds)
    refresh_rate: 2_100_000,
    # Theme preference: "light", "dark", "auto"
    theme: "light",
    # Enable price update notifications
    notifications_enabled: true,
    # Enable sound notifications
    sound_enabled: false,
    # Enable automatic price refreshes
    auto_refresh: true,
    # Number of cards to display per page
    cards_per_page: 20,
    # Default sort field: "name", "price", "change"
    default_sort: "name",
    # Default sort direction: "asc", "desc"
    default_sort_direction: "asc",
    # Show the price ticker component
    show_ticker: true,
    # Ticker animation speed (lower = faster)
    ticker_speed: 50,
    # Chart style preference: "line", "candlestick", "area"
    chart_style: "line",
    # List of price alert configurations
    price_alerts: [],
    created_at: nil,
    updated_at: nil
  ]

  @type t :: %__MODULE__{
          user_id: String.t(),
          refresh_rate: integer(),
          theme: String.t(),
          notifications_enabled: boolean(),
          sound_enabled: boolean(),
          auto_refresh: boolean(),
          cards_per_page: integer(),
          default_sort: String.t(),
          default_sort_direction: String.t(),
          show_ticker: boolean(),
          ticker_speed: integer(),
          chart_style: String.t(),
          price_alerts: list(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Create a new user preferences struct with default values.
  """
  def new(user_id) when is_binary(user_id) do
    now = DateTime.utc_now()

    %__MODULE__{
      user_id: user_id,
      created_at: now,
      updated_at: now
    }
  end

  @doc """
  Update user preferences with new values.
  """
  def update(preferences, changes) when is_map(changes) do
    updated_preferences =
      preferences
      |> Map.merge(changes)
      |> Map.put(:updated_at, DateTime.utc_now())

    {:ok, updated_preferences}
  end

  @doc """
  Validate user preferences data.
  """
  def validate(preferences) do
    with :ok <- validate_refresh_rate(preferences.refresh_rate),
         :ok <- validate_theme(preferences.theme),
         :ok <- validate_sort_field(preferences.default_sort),
         :ok <- validate_sort_direction(preferences.default_sort_direction),
         :ok <- validate_cards_per_page(preferences.cards_per_page),
         :ok <- validate_ticker_speed(preferences.ticker_speed),
         :ok <- validate_chart_style(preferences.chart_style) do
      {:ok, preferences}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Validation functions
  defp validate_refresh_rate(rate) when is_integer(rate) and rate >= 1_000 and rate <= 300_000 do
    :ok
  end

  defp validate_refresh_rate(_), do: {:error, "Refresh rate must be between 1 and 300 seconds"}

  defp validate_theme(theme) when theme in ["light", "dark"], do: :ok
  defp validate_theme(_), do: {:error, "Theme must be 'light' or 'dark'"}

  defp validate_sort_field(field) when field in ["name", "price", "change"], do: :ok
  defp validate_sort_field(_), do: {:error, "Sort field must be 'name', 'price', or 'change'"}

  defp validate_sort_direction(direction) when direction in ["asc", "desc"], do: :ok
  defp validate_sort_direction(_), do: {:error, "Sort direction must be 'asc' or 'desc'"}

  defp validate_cards_per_page(count) when is_integer(count) and count >= 5 and count <= 100 do
    :ok
  end

  defp validate_cards_per_page(_), do: {:error, "Cards per page must be between 5 and 100"}

  defp validate_ticker_speed(speed) when is_integer(speed) and speed >= 10 and speed <= 200 do
    :ok
  end

  defp validate_ticker_speed(_), do: {:error, "Ticker speed must be between 10 and 200"}

  defp validate_chart_style(style) when style in ["line", "candlestick", "area"], do: :ok

  defp validate_chart_style(_),
    do: {:error, "Chart style must be 'line', 'candlestick', or 'area'"}

  @doc """
  Convert preferences to a map for JSON serialization.
  """
  def to_map(preferences) do
    Map.from_struct(preferences)
  end

  @doc """
  Convert a map back to a preferences struct.
  """
  def from_map(map) when is_map(map) do
    struct(__MODULE__, map)
  end

  @doc """
  Get default preferences for a user.
  """
  def defaults(user_id) do
    new(user_id)
  end

  @doc """
  Get refresh rate options for UI selection.
  """
  def refresh_rate_options do
    [
      {"1 second", 1_000},
      {"5 seconds", 5_000},
      {"10 seconds", 10_000},
      {"21 seconds", 21_000},
      {"30 seconds", 30_000},
      {"1 minute", 60_000},
      {"2 minutes", 120_000},
      {"5 minutes", 300_000}
    ]
  end

  @doc """
  Get theme options for UI selection.
  """
  def theme_options do
    [
      {"Light", "light"},
      {"Dark", "dark"}
    ]
  end

  @doc """
  Get chart style options for UI selection.
  """
  def chart_style_options do
    [
      {"Line Chart", "line"},
      {"Area Chart", "area"},
      {"Candlestick", "candlestick"}
    ]
  end
end
