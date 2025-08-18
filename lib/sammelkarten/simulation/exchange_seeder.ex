defmodule Sammelkarten.Simulation.ExchangeSeeder do
  @moduledoc """
  Seeds the database with realistic exchange offers using test users with NIP-05 identifiers.
  
  This module creates mock exchange data for demonstration purposes.
  """

  alias Sammelkarten.Cards
  alias Sammelkarten.Nostr.TestUsers
  require Logger

  @doc """
  Seed the database with exchange offers from test users.
  """
  def seed_exchange_offers do
    Logger.info("Seeding exchange offers with test users...")
    
    # Get all cards
    {:ok, cards} = Cards.list_cards()
    test_users = TestUsers.test_users()
    
    # Clear existing test data
    clear_test_data()
    
    # Create regular trading offers (buy/sell)
    seed_regular_offers(cards, test_users)
    
    # Create exchange offers 
    seed_exchange_offers(cards, test_users)
    
    # Create Bitcoin offers
    seed_bitcoin_offers(cards, test_users)
    
    # Create dynamic card exchanges
    seed_dynamic_exchanges(cards, test_users)
    
    Logger.info("Exchange seeding completed!")
    :ok
  end

  # Clear existing test data
  defp clear_test_data do
    test_pubkeys = TestUsers.test_user_pubkeys()
    
    transaction = fn ->
      # Delete existing user trades from test users
      Enum.each(test_pubkeys, fn pubkey ->
        :mnesia.match_object({:user_trades, :_, pubkey, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_})
        |> Enum.each(&:mnesia.delete_object/1)
      end)
      
      # Delete existing dynamic offers from test users
      Enum.each(test_pubkeys, fn pubkey ->
        :mnesia.match_object({:dynamic_bitcoin_offers, :_, pubkey, :_, :_, :_, :_, :_, :_, :_})
        |> Enum.each(&:mnesia.delete_object/1)
        
        :mnesia.match_object({:dynamic_card_exchanges, :_, pubkey, :_, :_, :_, :_, :_, :_, :_})
        |> Enum.each(&:mnesia.delete_object/1)
      end)
    end
    
    case :mnesia.transaction(transaction) do
      {:atomic, _} -> Logger.info("Cleared existing test data")
      {:aborted, reason} -> Logger.error("Failed to clear test data: #{inspect(reason)}")
    end
  end

  # Seed regular buy/sell offers
  defp seed_regular_offers(cards, test_users) do
    Enum.each(cards, fn card ->
      # Create 1-3 offers per card from test users
      num_offers = Enum.random(1..3)
      selected_users = Enum.take_random(test_users, num_offers)
      
      Enum.each(selected_users, fn user ->
        offer_type = Enum.random(["buy", "sell"])
        quantity = Enum.random(1..5)
        
        # Price variation: ±5-15% from current price
        price_variation = (Enum.random(5..15) / 100) * (if Enum.random([true, false]), do: 1, else: -1)
        price = max(1, trunc(card.current_price * (1 + price_variation)))
        total_value = price * quantity
        
        trade_record = {
          :user_trades,
          generate_trade_id(),
          user.pubkey,
          card.id,
          offer_type,
          quantity,
          price,
          total_value,
          nil, # wanted_hash for exchanges
          "open",
          DateTime.utc_now(),
          nil, # executed_at
          nil  # counterparty_pubkey
        }
        
        :mnesia.dirty_write(trade_record)
      end)
    end)
    
    Logger.info("Seeded regular trading offers")
  end

  # Seed exchange offers (card for card)
  defp seed_exchange_offers(cards, test_users) do
    # Create 5-10 exchange offers
    num_exchanges = Enum.random(5..10)
    
    Enum.each(1..num_exchanges, fn _ ->
      user = Enum.random(test_users)
      offering_card = Enum.random(cards)
      
      # Either want specific cards or open to any
      {_wanted_type, wanted_data} = case Enum.random([:specific, :open]) do
        :specific ->
          wanted_cards = Enum.take_random(cards, Enum.random(1..3))
          wanted_data = %{
            "type" => "specific",
            "card_ids" => Enum.map(wanted_cards, & &1.id)
          }
          {"specific", Jason.encode!(wanted_data)}
          
        :open ->
          wanted_data = %{"type" => "open"}
          {"open", Jason.encode!(wanted_data)}
      end
      
      quantity = Enum.random(1..3)
      
      exchange_record = {
        :user_trades,
        generate_trade_id(),
        user.pubkey,
        offering_card.id,
        "exchange",
        quantity,
        nil, # price (not applicable for exchanges)
        nil, # total_value (not applicable for exchanges)
        wanted_data,
        "open",
        DateTime.utc_now(),
        nil, # executed_at
        nil  # counterparty_pubkey
      }
      
      :mnesia.dirty_write(exchange_record)
    end)
    
    Logger.info("Seeded exchange offers")
  end

  # Seed Bitcoin offers (sats for cards)
  defp seed_bitcoin_offers(cards, test_users) do
    Enum.each(cards, fn card ->
      # Create 1-2 Bitcoin offers per card
      num_offers = Enum.random(1..2)
      selected_users = Enum.take_random(test_users, num_offers)
      
      Enum.each(selected_users, fn user ->
        offer_type = Enum.random(["buy_for_sats", "sell_for_sats"])
        quantity = Enum.random(1..3)
        
        # Price in sats: ±10-20% from current price
        price_variation = (Enum.random(10..20) / 100) * (if Enum.random([true, false]), do: 1, else: -1)
        sats_price = max(1000, trunc(card.current_price * (1 + price_variation)))
        
        expires_at = DateTime.add(DateTime.utc_now(), Enum.random(1..7), :day)
        
        bitcoin_offer_record = {
          :dynamic_bitcoin_offers,
          generate_trade_id(),
          user.pubkey,
          card.id,
          offer_type,
          quantity,
          sats_price,
          "open",
          DateTime.utc_now(),
          expires_at
        }
        
        :mnesia.dirty_write(bitcoin_offer_record)
      end)
    end)
    
    Logger.info("Seeded Bitcoin offers")
  end

  # Seed dynamic card exchanges
  defp seed_dynamic_exchanges(cards, test_users) do
    # Create 8-15 dynamic exchanges
    num_exchanges = Enum.random(8..15)
    
    Enum.each(1..num_exchanges, fn _ ->
      user = Enum.random(test_users)
      wanted_card = Enum.random(cards)
      
      # Either offer specific card or open to any
      {offered_card_id, exchange_type} = case Enum.random([:specific_offer, :open_offer, :want_any]) do
        :specific_offer ->
          offered_card = Enum.random(cards)
          {offered_card.id, "offer"}
          
        :open_offer ->
          {nil, "offer"} # Offering any card for the wanted card
          
        :want_any ->
          offered_card = Enum.random(cards)
          {offered_card.id, "want"} # Want any card, offering specific
      end
      
      quantity = Enum.random(1..2)
      expires_at = DateTime.add(DateTime.utc_now(), Enum.random(1..14), :day)
      
      exchange_record = {
        :dynamic_card_exchanges,
        generate_trade_id(),
        user.pubkey,
        wanted_card.id,
        offered_card_id,
        exchange_type,
        quantity,
        "open",
        DateTime.utc_now(),
        expires_at
      }
      
      :mnesia.dirty_write(exchange_record)
    end)
    
    Logger.info("Seeded dynamic card exchanges")
  end

  # Generate a unique trade ID
  defp generate_trade_id do
    "trade_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end