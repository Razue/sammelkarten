defmodule SammelkartenWeb.DashboardExchangeLive do
  use SammelkartenWeb, :live_view

  alias Sammelkarten.Cards
  alias Sammelkarten.Preferences

  @impl true
  def mount(_params, _session, socket) do
    # Get user ID (for now, use a default user)
    user_id = "default_user"

    # Load user preferences
    {:ok, user_preferences} = Preferences.get_user_preferences(user_id)

    socket =
      socket
      |> assign(:cards, [])
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> assign(:search_term, "")
      |> assign(:sort_by, user_preferences.default_sort)
      |> assign(:sort_direction, user_preferences.default_sort_direction)
      |> assign(:connection_status, "connecting")
      |> assign(:user_id, user_id)
      |> assign(:user_preferences, user_preferences)

    if connected?(socket) do
      # Subscribe to price updates (which affect exchange values too)
      case Phoenix.PubSub.subscribe(Sammelkarten.PubSub, "price_updates") do
        :ok ->
          socket = assign(socket, :connection_status, "connected")
          # Start heartbeat monitoring
          Process.send_after(self(), :heartbeat, 30_000)
          # Load cards asynchronously
          send(self(), :load_cards)
          {:ok, socket}

        {:error, _reason} ->
          socket =
            socket
            |> assign(:connection_status, "failed")
            |> assign(:error, "Failed to connect to real-time updates")

          # Still try to load cards
          send(self(), :load_cards)
          {:ok, socket}
      end
    else
      # Load cards asynchronously even when not connected
      send(self(), :load_cards)
      {:ok, socket}
    end
  end

  @impl true
  def handle_info({:price_update_completed, %{updated_count: _count}}, socket) do
    # Refresh all cards when price updates complete
    {:ok, cards} = Cards.list_cards()

    # Apply current filtering and sorting
    filtered_cards = filter_cards(cards, socket.assigns.search_term)

    sorted_cards =
      sort_cards(filtered_cards, socket.assigns.sort_by, socket.assigns.sort_direction)

    {:noreply, assign(socket, :cards, sorted_cards)}
  end

  @impl true
  def handle_info({:price_update_failed, %{reason: _reason}}, socket) do
    # Handle price update failures (could show a toast notification)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:price_updated, card_id, new_price, price_change}, socket) do
    # Legacy handler for individual card updates (if implemented later)
    updated_cards =
      Enum.map(socket.assigns.cards, fn card ->
        if card.id == card_id do
          %{card | current_price: new_price, price_change_24h: price_change}
        else
          card
        end
      end)

    {:noreply, assign(socket, :cards, updated_cards)}
  end

  @impl true
  def handle_info(:load_cards, socket) do
    case Cards.list_cards() do
      {:ok, cards} ->
        socket =
          socket
          |> assign(:cards, cards)
          |> assign(:loading, false)
          |> assign(:error, nil)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:cards, [])
          |> assign(:loading, false)
          |> assign(:error, "Failed to load cards: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:retry_load_cards, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> assign(:error, nil)

    send(self(), :load_cards)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:retry_connection, socket) do
    if connected?(socket) do
      case Phoenix.PubSub.subscribe(Sammelkarten.PubSub, "price_updates") do
        :ok ->
          socket = assign(socket, :connection_status, "connected")
          {:noreply, socket}

        {:error, _reason} ->
          socket = assign(socket, :connection_status, "failed")
          # Retry connection after 5 seconds
          Process.send_after(self(), :retry_connection, 5000)
          {:noreply, socket}
      end
    else
      # If not connected, mark as disconnected
      socket = assign(socket, :connection_status, "disconnected")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:heartbeat, socket) do
    # Send a heartbeat to check connection status
    if socket.assigns.connection_status == "connected" do
      # Try a simple operation to verify connection
      send(self(), :verify_connection)
    end

    # Schedule next heartbeat in 30 seconds
    Process.send_after(self(), :heartbeat, 30_000)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:verify_connection, socket) do
    # Verify the PubSub connection is still working by checking if we're connected
    if connected?(socket) do
      # Connection is still active
      {:noreply, socket}
    else
      # Connection lost, try to reconnect
      socket = assign(socket, :connection_status, "reconnecting")
      send(self(), :retry_connection)
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("search", %{"search" => %{"term" => term}}, socket) do
    {:ok, all_cards} = Cards.list_cards()
    filtered_cards = filter_cards(all_cards, term)
    {:noreply, assign(socket, cards: filtered_cards, search_term: term)}
  end

  @impl true
  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    current_sort = socket.assigns.sort_by

    direction =
      if current_sort == sort_by and socket.assigns.sort_direction == "asc",
        do: "desc",
        else: "asc"

    sorted_cards = sort_cards(socket.assigns.cards, sort_by, direction)

    {:noreply, assign(socket, cards: sorted_cards, sort_by: sort_by, sort_direction: direction)}
  end

  @impl true
  def handle_event("retry", _params, socket) do
    send(self(), :retry_load_cards)
    {:noreply, socket}
  end

  @impl true
  def handle_event("show_help", _params, socket) do
    # Toggle help modal state
    show_help = not Map.get(socket.assigns, :show_help, false)
    {:noreply, assign(socket, :show_help, show_help)}
  end

  @impl true
  def handle_event("refresh_data", _params, socket) do
    # Refresh card data
    send(self(), :load_cards)
    {:noreply, socket}
  end

  defp filter_cards(cards, ""), do: cards

  defp filter_cards(cards, term) do
    term = String.downcase(term)

    Enum.filter(cards, fn card ->
      String.contains?(String.downcase(card.name), term) or
        String.contains?(String.downcase(card.rarity), term)
    end)
  end

  defp sort_cards(cards, "name", "asc"), do: Enum.sort_by(cards, & &1.name)
  defp sort_cards(cards, "name", "desc"), do: Enum.sort_by(cards, & &1.name, :desc)
  defp sort_cards(cards, "offer", "asc"), do: Enum.sort_by(cards, &calculate_offer_quantity/1)

  defp sort_cards(cards, "offer", "desc"),
    do: Enum.sort_by(cards, &calculate_offer_quantity/1, :desc)

  defp sort_cards(cards, "search", "asc"), do: Enum.sort_by(cards, &calculate_search_quantity/1)

  defp sort_cards(cards, "search", "desc"),
    do: Enum.sort_by(cards, &calculate_search_quantity/1, :desc)

  # Fallback to price for backwards compatibility
  defp sort_cards(cards, "price", "asc"), do: Enum.sort_by(cards, & &1.current_price)
  defp sort_cards(cards, "price", "desc"), do: Enum.sort_by(cards, & &1.current_price, :desc)

  # Calculate offer quantity using the same logic as detail page
  defp calculate_offer_quantity(card) do
    try do
      # Load the same data as detail page
      regular_offers = load_regular_offers_for_card(card.id)
      exchange_offers = load_exchange_offers_for_card(card.id)
      bitcoin_offers = load_dynamic_bitcoin_offers_for_card(card.id)
      card_exchanges = load_dynamic_card_exchanges_for_card(card.id)

      # Apply the same filtering logic as detail page for offers
      sell_offers = Enum.filter(regular_offers, &(&1.offer_type == "sell"))
      
      exchange_offering_card = Enum.filter(exchange_offers, fn offer ->
        offer.offering_card.id == card.id
      end)
      
      bitcoin_sell_offers = Enum.filter(bitcoin_offers, &(&1.offer_type == "sell_for_sats"))
      
      card_exchange_offers = Enum.filter(card_exchanges, fn exchange ->
        exchange.exchange_type == "offer" and exchange.wanted_card.id == card.id
      end)

      # Count total offers (same as detail page display)
      length(sell_offers) + length(exchange_offering_card) + 
      length(bitcoin_sell_offers) + length(card_exchange_offers)
    rescue
      _ -> 0
    end
  end

  # Calculate search quantity using the same logic as detail page  
  defp calculate_search_quantity(card) do
    try do
      # Load the same data as detail page
      regular_offers = load_regular_offers_for_card(card.id)
      exchange_offers = load_exchange_offers_for_card(card.id)
      bitcoin_offers = load_dynamic_bitcoin_offers_for_card(card.id)
      card_exchanges = load_dynamic_card_exchanges_for_card(card.id)

      # Apply the same filtering logic as detail page for searches
      buy_offers = Enum.filter(regular_offers, &(&1.offer_type == "buy"))
      
      exchange_wanting_card = Enum.filter(exchange_offers, fn offer ->
        case offer.wanted_type do
          "open" -> true
          "specific" ->
            Enum.any?(offer.wanted_cards, fn {name, _, _} ->
              String.downcase(name) == String.downcase(card.name)
            end)
          _ -> false
        end
      end)
      
      bitcoin_buy_offers = Enum.filter(bitcoin_offers, &(&1.offer_type == "buy_for_sats"))
      
      card_exchange_searches = Enum.filter(card_exchanges, fn exchange ->
        exchange.exchange_type == "want" and
          (exchange.wanted_card.id == card.id or exchange.offered_card == nil)
      end)

      # Count total searches (same as detail page display)
      length(buy_offers) + length(exchange_wanting_card) + 
      length(bitcoin_buy_offers) + length(card_exchange_searches)
    rescue
      _ -> 0
    end
  end

  def format_offer_quantity(card) do
    quantity = calculate_offer_quantity(card)
    "#{quantity}"
  end

  def format_search_quantity(card) do
    quantity = calculate_search_quantity(card)
    "#{quantity}"
  end

  # Load regular buy/sell offers for this card (copied from CardDetailExchangeLive)
  defp load_regular_offers_for_card(card_id) do
    try do
      transaction = fn ->
        :mnesia.match_object(
          {:user_trades, :_, :_, card_id, :_, :_, :_, :_, :_, "open", :_, :_, :_}
        )
      end

      case :mnesia.transaction(transaction) do
        {:atomic, trade_records} ->
          trade_records
          |> Enum.filter(fn {_, _, _, _, trade_type, _, _, _, _, _, _, _, _} ->
            trade_type in ["buy", "sell"]
          end)
          |> Enum.map(&format_regular_offer/1)
          |> Enum.filter(fn offer -> offer != nil end)

        {:aborted, _reason} ->
          []
      end
    rescue
      _ ->
        []
    end
  end

  # Load exchange offers involving this card (copied from CardDetailExchangeLive)
  defp load_exchange_offers_for_card(card_id) do
    try do
      transaction = fn ->
        all_exchanges =
          :mnesia.match_object(
            {:user_trades, :_, :_, :_, "exchange", :_, :_, :_, :_, "open", :_, :_, :_}
          )

        Enum.filter(all_exchanges, fn {_, _, _, offering_card_id, _, _, _, _, wanted_data_json, _,
                                       _, _, _} ->
          if offering_card_id == card_id do
            true
          else
            case Jason.decode(wanted_data_json || "{}") do
              {:ok, wanted_data} ->
                wanted_card_ids = wanted_data["card_ids"] || []
                card_id in wanted_card_ids or wanted_data["type"] == "open"
              _ ->
                false
            end
          end
        end)
      end

      case :mnesia.transaction(transaction) do
        {:atomic, exchange_records} ->
          exchange_records
          |> Enum.map(&format_exchange_offer/1)
          |> Enum.filter(fn offer -> offer != nil end)

        {:aborted, _reason} ->
          []
      end
    rescue
      _ ->
        []
    end
  end

  # Load dynamic Bitcoin offers from MarketMaker (copied from CardDetailExchangeLive)
  defp load_dynamic_bitcoin_offers_for_card(card_id) do
    try do
      transaction = fn ->
        :mnesia.match_object(
          {:dynamic_bitcoin_offers, :_, :_, card_id, :_, :_, :_, "open", :_, :_}
        )
      end

      case :mnesia.transaction(transaction) do
        {:atomic, offer_records} ->
          offer_records
          |> Enum.map(&format_dynamic_bitcoin_offer/1)
          |> Enum.filter(fn offer -> offer != nil end)

        {:aborted, _reason} ->
          []
      end
    rescue
      _ ->
        []
    end
  end

  # Load dynamic card exchanges from MarketMaker (copied from CardDetailExchangeLive)
  defp load_dynamic_card_exchanges_for_card(card_id) do
    try do
      transaction = fn ->
        all_exchanges =
          :mnesia.match_object(
            {:dynamic_card_exchanges, :_, :_, :_, :_, :_, :_, "open", :_, :_}
          )

        Enum.filter(all_exchanges, fn {_, _, _, wanted_card_id, offered_card_id, _, _, _, _, _} ->
          wanted_card_id == card_id or offered_card_id == card_id or offered_card_id == nil
        end)
      end

      case :mnesia.transaction(transaction) do
        {:atomic, exchange_records} ->
          exchange_records
          |> Enum.map(&format_dynamic_card_exchange/1)
          |> Enum.filter(fn offer -> offer != nil end)

        {:aborted, _reason} ->
          []
      end
    rescue
      _ ->
        []
    end
  end

  # Format regular trading offer from database record (copied from CardDetailExchangeLive)
  defp format_regular_offer(
         {_, trade_id, user_pubkey, card_id, trade_type, quantity, price, total_value, _, "open",
          created_at, _, _}
       ) do
    case Cards.get_card(card_id) do
      {:ok, card} ->
        %{
          id: trade_id,
          trader: user_pubkey |> String.slice(0, 8),
          trader_pubkey: user_pubkey,
          offer_type: trade_type,
          card: card,
          quantity: quantity,
          price: price,
          total_value: total_value,
          created_at: created_at
        }
      {:error, _} ->
        nil
    end
  end

  # Format exchange offer from database record (copied from CardDetailExchangeLive)
  defp format_exchange_offer(
         {_, trade_id, user_pubkey, offering_card_id, "exchange", quantity, _wanted_hash, _,
          wanted_data_json, "open", created_at, _, _}
       ) do
    with {:ok, offering_card} <- Cards.get_card(offering_card_id),
         {:ok, wanted_data} <- Jason.decode(wanted_data_json || "{}") do
      wanted_type = wanted_data["type"]
      wanted_card_ids = wanted_data["card_ids"] || []

      wanted_cards =
        case wanted_type do
          "open" ->
            [{"Any Card", 1, "common"}]
          "specific" ->
            wanted_card_ids
            |> Enum.map(&Cards.get_card/1)
            |> Enum.filter(&match?({:ok, _}, &1))
            |> Enum.map(fn {:ok, card} -> {card.name, 1, card.rarity} end)
          _ ->
            []
        end

      %{
        id: trade_id,
        trader: user_pubkey |> String.slice(0, 8),
        trader_pubkey: user_pubkey,
        offer_type: "exchange",
        offering_card: offering_card,
        offering_bundle: [{offering_card.name, quantity, offering_card.rarity}],
        wanted_cards: wanted_cards,
        wanted_type: wanted_type,
        quantity: quantity,
        created_at: created_at
      }
    else
      _ -> nil
    end
  end

  # Format dynamic Bitcoin offer from database record (copied from CardDetailExchangeLive)
  defp format_dynamic_bitcoin_offer(
         {_, trade_id, user_pubkey, card_id, offer_type, quantity, sats_price, "open", created_at,
          _expires_at}
       ) do
    case Cards.get_card(card_id) do
      {:ok, card} ->
        %{
          id: trade_id,
          trader: user_pubkey |> String.slice(0, 8),
          trader_pubkey: user_pubkey,
          offer_type: offer_type,
          card: card,
          quantity: quantity,
          sats_price: sats_price,
          created_at: created_at
        }
      {:error, _} ->
        nil
    end
  end

  # Format dynamic card exchange from database record (copied from CardDetailExchangeLive)
  defp format_dynamic_card_exchange(
         {_, trade_id, user_pubkey, wanted_card_id, offered_card_id, offer_type, quantity, "open",
          created_at, _expires_at}
       ) do
    with {:ok, wanted_card} <- Cards.get_card(wanted_card_id) do
      {offering_bundle, offered_card} =
        case offered_card_id do
          nil ->
            {[{"Any Card", quantity, "common"}], nil}
          card_id ->
            case Cards.get_card(card_id) do
              {:ok, card} -> {[{card.name, quantity, card.rarity}], card}
              _ -> {[{"Unknown Card", quantity, "common"}], nil}
            end
        end

      %{
        id: trade_id,
        trader: user_pubkey |> String.slice(0, 8),
        trader_pubkey: user_pubkey,
        offer_type: "card_exchange",
        exchange_type: offer_type,
        wanted_card: wanted_card,
        offered_card: offered_card,
        offering_bundle: offering_bundle,
        wanted_bundle: [{wanted_card.name, quantity, wanted_card.rarity}],
        quantity: quantity,
        created_at: created_at
      }
    else
      _ -> nil
    end
  end

  def rarity_color(rarity) do
    case String.downcase(rarity) do
      "common" -> "bg-gray-100 text-gray-800"
      "uncommon" -> "bg-green-100 text-green-800"
      "rare" -> "bg-blue-100 text-blue-800"
      "epic" -> "bg-purple-100 text-purple-800"
      "legendary" -> "bg-yellow-100 text-yellow-800"
      "mythic" -> "bg-red-100 text-red-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end
end
