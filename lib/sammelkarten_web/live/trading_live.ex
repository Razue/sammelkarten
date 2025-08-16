defmodule SammelkartenWeb.TradingLive do
  @moduledoc """
  LiveView for peer-to-peer card trading via Nostr events.

  This page handles:
  - Real-time trade offer broadcasting and discovery
  - Trade matching between buyers and sellers
  - Trade execution and ownership transfers
  - Trading history and reputation tracking
  - Nostr authentication requirement
  """

  use SammelkartenWeb, :live_view

  alias Sammelkarten.{Cards, Formatter}
  alias Sammelkarten.Nostr.{User, Event, Client}
  require Logger

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:page_title, "P2P Trading")
      |> assign(:current_user, nil)
      |> assign(:authenticated, false)
      |> assign(:active_offers, [])
      |> assign(:my_offers, [])
      |> assign(:trade_history, [])
      |> assign(:available_cards, [])
      |> assign(:selected_card, nil)
      |> assign(:offer_form, %{"card_id" => "", "price" => "", "quantity" => ""})
      |> assign(:loading, true)
      |> assign(:error_message, nil)
      # "all", "buy", "sell"
      |> assign(:filter_type, "all")
      # "newest", "price_low", "price_high"
      |> assign(:sort_by, "newest")
      # Default tab for trading
      |> assign(:active_tab, "active_offers")
      # Search functionality
      |> assign(:search_query, "")
      # Offer form state
      |> assign(:selected_offer_type, nil)
      # Form visibility
      |> assign(:show_create_form, false)

    # Check if user is authenticated
    case get_nostr_user_from_session(session) do
      {:ok, user} ->
        socket =
          socket
          |> assign(:current_user, user)
          |> assign(:authenticated, true)

        # Subscribe to price updates and trade events
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Sammelkarten.PubSub, "price_updates")
          Phoenix.PubSub.subscribe(Sammelkarten.PubSub, "trade_events")
        end

        # Load trading data
        send(self(), :load_trading_data)

        {:ok, socket}

      {:error, :not_authenticated} ->
        # Redirect to authentication page
        socket =
          socket
          |> put_flash(:error, "Please authenticate with Nostr to access trading features")
          |> push_navigate(to: "/auth")

        {:ok, socket}
    end
  end

  @impl true
  def handle_info(:load_trading_data, socket) do
    if socket.assigns.authenticated do
      user_pubkey = socket.assigns.current_user.pubkey

      # Load active trade offers (excluding user's own offers)
      active_offers = load_active_offers(user_pubkey)

      # Load user's own offers
      my_offers = load_user_offers(user_pubkey)

      # Load trade history
      trade_history = load_trade_history(user_pubkey)

      # Load available cards for the create offer form
      available_cards =
        case Cards.list_cards() do
          {:ok, cards} -> cards
          {:error, _} -> []
        end

      socket =
        socket
        |> assign(:active_offers, active_offers)
        |> assign(:my_offers, my_offers)
        |> assign(:trade_history, trade_history)
        |> assign(:available_cards, available_cards)
        |> assign(:loading, false)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:price_update, _card_id}, socket) do
    if socket.assigns.authenticated do
      # Reload trading data when prices update
      send(self(), :load_trading_data)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:price_update_completed, _stats}, socket) do
    # Handle price update completion - we can ignore this or use it for UI feedback
    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_trade_offer, offer}, socket) do
    if socket.assigns.authenticated do
      # Add new offer to active offers if it's not from current user
      current_offers = socket.assigns.active_offers

      if offer.user_pubkey != socket.assigns.current_user.pubkey do
        updated_offers =
          [offer | current_offers]
          |> sort_offers(socket.assigns.sort_by)
          |> filter_offers(socket.assigns.filter_type)

        socket = assign(socket, :active_offers, updated_offers)
        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    socket = assign(socket, :active_tab, tab)
    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    socket = assign(socket, :search_query, query)
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_offer_type", %{"type" => offer_type}, socket) do
    socket = assign(socket, :selected_offer_type, offer_type)
    {:noreply, socket}
  end

  @impl true
  def handle_event("show_create_form", _params, socket) do
    socket = assign(socket, :show_create_form, true)
    {:noreply, socket}
  end

  @impl true
  def handle_event("hide_create_form", _params, socket) do
    socket = 
      socket
      |> assign(:show_create_form, false)
      |> assign(:selected_offer_type, nil)
      |> assign(:offer_form, %{"card_id" => "", "price" => "", "quantity" => ""})
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_form", params, socket) do
    # LiveView phx-change sends the entire form data
    # Extract the form fields we care about
    offer_form = %{
      "card_id" => params["card_id"] || "",
      "price" => params["price"] || "",
      "quantity" => params["quantity"] || ""
    }
    
    socket = assign(socket, :offer_form, offer_form)
    {:noreply, socket}
  end

  @impl true
  def handle_event("create_offer", _params, socket) do
    if socket.assigns.authenticated do
      user_pubkey = socket.assigns.current_user.pubkey
      offer_type = socket.assigns.selected_offer_type
      offer_form = socket.assigns.offer_form
      
      card_id = offer_form["card_id"]
      price_str = offer_form["price"]
      quantity_str = offer_form["quantity"]

      # Validate that offer type is selected
      if offer_type == nil do
        socket = put_flash(socket, :error, "Please select Buy Order or Sell Order")
        {:noreply, socket}
      else
        with {price, _} <- Float.parse(price_str),
             {quantity, _} <- Integer.parse(quantity_str),
             true <- price > 0 and quantity > 0,
             true <- card_id != "",
             {:ok, _card} <- Cards.get_card(card_id) do
        # Convert price to cents for storage
        price_cents = round(price * 100)

        # Create trade offer event
        offer_data = %{
          card_id: card_id,
          offer_type: offer_type,
          price: price_cents,
          quantity: quantity,
          # 24 hours
          expires_at: DateTime.utc_now() |> DateTime.add(24 * 60 * 60) |> DateTime.to_unix()
        }

        event = Event.trade_offer(user_pubkey, offer_data)

        # Store offer locally and broadcast via Nostr
        case create_trade_offer(user_pubkey, card_id, offer_type, price_cents, quantity, event) do
          {:ok, _offer_id} ->
            # Broadcast event via Nostr
            Client.publish_event(event)

            # Reload trading data
            send(self(), :load_trading_data)

            socket =
              socket
              |> put_flash(:info, "Trade offer created successfully")
              |> assign(:offer_form, %{"card_id" => "", "price" => "", "quantity" => ""})
              |> assign(:selected_offer_type, nil)
              |> assign(:show_create_form, false)

            {:noreply, socket}

          {:error, reason} ->
            socket = put_flash(socket, :error, "Failed to create offer: #{reason}")
            {:noreply, socket}
        end
        else
          _ ->
            socket = put_flash(socket, :error, "Please enter valid price and quantity")
            {:noreply, socket}
        end
      end
    else
      socket = put_flash(socket, :error, "Authentication required")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("accept_offer", %{"offer_id" => offer_id}, socket) do
    if socket.assigns.authenticated do
      user_pubkey = socket.assigns.current_user.pubkey

      case execute_trade(offer_id, user_pubkey) do
        {:ok, trade_execution} ->
          # Create trade execution event
          execution_event = Event.trade_execution(user_pubkey, trade_execution)
          Client.publish_event(execution_event)

          # Reload trading data
          send(self(), :load_trading_data)

          socket = put_flash(socket, :info, "Trade executed successfully!")
          {:noreply, socket}

        {:error, reason} ->
          socket = put_flash(socket, :error, "Failed to execute trade: #{reason}")
          {:noreply, socket}
      end
    else
      socket = put_flash(socket, :error, "Authentication required")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("accept_offer", %{"trade_id" => trade_id}, socket) do
    if socket.assigns.authenticated do
      user_pubkey = socket.assigns.current_user.pubkey

      case execute_trade(trade_id, user_pubkey) do
        {:ok, trade_execution} ->
          # Create trade execution event
          execution_event = Event.trade_execution(user_pubkey, trade_execution)
          Client.publish_event(execution_event)

          # Reload trading data
          send(self(), :load_trading_data)

          socket = put_flash(socket, :info, "Trade executed successfully!")
          {:noreply, socket}

        {:error, reason} ->
          socket = put_flash(socket, :error, "Failed to execute trade: #{reason}")
          {:noreply, socket}
      end
    else
      socket = put_flash(socket, :error, "Authentication required")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_offer", %{"offer_id" => offer_id}, socket) do
    if socket.assigns.authenticated do
      user_pubkey = socket.assigns.current_user.pubkey

      case cancel_trade_offer(offer_id, user_pubkey) do
        {:ok, _} ->
          # Reload trading data
          send(self(), :load_trading_data)

          socket = put_flash(socket, :info, "Offer cancelled successfully")
          {:noreply, socket}

        {:error, reason} ->
          socket = put_flash(socket, :error, "Failed to cancel offer: #{reason}")
          {:noreply, socket}
      end
    else
      socket = put_flash(socket, :error, "Authentication required")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("filter_offers", %{"type" => filter_type}, socket) do
    active_offers =
      socket.assigns.active_offers
      |> filter_offers(filter_type)
      |> sort_offers(socket.assigns.sort_by)

    socket =
      socket
      |> assign(:filter_type, filter_type)
      |> assign(:active_offers, active_offers)

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort_offers", %{"by" => sort_by}, socket) do
    active_offers =
      socket.assigns.active_offers
      |> sort_offers(sort_by)

    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> assign(:active_offers, active_offers)

    {:noreply, socket}
  end

  # Private helper functions

  defp get_nostr_user_from_session(session) do
    case session do
      %{"nostr_authenticated" => true, "nostr_user" => user_data} when user_data != nil ->
        try do
          user = struct(Sammelkarten.Nostr.User, atomize_keys(user_data))
          {:ok, user}
        rescue
          e ->
            Logger.error("Failed to load user from session: #{inspect(e)}")
            {:error, :invalid_user_data}
        end

      _ ->
        {:error, :not_authenticated}
    end
  end

  defp atomize_keys(map) when is_map(map) do
    for {key, val} <- map, into: %{} do
      cond do
        is_binary(key) -> {String.to_existing_atom(key), val}
        is_atom(key) -> {key, val}
        true -> {key, val}
      end
    end
  end

  defp load_active_offers(exclude_user_pubkey) do
    # Load all cards and generate realistic active offers based on them (similar to DashboardExchangeLive)
    case Cards.list_cards() do
      {:ok, cards} ->
        cards
        |> Enum.filter(fn _ -> should_have_active_offers?() end)
        |> Enum.map(&generate_active_offer(&1, exclude_user_pubkey))
        |> Enum.filter(fn offer -> offer != nil end)
        |> sort_offers("newest")

      {:error, reason} ->
        Logger.error("Failed to load cards for active offers: #{inspect(reason)}")
        []
    end
  end

  defp load_user_offers(user_pubkey) do
    try do
      transaction = fn ->
        :mnesia.match_object(
          {:user_trades, :_, user_pubkey, :_, :_, :_, :_, :_, "open", :_, :_, :_}
        )
      end

      case :mnesia.transaction(transaction) do
        {:atomic, trade_records} ->
          trade_records
          |> Enum.map(&format_trade_offer/1)
          |> Enum.filter(fn offer -> offer != nil end)
          |> sort_offers("newest")

        {:aborted, reason} ->
          Logger.error("Failed to load user offers: #{inspect(reason)}")
          []
      end
    rescue
      e ->
        Logger.error("Error loading user offers: #{inspect(e)}")
        []
    end
  end

  defp load_trade_history(user_pubkey) do
    try do
      transaction = fn ->
        # Load completed trades where user was the trader
        user_trades =
          :mnesia.match_object(
            {:user_trades, :_, user_pubkey, :_, :_, :_, :_, :_, "completed", :_, :_, :_}
          )

        # Load completed trades where user was the counterparty
        counterparty_trades =
          :mnesia.match_object(
            {:user_trades, :_, :_, :_, :_, :_, :_, user_pubkey, "completed", :_, :_, :_}
          )

        user_trades ++ counterparty_trades
      end

      case :mnesia.transaction(transaction) do
        {:atomic, trade_records} ->
          trade_records
          |> Enum.uniq()
          |> Enum.map(&format_trade_execution/1)
          |> Enum.filter(fn trade -> trade != nil end)
          |> Enum.sort_by(fn trade -> trade.completed_at end, :desc)

        {:aborted, reason} ->
          Logger.error("Failed to load trade history: #{inspect(reason)}")
          []
      end
    rescue
      e ->
        Logger.error("Error loading trade history: #{inspect(e)}")
        []
    end
  end

  defp format_trade_offer(
         {_, trade_id, user_pubkey, card_id, trade_type, quantity, price, total_value, _, "open",
          created_at, _, _}
       ) do
    case Cards.get_card(card_id) do
      {:ok, card} ->
        # Calculate expires_at as 24 hours from created_at
        expires_at = created_at |> DateTime.add(24 * 60 * 60)

        %{
          id: trade_id,
          user_pubkey: user_pubkey,
          user_short: User.short_pubkey(%{pubkey: user_pubkey}),
          card: card,
          offer_type: trade_type,
          price: price,
          quantity: quantity,
          created_at: created_at,
          expires_at: expires_at,
          total_value: total_value
        }

      {:error, _} ->
        nil
    end
  end

  defp format_trade_execution(
         {_, trade_id, seller_pubkey, card_id, trade_type, quantity, price, total_value,
          buyer_pubkey, "completed", _, completed_at, _}
       ) do
    case Cards.get_card(card_id) do
      {:ok, card} ->
        %{
          id: trade_id,
          seller_pubkey: seller_pubkey,
          seller_short: User.short_pubkey(%{pubkey: seller_pubkey}),
          buyer_pubkey: buyer_pubkey,
          buyer_short: User.short_pubkey(%{pubkey: buyer_pubkey}),
          card: card,
          offer_type: trade_type,
          price: price,
          quantity: quantity,
          executed_at: completed_at,
          completed_at: completed_at,
          total_value: total_value
        }

      {:error, _} ->
        nil
    end
  end

  defp create_trade_offer(user_pubkey, card_id, offer_type, price, quantity, _event) do
    trade_id = generate_trade_id()
    total_value = price * quantity
    created_at = DateTime.utc_now()

    # New table structure: {:user_trades, id, user_pubkey, card_id, trade_type, quantity, price, total_value, counterparty_pubkey, status, created_at, completed_at, nostr_event_id}
    record = {
      :user_trades,
      trade_id,
      user_pubkey,
      card_id,
      offer_type,
      quantity,
      price,
      total_value,
      # counterparty_pubkey - nil for open offers
      nil,
      "open",
      created_at,
      # completed_at - nil for open offers
      nil,
      # nostr_event_id - nil for now
      nil
    }

    transaction = fn ->
      :mnesia.write(record)
    end

    case :mnesia.transaction(transaction) do
      {:atomic, :ok} ->
        Logger.info(
          "Created #{offer_type} offer for #{quantity} #{card_id} at #{Formatter.format_german_price(price)} by #{User.short_pubkey(%{pubkey: user_pubkey})}"
        )

        {:ok, trade_id}

      {:aborted, reason} ->
        Logger.error("Failed to create trade offer: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp execute_trade(offer_id, buyer_pubkey) do
    transaction = fn ->
      case :mnesia.read({:user_trades, offer_id}) do
        [
          {_, ^offer_id, seller_pubkey, card_id, trade_type, quantity, price, total_value, nil,
           "open", created_at, nil, _}
        ] ->
          # Check if offer is still valid (24 hours from creation)
          expires_at = created_at |> DateTime.add(24 * 60 * 60)

          if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
            completed_at = DateTime.utc_now()

            # Update offer to completed
            executed_record = {
              :user_trades,
              offer_id,
              seller_pubkey,
              card_id,
              trade_type,
              quantity,
              price,
              total_value,
              # counterparty_pubkey
              buyer_pubkey,
              "completed",
              created_at,
              completed_at,
              # nostr_event_id
              nil
            }

            # Write executed trade
            :mnesia.write(executed_record)

            # Create trade execution data for Nostr event
            execution_data = %{
              trade_id: offer_id,
              buyer_pubkey: buyer_pubkey,
              seller_pubkey: seller_pubkey,
              card_id: card_id,
              price: price,
              quantity: quantity,
              total_value: total_value
            }

            {:ok, execution_data}
          else
            {:error, :offer_expired}
          end

        [] ->
          {:error, :offer_not_found}

        _ ->
          {:error, :invalid_offer}
      end
    end

    case :mnesia.transaction(transaction) do
      {:atomic, {:ok, execution_data}} ->
        Logger.info(
          "Trade executed: #{buyer_pubkey} bought #{execution_data.quantity} #{execution_data.card_id} from #{execution_data.seller_pubkey}"
        )

        {:ok, execution_data}

      {:atomic, {:error, reason}} ->
        {:error, reason}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  defp cancel_trade_offer(offer_id, user_pubkey) do
    transaction = fn ->
      case :mnesia.read({:user_trades, offer_id}) do
        [{_, ^offer_id, ^user_pubkey, _, _, _, _, _, nil, "open", _, nil, _}] ->
          :mnesia.delete({:user_trades, offer_id})
          :ok

        [] ->
          {:error, :not_found}

        _ ->
          {:error, :unauthorized}
      end
    end

    case :mnesia.transaction(transaction) do
      {:atomic, :ok} ->
        {:ok, offer_id}

      {:atomic, {:error, reason}} ->
        {:error, reason}

      {:aborted, reason} ->
        {:error, reason}
    end
  end


  defp filter_offers(offers, "all"), do: offers
  defp filter_offers(offers, "buy"), do: Enum.filter(offers, &(&1.offer_type == "buy"))
  defp filter_offers(offers, "sell"), do: Enum.filter(offers, &(&1.offer_type == "sell"))

  defp sort_offers(offers, "newest"), do: Enum.sort_by(offers, & &1.created_at, :desc)
  defp sort_offers(offers, "price_low"), do: Enum.sort_by(offers, & &1.price, :asc)
  defp sort_offers(offers, "price_high"), do: Enum.sort_by(offers, & &1.price, :desc)

  defp generate_trade_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  # View helper functions that match the current TradingLive implementation

  def format_price(price_cents) do
    Sammelkarten.Formatter.format_german_price(price_cents)
  end

  def format_datetime(datetime) do
    datetime
    |> DateTime.shift_zone!("Europe/Berlin")
    |> Calendar.strftime("%d.%m.%Y %H:%M")
  end

  def time_ago(datetime) do
    diff_seconds = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff_seconds < 60 -> "vor #{diff_seconds}s"
      diff_seconds < 3600 -> "vor #{div(diff_seconds, 60)}m"
      diff_seconds < 86400 -> "vor #{div(diff_seconds, 3600)}h"
      true -> "vor #{div(diff_seconds, 86400)}d"
    end
  end

  def filter_and_sort_offers(offers, search_query, filter_type, sort_by) do
    offers
    |> filter_by_search(search_query)
    |> filter_by_type(filter_type)
    |> sort_offers(sort_by)
  end

  defp filter_by_search(offers, "") do
    offers
  end

  defp filter_by_search(offers, query) do
    query_lower = String.downcase(query)

    Enum.filter(offers, fn offer ->
      card_name = if Map.has_key?(offer, :card), do: String.downcase(offer.card.name), else: ""
      String.contains?(card_name, query_lower)
    end)
  end

  defp filter_by_type(offers, "all") do
    offers
  end

  defp filter_by_type(offers, filter_type) do
    Enum.filter(offers, fn offer -> offer.offer_type == filter_type end)
  end

  # Helper functions for generating realistic active offers (based on DashboardExchangeLive pattern)
  
  defp should_have_active_offers? do
    # About 40% of cards should have active offers at any time
    :rand.uniform(100) <= 40
  end

  defp generate_active_offer(card, exclude_user_pubkey) do
    # Generate a realistic trading offer for this card
    base_seed = :erlang.phash2({card.id, "trade_offer", DateTime.utc_now() |> DateTime.to_date()})
    :rand.seed(:exsss, {base_seed, base_seed + 1, base_seed + 2})

    # Determine offer type based on card characteristics
    offer_type = if :rand.uniform(100) <= 60, do: "buy", else: "sell"
    
    # Calculate realistic price based on current card price
    price_variation = (:rand.uniform(20) - 10) / 100  # -10% to +10%
    price = trunc(card.current_price * (1 + price_variation))
    
    # Generate quantity (1-3 for most offers)
    quantity = case String.downcase(card.rarity) do
      "mythic" -> 1
      "legendary" -> :rand.uniform(2)
      _ -> :rand.uniform(3)
    end

    # Generate a pseudonym trader (similar to exchange live)
    trader_pubkey = generate_pseudonym_trader_pubkey(card, base_seed)
    
    # Skip if this would be the current user
    if trader_pubkey == exclude_user_pubkey do
      nil
    else
      %{
        id: generate_trade_id(),
        user_pubkey: trader_pubkey,
        user_short: generate_short_pubkey(trader_pubkey),
        card: card,
        offer_type: offer_type,
        price: price,
        quantity: quantity,
        created_at: DateTime.utc_now() |> DateTime.add(-:rand.uniform(3600 * 12), :second), # Random time in last 12 hours
        expires_at: DateTime.utc_now() |> DateTime.add(:rand.uniform(3600 * 24), :second), # Random time in next 24 hours
        total_value: price * quantity
      }
    end
  end

  defp generate_pseudonym_trader_pubkey(_card, base_seed) do
    # Generate a consistent but fake pubkey for this card/day combination
    traders = [
      "npub1seedorchris123", "npub1fab456", "npub1altan789", "npub1sticker21m", 
      "npub1markus_turm", "npub1maulwurf", "npub1bitcoinbaer", "npub1satsstacker",
      "npub1nokyc", "npub1noderunner42", "npub1lightning", "npub1hodler",
      "npub1stacksats", "npub1orangepill", "npub1toxic21"
    ]
    trader_index = rem(base_seed, length(traders))
    Enum.at(traders, trader_index)
  end

  defp generate_short_pubkey(pubkey) do
    # Generate a short version like "npub1...xyz"
    if String.length(pubkey) > 8 do
      start = String.slice(pubkey, 0, 8)
      ending = String.slice(pubkey, -3, 3)
      "#{start}...#{ending}"
    else
      pubkey
    end
  end
end
