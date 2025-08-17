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
  @spread_percentage 0.04  # 4% spread between bid and ask
  @inventory_target 10     # Target inventory per card
  @max_inventory 20        # Maximum inventory per card
  @rebalance_interval 30_000  # 30 seconds
  @price_update_threshold 0.02  # 2% price change triggers rebalance

  defstruct [
    :pubkey,
    :inventory,
    :active_orders,
    :profit_target,
    :risk_limits,
    :last_rebalance,
    :total_profit,
    :status
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
    
    # Schedule periodic rebalancing
    :timer.send_interval(@rebalance_interval, :rebalance)
    
    state = %__MODULE__{
      pubkey: pubkey,
      inventory: %{},
      active_orders: %{},
      profit_target: 0.02,  # 2% profit target
      risk_limits: %{max_position: @max_inventory, max_daily_loss: 50_000},
      last_rebalance: :os.system_time(:second),
      total_profit: 0,
      status: :stopped
    }

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
    
    # Calculate bid and ask prices with spread
    spread_amount = trunc(current_price * @spread_percentage / 2)
    bid_price = current_price - spread_amount
    ask_price = current_price + spread_amount
    
    # Get current inventory for this card
    current_inventory = Map.get(state.inventory, card.id, 0)
    
    # Create buy order if inventory is below target
    if current_inventory < @inventory_target do
      buy_quantity = @inventory_target - current_inventory
      create_buy_order(state.pubkey, card.id, buy_quantity, bid_price)
    end
    
    # Create sell order if we have inventory
    if current_inventory > 0 do
      sell_quantity = min(current_inventory, @inventory_target)
      create_sell_order(state.pubkey, card.id, sell_quantity, ask_price)
    end
  end

  defp create_buy_order(pubkey, card_id, quantity, price) do
    order_params = %{
      user_pubkey: pubkey,
      card_id: card_id,
      type: "buy",
      quantity: quantity,
      price: price,
      expires_at: :os.system_time(:second) + 3600  # 1 hour
    }
    
    case Trading.create_offer(order_params) do
      {:ok, offer} ->
        Logger.debug("Market maker buy order created: #{card_id} x#{quantity} @ #{Formatter.format_german_price(price)}")
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
      expires_at: :os.system_time(:second) + 3600  # 1 hour
    }
    
    case Trading.create_offer(order_params) do
      {:ok, offer} ->
        Logger.debug("Market maker sell order created: #{card_id} x#{quantity} @ #{Formatter.format_german_price(price)}")
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
        Enum.each(cards, fn card ->
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
      nil -> state
      last_price ->
        price_change_pct = abs(new_price - last_price) / last_price
        
        if price_change_pct > @price_update_threshold do
          Logger.debug("Price change threshold exceeded for #{card_id}, rebalancing")
          
          case Cards.get_card(card_id) do
            {:ok, card} -> 
              rebalance_card_orders(card, state)
              state
            _ -> state
          end
        else
          state
        end
    end
  end

  defp get_last_order_price(state, card_id) do
    # Get the last order price from active orders
    case Map.get(state.active_orders, card_id) do
      nil -> nil
      orders when is_list(orders) ->
        case List.first(orders) do
          nil -> nil
          order -> order.price
        end
      _ -> nil
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
    
    expired_orders = Enum.filter(user_orders, fn order ->
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
end