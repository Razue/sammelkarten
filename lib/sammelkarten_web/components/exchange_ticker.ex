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

  # Helper functions - replicated from DashboardExchangeLive for component independence

  # Generate offer quantity - number of people offering this card (0-21)
  defp calculate_offer_quantity(card) do
    # Use card price and rarity to influence base probability
    base_seed = :erlang.phash2({card.id, "offer"})
    :rand.seed(:exsss, {base_seed, base_seed + 1, base_seed + 2})

    # Higher price cards tend to have fewer offers
    # Normalize around 50 euros
    price_factor = min(card.current_price / 5000, 2.0)

    rarity_factor =
      case String.downcase(card.rarity) do
        # More common = more offers
        "common" -> 1.5
        "uncommon" -> 1.2
        "rare" -> 1.0
        "epic" -> 0.7
        # Rare cards = fewer offers
        "legendary" -> 0.4
        "mythic" -> 0.2
        _ -> 1.0
      end

    # Calculate base quantity (0-21)
    base_quantity = trunc(1.0 / price_factor * rarity_factor * 3)
    # +/- 3 variation
    variation = :rand.uniform(8) - 4
    max(0, min(3, base_quantity + variation))
  end

  # Generate search quantity - number of people searching for this card (0-21)
  defp calculate_search_quantity(card) do
    # Use card price and rarity to influence base probability
    base_seed = :erlang.phash2({card.id, "search"})
    :rand.seed(:exsss, {base_seed, base_seed + 10, base_seed + 20})

    # Higher price cards tend to have more searches (people want them)
    # Normalize around 50 euros
    price_factor = min(card.current_price / 5000, 2.0)

    rarity_factor =
      case String.downcase(card.rarity) do
        # Common cards less in demand
        "common" -> 0.3
        "uncommon" -> 0.6
        "rare" -> 1.0
        "epic" -> 1.4
        # Rare cards more in demand
        "legendary" -> 1.8
        "mythic" -> 2.1
        _ -> 1.0
      end

    # Calculate base quantity (0-21)
    # Scale to ~21 max
    base_quantity = trunc(price_factor * rarity_factor * 3.5)
    # +/- 2 variation
    variation = :rand.uniform(6) - 3
    max(0, min(21, base_quantity + variation))
  end

  defp format_time(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
    |> String.replace("T", " ")
    |> String.replace("Z", " UTC")
  end
end
