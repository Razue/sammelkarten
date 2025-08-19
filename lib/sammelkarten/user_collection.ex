defmodule Sammelkarten.UserCollection do
  @moduledoc """
  Handles user collection aggregation and Nostr snapshot management.
  
  This module provides:
  - Collection aggregation from local Mnesia state
  - JSON encoding for Nostr events
  - Collection snapshot publishing and rehydration
  """
  
  alias Sammelkarten.Cards
  require Logger
  
  @doc """
  Aggregate a user's card collection from local state.
  Returns a map of card_id => quantity for all cards owned by the user.
  """
  def aggregate_user_collection(user_pubkey) do
    case Cards.get_user_cards(user_pubkey) do
      [] -> 
        {:ok, %{}}
        
      user_cards when is_list(user_cards) ->
        # Group by card_id and sum quantities
        collection_map = 
          user_cards
          |> Enum.group_by(& &1.card_id)
          |> Enum.map(fn {card_id, entries} ->
            total_quantity = Enum.reduce(entries, 0, & &1.quantity + &2)
            {card_id, total_quantity}
          end)
          |> Enum.into(%{})
        
        {:ok, collection_map}
    end
  end
  
  @doc """
  Encode collection data as JSON for Nostr event content.
  Format: {"cards": {"card_id": quantity, ...}, "total_cards": count, "updated_at": timestamp}
  """
  def encode_collection_json(collection_map) when is_map(collection_map) do
    total_cards = Enum.reduce(collection_map, 0, fn {_card_id, quantity}, acc -> acc + quantity end)
    
    collection_data = %{
      "cards" => collection_map,
      "total_cards" => total_cards,
      "updated_at" => DateTime.utc_now() |> DateTime.to_unix()
    }
    
    case Jason.encode(collection_data) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> 
        Logger.error("Failed to encode collection JSON: #{inspect(reason)}")
        {:error, :json_encoding_failed}
    end
  end
  
  @doc """
  Decode collection JSON back into collection map and metadata.
  """
  def decode_collection_json(json_content) when is_binary(json_content) do
    case Jason.decode(json_content) do
      {:ok, %{"cards" => cards_map, "total_cards" => total, "updated_at" => timestamp}} ->
        {:ok, %{
          cards: cards_map,
          total_cards: total,
          updated_at: DateTime.from_unix(timestamp)
        }}
        
      {:ok, %{"cards" => cards_map}} ->
        # Fallback for older format without metadata
        total_cards = Enum.reduce(cards_map, 0, fn {_card_id, quantity}, acc -> acc + quantity end)
        {:ok, %{
          cards: cards_map,
          total_cards: total_cards,
          updated_at: nil
        }}
        
      {:error, reason} ->
        Logger.error("Failed to decode collection JSON: #{inspect(reason)}")
        {:error, :json_decoding_failed}
        
      _ ->
        {:error, :invalid_collection_format}
    end
  end
  
  @doc """
  Generate a collection snapshot for a user.
  This combines aggregation and encoding in one step.
  """
  def create_collection_snapshot(user_pubkey) do
    with {:ok, collection_map} <- aggregate_user_collection(user_pubkey),
         {:ok, json_content} <- encode_collection_json(collection_map) do
      {:ok, %{
        user_pubkey: user_pubkey,
        collection_map: collection_map,
        json_content: json_content,
        created_at: DateTime.utc_now()
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Rehydrate user collection from a Nostr collection event.
  This function takes a collection snapshot and applies it to local state.
  
  WARNING: This will overwrite the user's current collection entirely.
  Use with caution in production.
  """
  def rehydrate_user_collection(user_pubkey, collection_json, opts \\ []) do
    safe_mode = Keyword.get(opts, :safe_mode, true)
    
    with {:ok, decoded_data} <- decode_collection_json(collection_json),
         {:ok, _current_collection} <- if(safe_mode, do: aggregate_user_collection(user_pubkey), else: {:ok, %{}}) do
      
      collection_map = decoded_data.cards
      
      if safe_mode do
        Logger.info("Rehydrating collection for #{String.slice(user_pubkey, 0, 8)}... in safe mode (#{decoded_data.total_cards} cards)")
        apply_collection_safely(user_pubkey, collection_map)
      else
        Logger.info("Rehydrating collection for #{String.slice(user_pubkey, 0, 8)}... with full replacement (#{decoded_data.total_cards} cards)")
        apply_collection_with_replacement(user_pubkey, collection_map)
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Validate that a collection snapshot is consistent with current state.
  Useful for testing roundtrip functionality.
  """
  def validate_collection_snapshot(user_pubkey, snapshot_json) do
    with {:ok, current_collection} <- aggregate_user_collection(user_pubkey),
         {:ok, decoded_data} <- decode_collection_json(snapshot_json) do
      
      snapshot_collection = decoded_data.cards
      
      # Compare collections
      if maps_equal?(current_collection, snapshot_collection) do
        {:ok, :consistent}
      else
        {:error, {:inconsistent_collections, current_collection, snapshot_collection}}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  # Private helper functions for rehydration
  
  defp apply_collection_safely(user_pubkey, collection_map) do
    # Safe mode: only add cards that don't exist, don't remove existing ones
    results = 
      Enum.map(collection_map, fn {card_id, quantity} ->
        case Cards.get_card(card_id) do
          {:ok, card} ->
            # Check if user already has this card
            existing_cards = Cards.get_user_cards(user_pubkey)
            user_has_card = Enum.any?(existing_cards, fn uc -> uc.card_id == card_id end)
            
            if not user_has_card do
              # Add card to user's collection at current market price
              Cards.add_to_user_collection(user_pubkey, card_id, quantity, card.current_price)
            else
              Logger.debug("Skipping #{card_id} - user already owns this card")
              :ok
            end
          
          {:error, :not_found} ->
            Logger.warning("Card #{card_id} not found in local database, skipping")
            {:error, :card_not_found}
        end
      end)
    
    # Count successes
    success_count = Enum.count(results, &(&1 == :ok))
    {:ok, %{cards_added: success_count, total_cards: map_size(collection_map)}}
  end
  
  defp apply_collection_with_replacement(user_pubkey, collection_map) do
    # Full replacement mode: clear existing collection and apply new one
    transaction_result = 
      :mnesia.transaction(fn ->
        # 1. Remove all existing user collections
        case clear_user_collection(user_pubkey) do
          :ok ->
            # 2. Add all cards from snapshot
            Enum.each(collection_map, fn {card_id, quantity} ->
              case Cards.get_card(card_id) do
                {:ok, card} ->
                  Cards.add_to_user_collection(user_pubkey, card_id, quantity, card.current_price)
                {:error, _} ->
                  Logger.warning("Card #{card_id} not found, skipping during rehydration")
              end
            end)
            
          {:error, reason} ->
            :mnesia.abort(reason)
        end
      end)
    
    case transaction_result do
      {:atomic, :ok} ->
        {:ok, %{cards_replaced: map_size(collection_map)}}
      {:aborted, reason} ->
        {:error, reason}
    end
  end
  
  defp clear_user_collection(user_pubkey) do
    # Find all user collection records and delete them
    match_spec = [{{:user_collections, :_, user_pubkey, :_, :_, :_, :_, :_}, [], [:"$_"]}]
    
    try do
      records = :mnesia.select(:user_collections, match_spec)
      Enum.each(records, fn {_, record_id, _, _, _, _, _, _} ->
        :mnesia.delete({:user_collections, record_id})
      end)
      :ok
    rescue
      error ->
        Logger.error("Failed to clear user collection: #{inspect(error)}")
        {:error, :clear_failed}
    end
  end
  
  # Private helper functions for validation
  
  defp maps_equal?(map1, map2) when is_map(map1) and is_map(map2) do
    # Convert values to ensure same type comparison
    normalize_map(map1) == normalize_map(map2)
  end
  
  defp normalize_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), normalize_value(v)} end)
    |> Enum.into(%{})
  end
  
  defp normalize_value(v) when is_integer(v), do: v
  defp normalize_value(v) when is_float(v), do: trunc(v)
  defp normalize_value(v), do: v
end