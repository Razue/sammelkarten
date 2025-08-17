defmodule Sammelkarten.Trading do
  @moduledoc """
  Trading functionality for creating and managing card trade offers.
  This is a simplified version that interfaces with the existing user_trades table.
  """

  require Logger

  @doc """
  Create a new trade offer.
  """
  def create_offer(params) do
    offer = %{
      id: generate_offer_id(),
      user_pubkey: params.user_pubkey,
      card_id: params.card_id,
      type: params.type,
      quantity: params.quantity,
      price: params.price,
      status: "open",
      created_at: DateTime.utc_now(),
      expires_at: params[:expires_at]
    }

    case store_offer(offer) do
      :ok -> {:ok, offer}
      error -> error
    end
  end

  @doc """
  Get the quantity of a specific card that a user owns.
  """
  def get_user_card_quantity(user_pubkey, card_id) do
    # Query user_collections table for user's cards
    case :mnesia.dirty_match_object({:user_collections, user_pubkey, card_id, :_, :_}) do
      [] -> 0
      [{:user_collections, _user, _card, quantity, _acquired_at}] -> quantity
      _ -> 0
    end
  rescue
    _ -> 0
  end

  @doc """
  Get all active offers for a user.
  """
  def get_user_offers(user_pubkey) do
    try do
      :mnesia.dirty_match_object(
        {:user_trades, :_, user_pubkey, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
      )
      |> Enum.filter(fn {_, _, _, _, _, _, _, _, _, status, _, _, _} ->
        status == "open"
      end)
      |> Enum.map(&trade_record_to_map/1)
    rescue
      _ -> []
    end
  end

  # Private functions

  defp generate_offer_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp store_offer(offer) do
    trade_record = {
      :user_trades,
      offer.id,
      offer.user_pubkey,
      offer.card_id,
      # This will map to trade_type
      offer.type,
      offer.quantity,
      offer.price,
      # total_value
      offer.price * offer.quantity,
      # counterparty_pubkey - nil for open offers
      nil,
      # This should be "open" instead of "offer"
      offer.status,
      # created_at - convert from Unix timestamp to DateTime if needed
      if is_integer(offer.created_at) do
        DateTime.from_unix!(offer.created_at)
      else
        offer.created_at
      end,
      # completed_at - nil for open offers
      nil,
      # nostr_event_id - nil for now
      nil
    }

    case :mnesia.dirty_write(trade_record) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      error -> {:error, error}
    end
  rescue
    error -> {:error, error}
  end

  defp trade_record_to_map(
         {:user_trades, id, user_pubkey, card_id, trade_type, quantity, price, total_value,
          counterparty_pubkey, status, created_at, completed_at, nostr_event_id}
       ) do
    %{
      id: id,
      user_pubkey: user_pubkey,
      card_id: card_id,
      trade_type: trade_type,
      quantity: quantity,
      price: price,
      total_value: total_value,
      counterparty_pubkey: counterparty_pubkey,
      status: status,
      created_at: created_at,
      completed_at: completed_at,
      nostr_event_id: nostr_event_id,
      expires_at: nil
    }
  end
end
