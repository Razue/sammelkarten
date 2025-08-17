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
      status: "offer",
      created_at: :os.system_time(:second),
      expires_at: params.expires_at
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
      now = :os.system_time(:second)
      
      :mnesia.dirty_match_object({:user_trades, :_, user_pubkey, :_, :_, :_, :_, :_, :_, :_})
      |> Enum.filter(fn {_, _, _, _, _, _, _, status, _, expires_at} ->
        status == "offer" and expires_at > now
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
      offer.type,
      offer.quantity,
      offer.price,
      offer.status,
      offer.created_at,
      offer.expires_at
    }

    case :mnesia.dirty_write(trade_record) do
      :ok -> :ok
      error -> {:error, error}
    end
  rescue
    error -> {:error, error}
  end

  defp trade_record_to_map({:user_trades, id, user_pubkey, card_id, type, quantity, price, status, created_at, expires_at}) do
    %{
      id: id,
      user_pubkey: user_pubkey,
      card_id: card_id,
      type: type,
      quantity: quantity,
      price: price,
      status: status,
      created_at: created_at,
      expires_at: expires_at
    }
  end
end