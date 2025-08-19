defmodule Sammelkarten.Portfolio do
  @moduledoc """
  Portfolio management and valuation for user card collections.
  
  Computes portfolio values, P&L, and aggregated statistics
  for publishing as Nostr portfolio snapshot events (kind 32126).
  """

  alias Sammelkarten.{Cards, UserCollection}
  
  @doc """
  Calculate portfolio values for a user's collection.
  
  Returns a map with:
  - total_value: Current market value in cents
  - card_count: Total number of cards owned
  - unique_cards: Number of unique card types
  - top_cards: List of {card_id, quantity, value} for highest value cards
  - updated_at: Unix timestamp
  """
  def calculate_portfolio_values(user_pubkey) do
    with {:ok, collection} <- UserCollection.aggregate_user_collection(user_pubkey) do
      cards_data = collection.cards || %{}
      
      portfolio_stats = 
        cards_data
        |> Enum.map(&calculate_card_value/1)
        |> Enum.reject(&is_nil/1)
        |> calculate_aggregated_stats()
      
      {:ok, portfolio_stats
           |> Map.put(:updated_at, :os.system_time(:second))
           |> Map.put(:pubkey, user_pubkey)}
    else
      {:error, _reason} -> {:ok, empty_portfolio(user_pubkey)}
    end
  end
  
  @doc """
  Create a portfolio snapshot as JSON for Nostr event content.
  """
  def encode_portfolio_snapshot(portfolio_data) do
    snapshot = %{
      total_value: portfolio_data.total_value,
      card_count: portfolio_data.card_count,
      unique_cards: portfolio_data.unique_cards,
      top_cards: portfolio_data.top_cards,
      updated_at: portfolio_data.updated_at,
      version: "1.0"
    }
    
    Jason.encode(snapshot)
  end
  
  @doc """
  Decode a portfolio snapshot from JSON content.
  """
  def decode_portfolio_snapshot(json_content) do
    case Jason.decode(json_content, keys: :atoms) do
      {:ok, data} -> 
        portfolio = %{
          total_value: data[:total_value] || 0,
          card_count: data[:card_count] || 0,
          unique_cards: data[:unique_cards] || 0,
          top_cards: data[:top_cards] || [],
          updated_at: data[:updated_at],
          version: data[:version] || "1.0"
        }
        {:ok, portfolio}
      
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end
  
  # Private functions
  
  defp calculate_card_value({card_id, quantity}) when is_integer(quantity) and quantity > 0 do
    case Cards.get_card(card_id) do
      {:ok, card} ->
        card_value = card.current_price * quantity
        {card_id, quantity, card_value, card.current_price}
      
      {:error, _} ->
        nil
    end
  end
  
  defp calculate_card_value(_), do: nil
  
  defp calculate_aggregated_stats(card_values) do
    total_value = card_values |> Enum.map(&elem(&1, 2)) |> Enum.sum()
    card_count = card_values |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    unique_cards = length(card_values)
    
    top_cards = 
      card_values
      |> Enum.sort_by(&elem(&1, 2), :desc)
      |> Enum.take(10)
      |> Enum.map(fn {card_id, quantity, value, price} ->
        %{card_id: card_id, quantity: quantity, value: value, price: price}
      end)
    
    %{
      total_value: total_value,
      card_count: card_count,
      unique_cards: unique_cards,
      top_cards: top_cards
    }
  end
  
  defp empty_portfolio(user_pubkey) do
    %{
      total_value: 0,
      card_count: 0,
      unique_cards: 0,
      top_cards: [],
      updated_at: :os.system_time(:second),
      pubkey: user_pubkey
    }
  end
end