defmodule SammelkartenWeb.CardDetailExchangeLive do
  @moduledoc """
  LiveView for individual card detail pages in exchange mode.

  Shows comprehensive card exchange information including:
  - Card details and metadata
  - Live offers and searches by pseudonym traders
  - Exchange activity charts
  - Card image gallery
  """

  use SammelkartenWeb, :live_view

  alias Sammelkarten.{Cards, Formatter}
  alias Sammelkarten.Nostr.TestUsers
  require Logger

  @impl true
  def mount(%{"slug" => card_slug}, _session, socket) do
    case Cards.get_card_by_slug(card_slug) do
      {:ok, card} ->
        if connected?(socket) do
          # Subscribe to price updates for this specific card using the card ID
          Phoenix.PubSub.subscribe(Sammelkarten.PubSub, "card_prices:#{card.id}")
          # Subscribe to trade events for real-time updates
          Phoenix.PubSub.subscribe(Sammelkarten.PubSub, "trade_events")
        end

        mount_with_card(card, socket)

      {:error, :not_found} ->
        mount_with_error("Card not found", socket)

      {:error, reason} ->
        mount_with_error("Failed to load card: #{inspect(reason)}", socket)
    end
  end

  defp mount_with_card(card, socket) do
    # Load real exchange data from database
    {offer_traders, search_traders} = load_real_exchange_data(card)

    socket =
      socket
      |> assign(:card, card)
      |> assign(:offer_traders, offer_traders)
      |> assign(:search_traders, search_traders)
      |> assign(:loading, false)
      |> assign(:error, nil)

    {:ok, socket}
  end

  defp mount_with_error(error_message, socket) do
    socket =
      socket
      |> assign(:card, nil)
      |> assign(:offer_traders, [])
      |> assign(:search_traders, [])
      |> assign(:loading, false)
      |> assign(:error, error_message)

    {:ok, socket}
  end

  @impl true
  def handle_info({:price_updated, updated_card}, socket) do
    # Update the card if it matches the one we're displaying
    if socket.assigns.card && socket.assigns.card.id == updated_card.id do
      # Reload real exchange data
      {offer_traders, search_traders} = load_real_exchange_data(updated_card)

      socket =
        socket
        |> assign(:card, updated_card)
        |> assign(:offer_traders, offer_traders)
        |> assign(:search_traders, search_traders)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:new_trade_offer, _offer}, socket) do
    # Reload exchange data when new offers are created
    if socket.assigns.card do
      {offer_traders, search_traders} = load_real_exchange_data(socket.assigns.card)

      socket =
        socket
        |> assign(:offer_traders, offer_traders)
        |> assign(:search_traders, search_traders)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("go_back", _params, socket) do
    {:noreply, push_navigate(socket, to: "/")}
  end

  # Load real exchange data from database
  defp load_real_exchange_data(card) do
    try do
      # Load regular trading offers (buy/sell) for this card
      regular_offers = load_regular_offers_for_card(card.id)

      # Load exchange offers involving this card
      exchange_offers = load_exchange_offers_for_card(card.id)

      # Load dynamic Bitcoin offers from MarketMaker
      bitcoin_offers = load_dynamic_bitcoin_offers_for_card(card.id)

      # Load dynamic card exchanges from MarketMaker
      card_exchanges = load_dynamic_card_exchanges_for_card(card.id)

      # Separate into offers and searches based on the trade type and involvement
      offer_traders =
        format_offers_for_display(
          regular_offers,
          exchange_offers,
          bitcoin_offers,
          card_exchanges,
          card,
          :offer
        )

      search_traders =
        format_offers_for_display(
          regular_offers,
          exchange_offers,
          bitcoin_offers,
          card_exchanges,
          card,
          :search
        )

      {offer_traders, search_traders}
    rescue
      e ->
        Logger.error("Error loading exchange data for card #{card.id}: #{inspect(e)}")
        {[], []}
    end
  end

  # Load regular buy/sell offers for this card
  defp load_regular_offers_for_card(card_id) do
    try do
      transaction = fn ->
        :mnesia.match_object(
          {:user_trades, :_, :_, card_id, :_, :_, :_, :_, :_, "open", :_, :_, :_}
        )
      end

      case :mnesia.transaction(transaction) do
        {:atomic, trade_records} ->
          Logger.info("Found #{length(trade_records)} regular offers for card #{card_id}")

          trade_records
          |> Enum.filter(fn {_, _, _, _, trade_type, _, _, _, _, _, _, _, _} ->
            trade_type in ["buy", "sell"]
          end)
          |> Enum.map(&format_regular_offer/1)
          |> Enum.filter(fn offer -> offer != nil end)

        {:aborted, reason} ->
          Logger.error("Failed to load regular offers: #{inspect(reason)}")
          []
      end
    rescue
      e ->
        Logger.error("Error loading regular offers: #{inspect(e)}")
        []
    end
  end

  # Load exchange offers involving this card
  defp load_exchange_offers_for_card(card_id) do
    try do
      transaction = fn ->
        # Get all exchange offers
        all_exchanges =
          :mnesia.match_object(
            {:user_trades, :_, :_, :_, "exchange", :_, :_, :_, :_, "open", :_, :_, :_}
          )

        # Filter to include exchanges involving this card
        Enum.filter(all_exchanges, fn {_, _, _, offering_card_id, _, _, _, _, wanted_data_json, _,
                                       _, _, _} ->
          # Check if this card is being offered
          if offering_card_id == card_id do
            true
          else
            # Check if this card is wanted in the exchange
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
          Logger.info(
            "Found #{length(exchange_records)} exchange offers involving card #{card_id}"
          )

          exchange_records
          |> Enum.map(&format_exchange_offer/1)
          |> Enum.filter(fn offer -> offer != nil end)

        {:aborted, reason} ->
          Logger.error("Failed to load exchange offers: #{inspect(reason)}")
          []
      end
    rescue
      e ->
        Logger.error("Error loading exchange offers: #{inspect(e)}")
        []
    end
  end

  # Format regular trading offer from database record
  defp format_regular_offer(
         {_, trade_id, user_pubkey, card_id, trade_type, quantity, price, total_value, _, "open",
          created_at, _, _}
       ) do
    case Cards.get_card(card_id) do
      {:ok, card} ->
        minutes_ago = DateTime.diff(DateTime.utc_now(), created_at, :second) |> div(60)

        %{
          id: trade_id,
          trader: get_trader_display_name(user_pubkey),
          trader_pubkey: user_pubkey,
          trader_nip05: TestUsers.nip05_display_for_pubkey(user_pubkey),
          offer_type: trade_type,
          card: card,
          quantity: quantity,
          price: price,
          total_value: total_value,
          minutes_ago: minutes_ago,
          created_at: created_at
        }

      {:error, _} ->
        nil
    end
  end

  # Format exchange offer from database record
  defp format_exchange_offer(
         {_, trade_id, user_pubkey, offering_card_id, "exchange", quantity, _wanted_hash, _,
          wanted_data_json, "open", created_at, _, _}
       ) do
    with {:ok, offering_card} <- Cards.get_card(offering_card_id),
         {:ok, wanted_data} <- Jason.decode(wanted_data_json || "{}") do
      wanted_type = wanted_data["type"]
      wanted_card_ids = wanted_data["card_ids"] || []
      minutes_ago = DateTime.diff(DateTime.utc_now(), created_at, :second) |> div(60)

      # Get wanted cards info
      wanted_cards =
        case wanted_type do
          # Open to any card
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
        trader: get_trader_display_name(user_pubkey),
        trader_pubkey: user_pubkey,
        trader_nip05: TestUsers.nip05_display_for_pubkey(user_pubkey),
        offer_type: "exchange",
        offering_card: offering_card,
        offering_bundle: [{offering_card.name, quantity, offering_card.rarity}],
        wanted_cards: wanted_cards,
        wanted_type: wanted_type,
        quantity: quantity,
        minutes_ago: minutes_ago,
        created_at: created_at
      }
    else
      _ -> nil
    end
  end

  # Load dynamic Bitcoin offers from MarketMaker
  defp load_dynamic_bitcoin_offers_for_card(card_id) do
    try do
      transaction = fn ->
        :mnesia.match_object(
          {:dynamic_bitcoin_offers, :_, :_, card_id, :_, :_, :_, "open", :_, :_}
        )
      end

      case :mnesia.transaction(transaction) do
        {:atomic, offer_records} ->
          Logger.info("Found #{length(offer_records)} dynamic Bitcoin offers for card #{card_id}")

          offer_records
          |> Enum.map(&format_dynamic_bitcoin_offer/1)
          |> Enum.filter(fn offer -> offer != nil end)

        {:aborted, reason} ->
          Logger.error("Failed to load dynamic Bitcoin offers: #{inspect(reason)}")
          []
      end
    rescue
      e ->
        Logger.error("Error loading dynamic Bitcoin offers: #{inspect(e)}")
        []
    end
  end

  # Load dynamic card exchanges from MarketMaker
  defp load_dynamic_card_exchanges_for_card(card_id) do
    try do
      transaction = fn ->
        # Get all dynamic exchanges
        all_exchanges =
          :mnesia.match_object({:dynamic_card_exchanges, :_, :_, :_, :_, :_, :_, "open", :_, :_})

        # Filter to include exchanges involving this card
        Enum.filter(all_exchanges, fn {_, _, _, wanted_card_id, offered_card_id, _, _, _, _, _} ->
          wanted_card_id == card_id or offered_card_id == card_id or offered_card_id == nil
        end)
      end

      case :mnesia.transaction(transaction) do
        {:atomic, exchange_records} ->
          Logger.info(
            "Found #{length(exchange_records)} dynamic exchange offers involving card #{card_id}"
          )

          exchange_records
          |> Enum.map(&format_dynamic_card_exchange/1)
          |> Enum.filter(fn offer -> offer != nil end)

        {:aborted, reason} ->
          Logger.error("Failed to load dynamic card exchanges: #{inspect(reason)}")
          []
      end
    rescue
      e ->
        Logger.error("Error loading dynamic card exchanges: #{inspect(e)}")
        []
    end
  end

  # Format dynamic Bitcoin offer from database record
  defp format_dynamic_bitcoin_offer(
         {_, trade_id, user_pubkey, card_id, offer_type, quantity, sats_price, "open", created_at,
          _expires_at}
       ) do
    case Cards.get_card(card_id) do
      {:ok, card} ->
        minutes_ago = DateTime.diff(DateTime.utc_now(), created_at, :second) |> div(60)

        %{
          id: trade_id,
          trader: get_trader_display_name(user_pubkey),
          trader_pubkey: user_pubkey,
          trader_nip05: TestUsers.nip05_display_for_pubkey(user_pubkey),
          offer_type: offer_type,
          card: card,
          quantity: quantity,
          sats_price: sats_price,
          minutes_ago: minutes_ago,
          created_at: created_at
        }

      {:error, _} ->
        nil
    end
  end

  # Format dynamic card exchange from database record
  defp format_dynamic_card_exchange(
         {_, trade_id, user_pubkey, wanted_card_id, offered_card_id, offer_type, quantity, "open",
          created_at, _expires_at}
       ) do
    with {:ok, wanted_card} <- Cards.get_card(wanted_card_id) do
      minutes_ago = DateTime.diff(DateTime.utc_now(), created_at, :second) |> div(60)

      # Handle offered card (nil means "any card")
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
        trader: get_trader_display_name(user_pubkey),
        trader_pubkey: user_pubkey,
        trader_nip05: TestUsers.nip05_display_for_pubkey(user_pubkey),
        offer_type: "card_exchange",
        exchange_type: offer_type,
        wanted_card: wanted_card,
        offered_card: offered_card,
        offering_bundle: offering_bundle,
        wanted_bundle: [{wanted_card.name, quantity, wanted_card.rarity}],
        quantity: quantity,
        minutes_ago: minutes_ago,
        created_at: created_at
      }
    else
      _ -> nil
    end
  end

  # Format offers for display, separating into offers and searches
  defp format_offers_for_display(
         regular_offers,
         exchange_offers,
         bitcoin_offers,
         card_exchanges,
         current_card,
         display_type
       ) do
    case display_type do
      :offer ->
        # Show sell offers (people offering this card) and exchange offers offering this card
        sell_offers = Enum.filter(regular_offers, &(&1.offer_type == "sell"))

        exchange_offering_card =
          Enum.filter(exchange_offers, fn offer ->
            offer.offering_card.id == current_card.id
          end)

        # Bitcoin sell offers (sell_for_sats)
        bitcoin_sell_offers = Enum.filter(bitcoin_offers, &(&1.offer_type == "sell_for_sats"))

        # Card exchanges offering this card
        card_exchange_offers =
          Enum.filter(card_exchanges, fn exchange ->
            exchange.exchange_type == "offer" and exchange.wanted_card.id == current_card.id
          end)

        # Convert to unified format
        formatted_sells = Enum.map(sell_offers, &format_as_offer_display/1)

        formatted_exchanges =
          Enum.map(exchange_offering_card, &format_exchange_as_offer_display/1)

        formatted_bitcoin_sells =
          Enum.map(bitcoin_sell_offers, &format_bitcoin_as_offer_display/1)

        formatted_card_exchanges =
          Enum.map(card_exchange_offers, &format_card_exchange_as_offer_display/1)

        (formatted_sells ++
           formatted_exchanges ++ formatted_bitcoin_sells ++ formatted_card_exchanges)
        |> Enum.sort_by(& &1.minutes_ago, :asc)

      :search ->
        # Show buy offers (people searching for this card) and exchange offers wanting this card
        buy_offers = Enum.filter(regular_offers, &(&1.offer_type == "buy"))

        exchange_wanting_card =
          Enum.filter(exchange_offers, fn offer ->
            case offer.wanted_type do
              "open" ->
                true

              "specific" ->
                Enum.any?(offer.wanted_cards, fn {name, _, _} ->
                  String.downcase(name) == String.downcase(current_card.name)
                end)

              _ ->
                false
            end
          end)

        # Bitcoin buy offers (buy_for_sats)
        bitcoin_buy_offers = Enum.filter(bitcoin_offers, &(&1.offer_type == "buy_for_sats"))

        # Card exchanges wanting this card
        card_exchange_searches =
          Enum.filter(card_exchanges, fn exchange ->
            exchange.exchange_type == "want" and
              (exchange.wanted_card.id == current_card.id or exchange.offered_card == nil)
          end)

        # Convert to unified format
        formatted_buys = Enum.map(buy_offers, &format_as_search_display/1)

        formatted_exchanges =
          Enum.map(exchange_wanting_card, &format_exchange_as_search_display/1)

        formatted_bitcoin_buys = Enum.map(bitcoin_buy_offers, &format_bitcoin_as_search_display/1)

        formatted_card_searches =
          Enum.map(card_exchange_searches, &format_card_exchange_as_search_display/1)

        (formatted_buys ++
           formatted_exchanges ++ formatted_bitcoin_buys ++ formatted_card_searches)
        |> Enum.sort_by(& &1.minutes_ago, :asc)
    end
  end

  # Format regular sell offer for display
  defp format_as_offer_display(offer) do
    %{
      trader: offer.trader,
      trader_pubkey: offer.trader_pubkey,
      trader_nip05: offer.trader_nip05,
      offer_bundle: [{offer.card.name, offer.quantity, offer.card.rarity}],
      # What they want in return
      search_bundle: [{"Bitcoin Sats", offer.total_value, "currency"}],
      minutes_ago: offer.minutes_ago,
      offer_type: "sell",
      price: offer.price
    }
  end

  # Format regular buy offer for display
  defp format_as_search_display(offer) do
    %{
      trader: offer.trader,
      trader_pubkey: offer.trader_pubkey,
      trader_nip05: offer.trader_nip05,
      # What they're offering
      offer_bundle: [{"Bitcoin Sats", offer.total_value, "currency"}],
      # What they want
      search_bundle: [{offer.card.name, offer.quantity, offer.card.rarity}],
      minutes_ago: offer.minutes_ago,
      offer_type: "buy",
      price: offer.price
    }
  end

  # Format exchange offer for display (offering this card)
  defp format_exchange_as_offer_display(exchange) do
    %{
      trader: exchange.trader,
      trader_pubkey: exchange.trader_pubkey,
      trader_nip05: exchange.trader_nip05,
      offer_bundle: exchange.offering_bundle,
      search_bundle: exchange.wanted_cards,
      minutes_ago: exchange.minutes_ago,
      offer_type: "exchange"
    }
  end

  # Format exchange offer for display (wanting this card)
  defp format_exchange_as_search_display(exchange) do
    %{
      trader: exchange.trader,
      trader_pubkey: exchange.trader_pubkey,
      trader_nip05: exchange.trader_nip05,
      # What they're offering
      offer_bundle: exchange.offering_bundle,
      # What they want (includes current card)
      search_bundle: exchange.wanted_cards,
      minutes_ago: exchange.minutes_ago,
      offer_type: "exchange"
    }
  end

  # Format Bitcoin sell offer for display (offering card for sats)
  defp format_bitcoin_as_offer_display(bitcoin_offer) do
    %{
      trader: bitcoin_offer.trader,
      trader_pubkey: bitcoin_offer.trader_pubkey,
      trader_nip05: bitcoin_offer.trader_nip05,
      offer_bundle: [{bitcoin_offer.card.name, bitcoin_offer.quantity, bitcoin_offer.card.rarity}],
      # What they want in return (Bitcoin sats)
      search_bundle: [{"Bitcoin Sats", bitcoin_offer.sats_price, "currency"}],
      minutes_ago: bitcoin_offer.minutes_ago,
      offer_type: "bitcoin_sell"
    }
  end

  # Format Bitcoin buy offer for display (offering sats for card)
  defp format_bitcoin_as_search_display(bitcoin_offer) do
    %{
      trader: bitcoin_offer.trader,
      trader_pubkey: bitcoin_offer.trader_pubkey,
      trader_nip05: bitcoin_offer.trader_nip05,
      # What they're offering (Bitcoin sats)
      offer_bundle: [{"Bitcoin Sats", bitcoin_offer.sats_price, "currency"}],
      # What they want
      search_bundle: [
        {bitcoin_offer.card.name, bitcoin_offer.quantity, bitcoin_offer.card.rarity}
      ],
      minutes_ago: bitcoin_offer.minutes_ago,
      offer_type: "bitcoin_buy"
    }
  end

  # Format card exchange as offer display (offering card for another)
  defp format_card_exchange_as_offer_display(card_exchange) do
    %{
      trader: card_exchange.trader,
      trader_pubkey: card_exchange.trader_pubkey,
      trader_nip05: card_exchange.trader_nip05,
      offer_bundle: card_exchange.offering_bundle,
      search_bundle: card_exchange.wanted_bundle,
      minutes_ago: card_exchange.minutes_ago,
      offer_type: "card_exchange_offer"
    }
  end

  # Format card exchange as search display (wanting card, offering another)
  defp format_card_exchange_as_search_display(card_exchange) do
    %{
      trader: card_exchange.trader,
      trader_pubkey: card_exchange.trader_pubkey,
      trader_nip05: card_exchange.trader_nip05,
      # What they're offering
      offer_bundle: card_exchange.offering_bundle,
      # What they want
      search_bundle: card_exchange.wanted_bundle,
      minutes_ago: card_exchange.minutes_ago,
      offer_type: "card_exchange_search"
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="min-h-screen bg-gray-50 dark:bg-gray-900 page-transition"
      id="card-exchange-detail-container"
      phx-hook="CardDetailKeyboardShortcuts"
    >
      <%= if @error do %>
        <div class="max-w-4xl mx-auto px-4 py-8">
          <div class="bg-red-50 dark:bg-red-900 border border-red-200 dark:border-red-700 rounded-lg p-6 text-center">
            <h2 class="text-xl font-semibold text-red-800 dark:text-red-100 mb-2">Error</h2>
            <p class="text-red-600 dark:text-red-300">{@error}</p>
            <.link
              navigate="/"
              class="inline-block mt-4 text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 underline"
            >
              ← Back to Exchange
            </.link>
          </div>
        </div>
      <% else %>
        <%= if @card do %>
          <!-- Breadcrumb Navigation -->
          <div class="bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 animate-slide-in-top">
            <div class="max-w-6xl mx-auto px-4 py-3">
              <nav class="flex" aria-label="Breadcrumb">
                <ol class="flex items-center space-x-2 text-sm text-gray-500 dark:text-gray-400">
                  <li>
                    <.link navigate="/" class="hover:text-gray-700 dark:hover:text-gray-300">
                      Card Collection Exchange
                    </.link>
                  </li>
                  <li class="flex items-center">
                    <svg class="w-4 h-4 mx-2" fill="currentColor" viewBox="0 0 20 20">
                      <path
                        fill-rule="evenodd"
                        d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z"
                        clip-rule="evenodd"
                      />
                    </svg>
                    <span class="font-medium text-gray-900 dark:text-white">{@card.name}</span>
                  </li>
                </ol>
              </nav>
            </div>
          </div>
          
    <!-- Main Content -->
          <div class="max-w-6xl mx-auto px-4 py-8">
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
              
    <!-- Left Column: Card Image and Basic Info -->
              <div class="space-y-6 animate-fade-in-up">
                <!-- Card Image -->
                <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6 card-hover">
                  <div
                    class="bg-gray-100 dark:bg-gray-700 rounded-lg overflow-hidden flex items-center justify-center"
                    style="min-height: 630px;"
                  >
                    <img
                      src={@card.image_path}
                      alt={@card.name}
                      class="card-image-hover w-full h-full object-contain"
                      style="max-height: 600px;"
                    />
                  </div>
                </div>
                
    <!-- Card Metadata -->
                <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
                  <h3 class="text-lg font-semibold text-gray-900 dark:text-white mb-4">
                    Card Details
                  </h3>
                  <div class="space-y-3">
                    <div class="flex justify-between">
                      <span class="text-gray-600 dark:text-gray-400">Rarity</span>
                      <span class={[
                        "px-2 py-1 rounded-full text-xs font-medium",
                        rarity_color_class(@card.rarity)
                      ]}>
                        {String.upcase(@card.rarity)}
                      </span>
                    </div>
                    <div class="flex justify-between">
                      <span class="text-gray-600 dark:text-gray-400">Current Market Price</span>
                      <span class="text-gray-900 dark:text-white font-medium">
                        {format_price(@card.current_price)}
                      </span>
                    </div>
                    <div class="flex justify-between">
                      <span class="text-gray-600 dark:text-gray-400">Last Updated</span>
                      <span class="text-gray-900 dark:text-white">
                        {format_datetime(@card.last_updated)}
                      </span>
                    </div>
                  </div>

                  <%= if @card.description && @card.description != "" do %>
                    <div class="mt-6 pt-6 border-t border-gray-200 dark:border-gray-700">
                      <h4 class="font-medium text-gray-900 dark:text-white mb-2">Description</h4>
                      <p class="text-gray-600 dark:text-gray-400 text-sm leading-relaxed">
                        {@card.description}
                      </p>
                    </div>
                  <% end %>
                </div>
              </div>
              
    <!-- Right Column: Exchange Activity -->
              <div class="space-y-6 animate-fade-in-up" style="animation-delay: 0.2s;">
                <!-- Card Title -->
                <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6 card-hover">
                  <h1 class="text-2xl font-bold text-gray-900 dark:text-white mb-2">{@card.name}</h1>
                  <p class="text-gray-600 dark:text-gray-400">Exchange Activity</p>
                </div>
                
    <!-- Offers Section -->
                <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
                  <div class="flex items-center justify-between mb-4">
                    <h3 class="text-lg font-semibold text-gray-900 dark:text-white flex items-center">
                      <svg class="w-5 h-5 text-green-500 mr-2" fill="currentColor" viewBox="0 0 20 20">
                        <path
                          fill-rule="evenodd"
                          d="M10.293 3.293a1 1 0 011.414 0l6 6a1 1 0 010 1.414l-6 6a1 1 0 01-1.414-1.414L14.586 11H3a1 1 0 110-2h11.586l-4.293-4.293a1 1 0 010-1.414z"
                          clip-rule="evenodd"
                        />
                      </svg>
                      Offers ({length(@offer_traders)})
                    </h3>
                  </div>

                  <%= if length(@offer_traders) > 0 do %>
                    <div class="space-y-4">
                      <%= for offer <- @offer_traders do %>
                        <div class="p-4 bg-green-50 dark:bg-green-900/20 rounded-lg border border-green-200 dark:border-green-800">
                          <!-- Trader Header -->
                          <div class="flex items-center justify-between mb-3">
                            <div class="flex items-center space-x-3">
                              <div class="w-8 h-8 bg-green-500 rounded-full flex items-center justify-center">
                                <span class="text-white text-xs font-bold">
                                  {String.slice(offer.trader, 0, 1)}
                                </span>
                              </div>
                              <div>
                                <p class="font-medium text-gray-900 dark:text-white">
                                  {offer.trader}
                                </p>
                                <%= if offer.trader_nip05 do %>
                                  <p class="text-xs text-green-600 dark:text-green-400 font-mono">
                                    {offer.trader_nip05}
                                  </p>
                                <% end %>
                                <p class="text-xs text-gray-500 dark:text-gray-400">
                                  {format_time_ago(offer.minutes_ago)} ago
                                </p>
                              </div>
                            </div>
                            <span class="text-xs font-medium text-green-600 dark:text-green-400 bg-green-100 dark:bg-green-800 px-2 py-1 rounded-full">
                              OFFERING
                            </span>
                          </div>
                          
    <!-- Exchange Visual -->
                          <div class="flex flex-col sm:flex-row sm:items-center space-y-4 sm:space-y-0 sm:space-x-4">
                            <!-- What they're offering -->
                            <div class="flex-1">
                              <p class="text-xs font-medium text-gray-600 dark:text-gray-400 mb-2 uppercase tracking-wide">
                                Offering
                              </p>
                              <div class="space-y-1">
                                <%= for {card_name, quantity, rarity} <- offer.offer_bundle do %>
                                  <div class="flex items-center justify-between p-2 bg-white dark:bg-gray-800 rounded border">
                                    <div class="flex items-center space-x-2">
                                      <span class={["w-2 h-2 rounded-full", rarity_dot_color(rarity)]}>
                                      </span>
                                      <span class="text-sm font-medium text-gray-900 dark:text-white">
                                        {card_name}
                                      </span>
                                    </div>
                                    <span class="text-sm font-bold text-green-600 dark:text-green-400">
                                      ×{quantity}
                                    </span>
                                  </div>
                                <% end %>
                              </div>
                            </div>
                            
    <!-- Exchange Arrow -->
                            <div class="flex flex-col items-center justify-center px-2 py-2">
                              <svg
                                class="w-6 h-6 sm:w-8 sm:h-8 text-gray-400 transform rotate-90 sm:rotate-0"
                                fill="none"
                                stroke="currentColor"
                                viewBox="0 0 24 24"
                              >
                                <path
                                  stroke-linecap="round"
                                  stroke-linejoin="round"
                                  stroke-width="2"
                                  d="M13 7l5 5m0 0l-5 5m5-5H6"
                                >
                                </path>
                              </svg>
                              <span class="text-xs text-gray-500 mt-1">FOR</span>
                            </div>
                            
    <!-- What they want -->
                            <div class="flex-1">
                              <p class="text-xs font-medium text-gray-600 dark:text-gray-400 mb-2 uppercase tracking-wide">
                                Wants
                              </p>
                              <div class="space-y-1">
                                <%= for {card_name, quantity, rarity} <- offer.search_bundle do %>
                                  <div class="flex items-center justify-between p-2 bg-white dark:bg-gray-800 rounded border">
                                    <div class="flex items-center space-x-2">
                                      <span class={["w-2 h-2 rounded-full", rarity_dot_color(rarity)]}>
                                      </span>
                                      <span class="text-sm font-medium text-gray-900 dark:text-white">
                                        {card_name}
                                      </span>
                                    </div>
                                    <span class="text-sm font-bold text-blue-600 dark:text-blue-400">
                                      ×{quantity}
                                    </span>
                                  </div>
                                <% end %>
                              </div>
                            </div>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  <% else %>
                    <div class="text-center py-8 text-gray-500 dark:text-gray-400">
                      <svg
                        class="mx-auto h-12 w-12 text-gray-400 dark:text-gray-500 mb-4"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                        />
                      </svg>
                      <p>No active offers for this card.</p>
                      <p class="text-xs mt-1">Be the first to make an offer!</p>
                    </div>
                  <% end %>
                </div>
                
    <!-- Searches Section -->
                <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
                  <div class="flex items-center justify-between mb-4">
                    <h3 class="text-lg font-semibold text-gray-900 dark:text-white flex items-center">
                      <svg class="w-5 h-5 text-blue-500 mr-2" fill="currentColor" viewBox="0 0 20 20">
                        <path
                          fill-rule="evenodd"
                          d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z"
                          clip-rule="evenodd"
                        />
                      </svg>
                      Searches ({length(@search_traders)})
                    </h3>
                  </div>

                  <%= if length(@search_traders) > 0 do %>
                    <div class="space-y-4">
                      <%= for search <- @search_traders do %>
                        <div class="p-4 bg-blue-50 dark:bg-blue-900/20 rounded-lg border border-blue-200 dark:border-blue-800">
                          <!-- Trader Header -->
                          <div class="flex items-center justify-between mb-3">
                            <div class="flex items-center space-x-3">
                              <div class="w-8 h-8 bg-blue-500 rounded-full flex items-center justify-center">
                                <span class="text-white text-xs font-bold">
                                  {String.slice(search.trader, 0, 1)}
                                </span>
                              </div>
                              <div>
                                <p class="font-medium text-gray-900 dark:text-white">
                                  {search.trader}
                                </p>
                                <%= if search.trader_nip05 do %>
                                  <p class="text-xs text-blue-600 dark:text-blue-400 font-mono">
                                    {search.trader_nip05}
                                  </p>
                                <% end %>
                                <p class="text-xs text-gray-500 dark:text-gray-400">
                                  {format_time_ago(search.minutes_ago)} ago
                                </p>
                              </div>
                            </div>
                            <span class="text-xs font-medium text-blue-600 dark:text-blue-400 bg-blue-100 dark:bg-blue-800 px-2 py-1 rounded-full">
                              SEARCHING
                            </span>
                          </div>
                          
    <!-- Exchange Visual -->
                          <div class="flex flex-col sm:flex-row sm:items-center space-y-4 sm:space-y-0 sm:space-x-4">
                            <!-- What they want -->
                            <div class="flex-1">
                              <p class="text-xs font-medium text-gray-600 dark:text-gray-400 mb-2 uppercase tracking-wide">
                                Looking For
                              </p>
                              <div class="space-y-1">
                                <%= for {card_name, quantity, rarity} <- search.search_bundle do %>
                                  <div class="flex items-center justify-between p-2 bg-white dark:bg-gray-800 rounded border">
                                    <div class="flex items-center space-x-2">
                                      <span class={["w-2 h-2 rounded-full", rarity_dot_color(rarity)]}>
                                      </span>
                                      <span class="text-sm font-medium text-gray-900 dark:text-white">
                                        {card_name}
                                      </span>
                                    </div>
                                    <span class="text-sm font-bold text-blue-600 dark:text-blue-400">
                                      ×{quantity}
                                    </span>
                                  </div>
                                <% end %>
                              </div>
                            </div>
                            
    <!-- Exchange Arrow -->
                            <div class="flex flex-col items-center justify-center px-2 py-2">
                              <svg
                                class="w-6 h-6 sm:w-8 sm:h-8 text-gray-400 transform rotate-90 sm:rotate-0"
                                fill="none"
                                stroke="currentColor"
                                viewBox="0 0 24 24"
                              >
                                <path
                                  stroke-linecap="round"
                                  stroke-linejoin="round"
                                  stroke-width="2"
                                  d="M7 16l-4-4m0 0l4-4m-4 4h18"
                                >
                                </path>
                              </svg>
                              <span class="text-xs text-gray-500 mt-1">FOR</span>
                            </div>
                            
    <!-- What they're offering -->
                            <div class="flex-1">
                              <p class="text-xs font-medium text-gray-600 dark:text-gray-400 mb-2 uppercase tracking-wide">
                                Offering
                              </p>
                              <div class="space-y-1">
                                <%= for {card_name, quantity, rarity} <- search.offer_bundle do %>
                                  <div class="flex items-center justify-between p-2 bg-white dark:bg-gray-800 rounded border">
                                    <div class="flex items-center space-x-2">
                                      <span class={["w-2 h-2 rounded-full", rarity_dot_color(rarity)]}>
                                      </span>
                                      <span class="text-sm font-medium text-gray-900 dark:text-white">
                                        {card_name}
                                      </span>
                                    </div>
                                    <span class="text-sm font-bold text-green-600 dark:text-green-400">
                                      ×{quantity}
                                    </span>
                                  </div>
                                <% end %>
                              </div>
                            </div>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  <% else %>
                    <div class="text-center py-8 text-gray-500 dark:text-gray-400">
                      <svg
                        class="mx-auto h-12 w-12 text-gray-400 dark:text-gray-500 mb-4"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
                        />
                      </svg>
                      <p>No active searches for this card.</p>
                      <p class="text-xs mt-1">Start a search to find this card!</p>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # Helper functions

  defp get_trader_display_name(pubkey) do
    TestUsers.display_name_for_pubkey(pubkey)
  end

  defp format_price(price_in_sats) when is_integer(price_in_sats) do
    Formatter.format_german_price(price_in_sats)
  end

  defp format_price(price) when is_float(price) do
    price_sats = trunc(price)
    Formatter.format_german_price(price_sats)
  end

  defp rarity_color_class("common"),
    do: "bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200"

  defp rarity_color_class("uncommon"),
    do: "bg-green-100 dark:bg-green-800 text-green-800 dark:text-green-200"

  defp rarity_color_class("rare"),
    do: "bg-blue-100 dark:bg-blue-800 text-blue-800 dark:text-blue-200"

  defp rarity_color_class("epic"),
    do: "bg-purple-100 dark:bg-purple-800 text-purple-800 dark:text-purple-200"

  defp rarity_color_class("legendary"),
    do: "bg-yellow-100 dark:bg-yellow-800 text-yellow-800 dark:text-yellow-200"

  defp rarity_color_class("mythic"),
    do: "bg-red-100 dark:bg-red-800 text-red-800 dark:text-red-200"

  defp rarity_color_class(_), do: "bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200"

  defp rarity_dot_color("common"), do: "bg-gray-400"
  defp rarity_dot_color("uncommon"), do: "bg-green-400"
  defp rarity_dot_color("rare"), do: "bg-blue-400"
  defp rarity_dot_color("epic"), do: "bg-purple-400"
  defp rarity_dot_color("legendary"), do: "bg-yellow-400"
  defp rarity_dot_color("mythic"), do: "bg-red-400"
  defp rarity_dot_color("currency"), do: "bg-orange-400"
  defp rarity_dot_color(_), do: "bg-gray-400"

  defp format_datetime(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
    |> String.replace("T", " ")
    |> String.replace("Z", " UTC")
  end

  defp format_time_ago(minutes) when minutes < 60 do
    "#{minutes}m"
  end

  defp format_time_ago(minutes) do
    hours = div(minutes, 60)
    "#{hours}h"
  end
end
