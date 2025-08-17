defmodule Sammelkarten.MarketMaker do
  @moduledoc """
  Automated market maker for card liquidity.

  This module provides:
  - Continuous bid/ask spread maintenance
  - Dynamic pricing based on market conditions
  - Liquidity provision for all cards
  - Risk management and inventory tracking
  - Profit optimization algorithms
  """

  use GenServer
  require Logger
  alias Sammelkarten.{Cards, Trading, Formatter}

  # Market maker configuration
  # Target inventory per card
  @inventory_target 10
  # Maximum inventory per card
  @max_inventory 20
  # 30 seconds
  @rebalance_interval 30_000
  # 2% price change triggers rebalance
  @price_update_threshold 0.02

  # Dynamic offer configuration
  # Number of Bitcoin sats offers per card
  @bitcoin_offer_count 2
  # Number of card exchange offers per card
  @exchange_offer_count 3
  # 45 seconds between offer refreshes
  @offer_refresh_interval 15_000

  defstruct [
    :pubkey,
    :inventory,
    :active_orders,
    :profit_target,
    :risk_limits,
    :last_rebalance,
    :total_profit,
    :status,
    :last_offer_refresh,
    :active_bitcoin_offers,
    :active_exchange_offers
  ]

  # Client API

  @doc """
  Start the market maker system.
  """
  def start_link(opts) do
    pubkey = Keyword.get(opts, :pubkey, "market_maker_bot")
    GenServer.start_link(__MODULE__, %{pubkey: pubkey}, name: __MODULE__)
  end

  @doc """
  Start market making for all cards.
  """
  def start_market_making do
    GenServer.cast(__MODULE__, :start_market_making)
  end

  @doc """
  Stop market making and cancel all orders.
  """
  def stop_market_making do
    GenServer.cast(__MODULE__, :stop_market_making)
  end

  @doc """
  Get current market maker status and metrics.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Force a rebalance of all market maker orders.
  """
  def rebalance_orders do
    GenServer.cast(__MODULE__, :rebalance_orders)
  end

  @doc """
  Update market maker configuration.
  """
  def update_config(config) do
    GenServer.cast(__MODULE__, {:update_config, config})
  end

  # Server implementation

  @impl true
  def init(%{pubkey: pubkey}) do
    # Subscribe to price updates
    Phoenix.PubSub.subscribe(Sammelkarten.PubSub, "price_updates")

    # Load user preferences to get refresh rate
    refresh_interval =
      case Sammelkarten.Preferences.get_user_preferences("default_user") do
        # Use 1/4 of price refresh rate
        {:ok, preferences} -> div(preferences.refresh_rate, 4)
        {:error, _} -> @offer_refresh_interval
      end

    # Schedule periodic rebalancing
    :timer.send_interval(@rebalance_interval, :rebalance)

    # Schedule periodic offer refresh using preference rate
    :timer.send_interval(refresh_interval, :refresh_offers)

    state = %__MODULE__{
      pubkey: pubkey,
      inventory: %{},
      active_orders: %{},
      # 2% profit target
      profit_target: 0.02,
      risk_limits: %{max_position: @max_inventory, max_daily_loss: 50_000},
      last_rebalance: :os.system_time(:second),
      total_profit: 0,
      status: :stopped,
      last_offer_refresh: :os.system_time(:second),
      active_bitcoin_offers: %{},
      active_exchange_offers: %{}
    }

    start_market_making()

    Logger.info("Market maker initialized with pubkey: #{pubkey}")
    {:ok, state}
  end

  @impl true
  def handle_cast(:start_market_making, state) do
    Logger.info("Starting market making operations")

    # Initialize inventory for all cards
    new_inventory = initialize_inventory()
    new_state = %{state | inventory: new_inventory, status: :active}

    # Create initial orders
    create_initial_orders(new_state)

    # Create initial dynamic offers
    create_initial_dynamic_offers(new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:stop_market_making, state) do
    Logger.info("Stopping market making operations")

    # Cancel all active orders
    cancel_all_orders(state)

    new_state = %{state | status: :stopped, active_orders: %{}}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:rebalance_orders, state) do
    if state.status == :active do
      new_state = perform_rebalance(state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:update_config, config}, state) do
    # Update configuration parameters
    new_state = apply_config_updates(state, config)
    Logger.info("Market maker configuration updated")
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      status: state.status,
      total_profit: state.total_profit,
      active_orders: map_size(state.active_orders),
      inventory_items: map_size(state.inventory),
      last_rebalance: state.last_rebalance,
      profit_target: state.profit_target,
      risk_limits: state.risk_limits
    }

    {:reply, status, state}
  end

  @impl true
  def handle_info(:rebalance, state) do
    if state.status == :active do
      new_state = perform_rebalance(state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:refresh_offers, state) do
    if state.status == :active do
      new_state = refresh_dynamic_offers(state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:price_update, card_id, _old_price, new_price}, state) do
    if state.status == :active do
      new_state = handle_price_change(state, card_id, new_price)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp initialize_inventory do
    case Cards.list_cards() do
      {:ok, cards} ->
        cards
        |> Enum.map(fn card -> {card.id, @inventory_target} end)
        |> Map.new()

      {:error, _} ->
        Logger.error("Failed to initialize market maker inventory")
        %{}
    end
  end

  defp create_initial_orders(state) do
    case Cards.list_cards() do
      {:ok, cards} ->
        Enum.each(cards, fn card ->
          create_market_orders_for_card(card, state)
        end)

      {:error, reason} ->
        Logger.error("Failed to create initial orders: #{inspect(reason)}")
    end
  end

  defp create_market_orders_for_card(card, state) do
    current_price = card.current_price

    # Randomly decide whether to create buy or sell order (or both)
    order_type = case :rand.uniform(3) do
      1 -> :buy_only
      2 -> :sell_only  
      3 -> :both
    end

    case order_type do
      :buy_only ->
        buy_quantity = generate_realistic_quantity()
        buy_price = generate_dynamic_buy_price(current_price)
        create_buy_order(state.pubkey, card.id, buy_quantity, buy_price)

      :sell_only ->
        sell_quantity = generate_realistic_quantity()
        sell_price = generate_dynamic_sell_price(current_price)
        create_sell_order(state.pubkey, card.id, sell_quantity, sell_price)

      :both ->
        buy_quantity = generate_realistic_quantity()
        sell_quantity = generate_realistic_quantity()
        buy_price = generate_dynamic_buy_price(current_price)
        sell_price = generate_dynamic_sell_price(current_price)
        create_buy_order(state.pubkey, card.id, buy_quantity, buy_price)
        create_sell_order(state.pubkey, card.id, sell_quantity, sell_price)
    end
  end

  defp create_buy_order(pubkey, card_id, quantity, price) do
    order_params = %{
      user_pubkey: pubkey,
      card_id: card_id,
      type: "buy",
      quantity: quantity,
      price: price,
      # 1 hour
      expires_at: :os.system_time(:second) + 3600
    }

    case Trading.create_offer(order_params) do
      {:ok, offer} ->
        Logger.debug(
          "Market maker search order created: #{card_id} x#{quantity} @ #{Formatter.format_german_price(price)}"
        )

        {:ok, offer}

      {:error, reason} ->
        Logger.warning("Failed to create buy order for #{card_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp create_sell_order(pubkey, card_id, quantity, price) do
    order_params = %{
      user_pubkey: pubkey,
      card_id: card_id,
      type: "sell",
      quantity: quantity,
      price: price,
      # 1 hour
      expires_at: :os.system_time(:second) + 3600
    }

    case Trading.create_offer(order_params) do
      {:ok, offer} ->
        Logger.debug(
          "Market maker offer order created: #{card_id} x#{quantity} @ #{Formatter.format_german_price(price)}"
        )

        {:ok, offer}

      {:error, reason} ->
        Logger.warning("Failed to create sell order for #{card_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp perform_rebalance(state) do
    Logger.debug("Performing market maker rebalance")

    # Cancel expired orders
    cancel_expired_orders(state)

    # Update orders based on current market conditions
    case Cards.list_cards() do
      {:ok, cards} ->
        # Only rebalance 2-5 random cards instead of all cards
        selected_cards = Enum.take_random(cards, :rand.uniform(4) + 1)
        
        Enum.each(selected_cards, fn card ->
          rebalance_card_orders(card, state)
        end)

        %{state | last_rebalance: :os.system_time(:second)}

      {:error, _} ->
        state
    end
  end

  defp rebalance_card_orders(card, state) do
    # Get current orders for this card
    user_orders = Trading.get_user_offers(state.pubkey)
    card_orders = Enum.filter(user_orders, fn order -> order.card_id == card.id end)

    # Cancel existing orders for this card
    Enum.each(card_orders, fn order ->
      cancel_order(order.id)
    end)

    # Create new orders with updated prices
    create_market_orders_for_card(card, state)
  end

  defp handle_price_change(state, card_id, new_price) do
    # Check if price change exceeds threshold
    case get_last_order_price(state, card_id) do
      nil ->
        state

      last_price ->
        price_change_pct = abs(new_price - last_price) / last_price

        if price_change_pct > @price_update_threshold do
          Logger.debug("Price change threshold exceeded for #{card_id}, rebalancing")

          case Cards.get_card(card_id) do
            {:ok, card} ->
              rebalance_card_orders(card, state)
              state

            _ ->
              state
          end
        else
          state
        end
    end
  end

  defp get_last_order_price(state, card_id) do
    # Get the last order price from active orders
    case Map.get(state.active_orders, card_id) do
      nil ->
        nil

      orders when is_list(orders) ->
        case List.first(orders) do
          nil -> nil
          order -> order.price
        end

      _ ->
        nil
    end
  end

  defp cancel_all_orders(state) do
    user_orders = Trading.get_user_offers(state.pubkey)

    Enum.each(user_orders, fn order ->
      cancel_order(order.id)
    end)

    Logger.info("Cancelled #{length(user_orders)} market maker orders")
  end

  defp cancel_expired_orders(state) do
    user_orders = Trading.get_user_offers(state.pubkey)
    now = :os.system_time(:second)

    expired_orders =
      Enum.filter(user_orders, fn order ->
        order.expires_at <= now
      end)

    Enum.each(expired_orders, fn order ->
      cancel_order(order.id)
    end)

    if length(expired_orders) > 0 do
      Logger.debug("Cancelled #{length(expired_orders)} expired market maker orders")
    end
  end

  defp cancel_order(order_id) do
    # For now, this is a placeholder. In a real implementation,
    # we would mark the order as cancelled in the database
    Logger.debug("Cancelling order: #{order_id}")
    :ok
  end

  defp apply_config_updates(state, config) do
    # Apply configuration updates
    state
    |> update_profit_target(config)
    |> update_risk_limits(config)
  end

  defp update_profit_target(state, config) do
    if Map.has_key?(config, :profit_target) do
      %{state | profit_target: config.profit_target}
    else
      state
    end
  end

  defp update_risk_limits(state, config) do
    if Map.has_key?(config, :risk_limits) do
      %{state | risk_limits: Map.merge(state.risk_limits, config.risk_limits)}
    else
      state
    end
  end

  # Dynamic offer creation functions

  defp create_initial_dynamic_offers(_state) do
    case Cards.list_cards() do
      {:ok, cards} ->
        Enum.each(cards, fn card ->
          create_bitcoin_offers_for_card(card)
          create_exchange_offers_for_card(card, cards)
        end)

      {:error, reason} ->
        Logger.error("Failed to create initial dynamic offers: #{inspect(reason)}")
    end
  end

  defp refresh_dynamic_offers(state) do
    Logger.debug("Refreshing dynamic offers")

    # Clear old offers (in real implementation, these would expire)
    clear_dynamic_offers()

    # Create new offers
    case Cards.list_cards() do
      {:ok, cards} ->
        # Only create offers for 2-5 random cards instead of all cards
        selected_cards = Enum.take_random(cards, :rand.uniform(4) + 1)
        
        Enum.each(selected_cards, fn card ->
          create_bitcoin_offers_for_card(card)
          create_exchange_offers_for_card(card, cards)
        end)

        %{state | last_offer_refresh: :os.system_time(:second)}

      {:error, _} ->
        state
    end
  end

  defp create_bitcoin_offers_for_card(card) do
    # Generate Bitcoin sats offers/wants for this card
    1..@bitcoin_offer_count
    |> Enum.each(fn i ->
      trader_pubkey = generate_trader_pubkey("btc_trader_#{card.id}_#{i}")

      # Random offer type (buy/sell)
      offer_type = if :rand.uniform(2) == 1, do: "buy_for_sats", else: "sell_for_sats"

      # Price variation: ±15% from current price
      price_variation = (:rand.uniform(30) - 15) / 100
      sats_price = calculate_sats_price(card.current_price, price_variation)

      # Quantity: 1-5 cards
      quantity = :rand.uniform(5)

      create_bitcoin_offer(trader_pubkey, card.id, offer_type, quantity, sats_price)
    end)
  end

  defp create_exchange_offers_for_card(card, all_cards) do
    # Generate card exchange offers for this card
    1..@exchange_offer_count
    |> Enum.each(fn i ->
      trader_pubkey = generate_trader_pubkey("exchange_trader_#{card.id}_#{i}")

      # Random exchange type
      exchange_type =
        case :rand.uniform(3) do
          # Offering this card for any card
          1 -> "offer_card_for_any"
          # Wanting this card, offering any card
          2 -> "want_card_for_any"
          # Wanting this card for a specific card
          3 -> "want_specific_card"
        end

      case exchange_type do
        "offer_card_for_any" ->
          create_exchange_offer(trader_pubkey, card.id, "offer", nil, :rand.uniform(3))

        "want_card_for_any" ->
          create_exchange_offer(trader_pubkey, card.id, "want", nil, :rand.uniform(2))

        "want_specific_card" ->
          # Pick a random other card to offer
          other_cards = Enum.reject(all_cards, fn c -> c.id == card.id end)

          if length(other_cards) > 0 do
            offered_card = Enum.random(other_cards)

            create_exchange_offer(
              trader_pubkey,
              card.id,
              "want",
              offered_card.id,
              :rand.uniform(2)
            )
          end
      end
    end)
  end

  defp generate_trader_pubkey(base) do
    hash = :crypto.hash(:sha256, base) |> Base.encode16(case: :lower)
    "npub1#{String.slice(hash, 0, 20)}"
  end

  defp calculate_sats_price(euro_price, variation) do
    # Convert euro to approximate sats (assuming 1 EUR ≈ 1600 sats as example)
    base_sats = euro_price * 16
    trunc(base_sats * (1 + variation))
  end

  defp create_bitcoin_offer(trader_pubkey, card_id, offer_type, quantity, sats_price) do
    trade_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    created_at = DateTime.utc_now()
    # 1 hour from now
    expires_at = DateTime.add(created_at, 3600, :second)

    record = {
      :dynamic_bitcoin_offers,
      trade_id,
      trader_pubkey,
      card_id,
      offer_type,
      quantity,
      sats_price,
      "open",
      created_at,
      expires_at
    }

    try do
      :mnesia.dirty_write(record)

      Logger.debug(
        "Created Bitcoin offer: #{offer_type} #{quantity}x #{card_id} for #{sats_price} sats"
      )
    rescue
      error ->
        Logger.warning("Failed to create Bitcoin offer: #{inspect(error)}")
    end
  end

  defp create_exchange_offer(trader_pubkey, wanted_card_id, offer_type, offered_card_id, quantity) do
    trade_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    created_at = DateTime.utc_now()
    # 1 hour from now
    expires_at = DateTime.add(created_at, 3600, :second)

    record = {
      :dynamic_card_exchanges,
      trade_id,
      trader_pubkey,
      wanted_card_id,
      # nil for "any card" offers
      offered_card_id,
      offer_type,
      quantity,
      "open",
      created_at,
      expires_at
    }

    try do
      :mnesia.dirty_write(record)
      offered_desc = if offered_card_id, do: "#{offered_card_id}", else: "any card"

      Logger.debug(
        "Created exchange offer: #{offer_type} #{quantity}x #{wanted_card_id} for #{offered_desc}"
      )
    rescue
      error ->
        Logger.warning("Failed to create exchange offer: #{inspect(error)}")
    end
  end

  defp clear_dynamic_offers do
    # Clear expired dynamic offers
    try do
      # Clear Bitcoin offers
      :mnesia.dirty_match_object({:dynamic_bitcoin_offers, :_, :_, :_, :_, :_, :_, :_, :_, :_})
      |> Enum.each(fn record ->
        :mnesia.dirty_delete_object(record)
      end)

      # Clear exchange offers
      :mnesia.dirty_match_object({:dynamic_card_exchanges, :_, :_, :_, :_, :_, :_, :_, :_, :_})
      |> Enum.each(fn record ->
        :mnesia.dirty_delete_object(record)
      end)
    rescue
      error ->
        Logger.warning("Failed to clear dynamic offers: #{inspect(error)}")
    end
  end

  defp generate_realistic_quantity do
    # 85% chance of 1x, 12% chance of 2x, 3% chance of 3x
    case :rand.uniform(100) do
      n when n <= 85 -> 1
      n when n <= 97 -> 2
      _ -> 3
    end
  end

  defp generate_dynamic_buy_price(current_price) do
    # Buy orders (searches) are typically 1-8% below market price
    # with some variation to create realistic market depth
    discount_percentage = (:rand.uniform(70) + 10) / 1000  # 1.0% to 8.0%
    price_variation = (:rand.uniform(20) - 10) / 1000      # ±1.0% additional variation
    
    final_percentage = discount_percentage + price_variation
    price_adjustment = trunc(current_price * final_percentage)
    
    max(current_price - price_adjustment, trunc(current_price * 0.85))  # Never below 85% of market
  end

  defp generate_dynamic_sell_price(current_price) do
    # Sell orders (offers) are typically 1-8% above market price  
    # with some variation to create realistic market depth
    markup_percentage = (:rand.uniform(70) + 10) / 1000    # 1.0% to 8.0%
    price_variation = (:rand.uniform(20) - 10) / 1000      # ±1.0% additional variation
    
    final_percentage = markup_percentage + price_variation
    price_adjustment = trunc(current_price * final_percentage)
    
    current_price + price_adjustment
  end
end
