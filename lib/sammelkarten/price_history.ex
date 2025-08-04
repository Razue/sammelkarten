defmodule Sammelkarten.PriceHistory do
  @moduledoc """
  Price history data structure for tracking card price changes over time.

  Fields:
  - id: Unique identifier for the price record
  - card_id: Reference to the card this price belongs to
  - price: Price at this point in time (in cents)
  - timestamp: When this price was recorded
  - volume: Trading volume or activity indicator
  """

  @type t :: %__MODULE__{
          id: String.t(),
          card_id: String.t(),
          price: integer(),
          timestamp: DateTime.t(),
          volume: integer()
        }

  defstruct [
    :id,
    :card_id,
    :price,
    :timestamp,
    :volume
  ]

  @doc """
  Create a new price history record.
  """
  def new(attrs \\ %{}) do
    defaults = %{
      id: generate_id(),
      timestamp: DateTime.utc_now(),
      volume: 0
    }

    struct(__MODULE__, Map.merge(defaults, attrs))
  end

  @doc """
  Generate a unique ID for a price history record.
  """
  def generate_id do
    timestamp = DateTime.to_unix(DateTime.utc_now(), :microsecond)
    "#{timestamp}_#{Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)}"
  end

  @doc """
  Format timestamp for display.
  """
  def format_timestamp(timestamp) do
    case DateTime.to_date(timestamp) do
      date -> Date.to_string(date)
    end
  end

  @doc """
  Get price history for a specific time range.
  """
  def time_range_id(start_time, end_time) do
    start_unix = DateTime.to_unix(start_time, :microsecond)
    end_unix = DateTime.to_unix(end_time, :microsecond)
    {start_unix, end_unix}
  end
end
