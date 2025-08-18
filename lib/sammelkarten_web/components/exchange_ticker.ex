defmodule SammelkartenWeb.Components.ExchangeTicker do
  @moduledoc """
  Exchange ticker component that displays streaming exchange activity for all cards.

  This component shows a horizontally scrolling ticker with offer and search quantities
  for peer-to-peer card trading, similar to financial news tickers but focused on
  exchange activity rather than price changes.
  """

  use SammelkartenWeb, :live_component

  @impl true
  def update(assigns, socket) do
    # Filter cards to show only those with active trading (either offers or searches)
    ticker_cards =
      assigns.cards
      |> Enum.filter(fn card ->
        calculate_offer_quantity(card) > 0 or calculate_search_quantity(card) > 0
      end)
      |> Enum.sort_by(
        fn card ->
          # Sort by total activity (offers + searches) descending
          calculate_offer_quantity(card) + calculate_search_quantity(card)
        end,
        :desc
      )
      # Limit to 10 most active cards for performance
      |> Enum.take(10)

    socket =
      socket
      |> assign(:cards, ticker_cards)
      |> assign(:last_update, DateTime.utc_now())

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-gray-900 text-white border-b border-gray-700">
      <div class="relative overflow-hidden">
        <%= if length(@cards) > 0 do %>
          <!-- Ticker Content -->
          <div class="flex animate-ticker-scroll">
            <!-- First set of cards -->
            <div class="flex space-x-8 px-4 py-2 whitespace-nowrap">
              <%= for card <- @cards do %>
                <div class="flex items-center space-x-3 text-sm">
                  <span class="font-medium text-blue-300">{card.name}</span>
                  
    <!-- Offer Information -->
                  <%= if calculate_offer_quantity(card) > 0 do %>
                    <span class="flex items-center space-x-1 text-xs font-medium text-green-400">
                      <!-- Offer Icon (Arrow) -->
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M17 8l4 4m0 0l-4 4m4-4H3"
                        >
                        </path>
                      </svg>
                      <span>{calculate_offer_quantity(card)}</span>
                    </span>
                  <% end %>
                  
    <!-- Search Information -->
                  <%= if calculate_search_quantity(card) > 0 do %>
                    <span class="flex items-center space-x-1 text-xs font-medium text-blue-400">
                      <!-- Search Icon -->
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
                        >
                        </path>
                      </svg>
                      <span>{calculate_search_quantity(card)}</span>
                    </span>
                  <% end %>
                  
    <!-- Market Activity Indicator -->
                  <span class="flex items-center space-x-1 text-xs font-medium text-purple-400">
                    <div class="w-2 h-2 bg-purple-400 rounded-full animate-pulse"></div>
                    <span>active</span>
                  </span>
                </div>
              <% end %>
            </div>
            
    <!-- Duplicate set for seamless scrolling -->
            <div class="flex space-x-8 px-4 py-2 whitespace-nowrap">
              <%= for card <- @cards do %>
                <div class="flex items-center space-x-3 text-sm">
                  <span class="font-medium text-blue-300">{card.name}</span>
                  
    <!-- Offer Information -->
                  <%= if calculate_offer_quantity(card) > 0 do %>
                    <span class="flex items-center space-x-1 text-xs font-medium text-green-400">
                      <!-- Offer Icon (Arrow) -->
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M17 8l4 4m0 0l-4 4m4-4H3"
                        >
                        </path>
                      </svg>
                      <span>{calculate_offer_quantity(card)}</span>
                    </span>
                  <% end %>
                  
    <!-- Search Information -->
                  <%= if calculate_search_quantity(card) > 0 do %>
                    <span class="flex items-center space-x-1 text-xs font-medium text-blue-400">
                      <!-- Search Icon -->
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
                        >
                        </path>
                      </svg>
                      <span>{calculate_search_quantity(card)}</span>
                    </span>
                  <% end %>
                  
    <!-- Market Activity Indicator -->
                  <span class="flex items-center space-x-1 text-xs font-medium text-purple-400">
                    <div class="w-2 h-2 bg-purple-400 rounded-full animate-pulse"></div>
                    <span>active</span>
                  </span>
                </div>
              <% end %>
            </div>
          </div>
          
    <!-- Last update indicator -->
          <%= if @last_update do %>
            <div class="absolute right-0 top-0 bottom-0 bg-gradient-to-l from-gray-900 to-transparent w-20 flex items-center justify-end pr-2">
              <div class="text-xs text-gray-400" title={"Last updated: #{format_time(@last_update)}"}>
                <div class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
              </div>
            </div>
          <% end %>
        <% else %>
          <div class="px-4 py-2 text-center text-gray-400 text-sm">
            <span>🔄 Waiting for exchange activity...</span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper functions - using same database lookup logic as DashboardExchangeLive

  # Calculate offer quantity using the same logic as DashboardExchangeLive
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

  # Calculate search quantity using the same logic as DashboardExchangeLive  
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

  # Load regular buy/sell offers for this card (copied from DashboardExchangeLive)
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

  # Load exchange offers involving this card (copied from DashboardExchangeLive)
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

  # Load dynamic Bitcoin offers from MarketMaker (copied from DashboardExchangeLive)
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

  # Load dynamic card exchanges from MarketMaker (copied from DashboardExchangeLive)
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

  # Format regular trading offer from database record (copied from DashboardExchangeLive)
  defp format_regular_offer(
         {_, trade_id, user_pubkey, card_id, trade_type, quantity, price, total_value, _, "open",
          created_at, _, _}
       ) do
    case Sammelkarten.Cards.get_card(card_id) do
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

  # Format exchange offer from database record (copied from DashboardExchangeLive)
  defp format_exchange_offer(
         {_, trade_id, user_pubkey, offering_card_id, "exchange", quantity, _wanted_hash, _,
          wanted_data_json, "open", created_at, _, _}
       ) do
    with {:ok, offering_card} <- Sammelkarten.Cards.get_card(offering_card_id),
         {:ok, wanted_data} <- Jason.decode(wanted_data_json || "{}") do
      wanted_type = wanted_data["type"]
      wanted_card_ids = wanted_data["card_ids"] || []

      wanted_cards =
        case wanted_type do
          "open" ->
            [{"Any Card", 1, "common"}]
          "specific" ->
            wanted_card_ids
            |> Enum.map(&Sammelkarten.Cards.get_card/1)
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

  # Format dynamic Bitcoin offer from database record (copied from DashboardExchangeLive)
  defp format_dynamic_bitcoin_offer(
         {_, trade_id, user_pubkey, card_id, offer_type, quantity, sats_price, "open", created_at,
          _expires_at}
       ) do
    case Sammelkarten.Cards.get_card(card_id) do
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

  # Format dynamic card exchange from database record (copied from DashboardExchangeLive)
  defp format_dynamic_card_exchange(
         {_, trade_id, user_pubkey, wanted_card_id, offered_card_id, offer_type, quantity, "open",
          created_at, _expires_at}
       ) do
    with {:ok, wanted_card} <- Sammelkarten.Cards.get_card(wanted_card_id) do
      {offering_bundle, offered_card} =
        case offered_card_id do
          nil ->
            {[{"Any Card", quantity, "common"}], nil}
          card_id ->
            case Sammelkarten.Cards.get_card(card_id) do
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

  defp format_time(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
    |> String.replace("T", " ")
    |> String.replace("Z", " UTC")
  end
end
