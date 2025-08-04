defmodule Sammelkarten.Card do
  @moduledoc """
  Card data structure representing a collectible card.

  Fields:
  - id: Unique identifier for the card
  - name: Display name of the card
  - image_path: Path to the card image in assets
  - current_price: Current market price in cents (integer for precision)
  - price_change_24h: Price change in last 24 hours in cents
  - price_change_percentage: Percentage change in last 24 hours
  - rarity: Card rarity level (common, uncommon, rare, epic, legendary)
  - description: Card description or backstory
  - last_updated: Timestamp of last price update
  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          image_path: String.t(),
          current_price: integer(),
          price_change_24h: integer(),
          price_change_percentage: float(),
          rarity: String.t(),
          description: String.t(),
          last_updated: DateTime.t()
        }

  defstruct [
    :id,
    :name,
    :image_path,
    :current_price,
    :price_change_24h,
    :price_change_percentage,
    :rarity,
    :description,
    :last_updated
  ]

  @doc """
  Create a new card struct with default values.
  """
  def new(attrs \\ %{}) do
    defaults = %{
      id: generate_id(),
      current_price: 0,
      price_change_24h: 0,
      price_change_percentage: 0.0,
      rarity: "common",
      description: "",
      last_updated: DateTime.utc_now()
    }

    struct(__MODULE__, Map.merge(defaults, attrs))
  end

  @doc """
  Generate a unique ID for a card.
  """
  def generate_id do
    Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end

  @doc """
  Convert price from cents to decimal for display.
  """
  def price_to_decimal(price_cents) when is_integer(price_cents) do
    Decimal.div(price_cents, 100)
  end

  @doc """
  Convert decimal price to cents for storage.
  """
  def decimal_to_price(decimal_price) do
    Decimal.to_integer(Decimal.mult(decimal_price, 100))
  end

  @doc """
  Format price for display with currency symbol in German format.
  """
  def format_price(price_cents) when is_integer(price_cents) do
    Sammelkarten.Formatter.format_german_price(price_cents)
  end

  @doc """
  Get rarity color for UI styling.
  """
  def rarity_color(rarity) do
    case rarity do
      "common" -> "text-gray-600"
      "uncommon" -> "text-green-600"
      "rare" -> "text-blue-600"
      "epic" -> "text-purple-600"
      "legendary" -> "text-yellow-600"
      _ -> "text-gray-600"
    end
  end

  @doc """
  Get price change color for UI styling.
  """
  def price_change_color(change_percentage) when is_float(change_percentage) do
    cond do
      change_percentage > 0 -> "text-green-600"
      change_percentage < 0 -> "text-red-600"
      true -> "text-gray-600"
    end
  end

  @doc """
  Format price change percentage for display in German format.
  """
  def format_price_change(change_percentage) when is_float(change_percentage) do
    Sammelkarten.Formatter.format_german_percentage(change_percentage)
  end
end
