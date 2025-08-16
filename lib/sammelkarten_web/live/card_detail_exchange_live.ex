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

  alias Sammelkarten.Cards

  @pseudonym_names [
    "Seedorchris",
    "Fab",
    "Altan",
    "Sticker21M",
    "Markus_Turm",
    "Maulwurf",
    "BitcoinBär",
    "SatsStacker",
    "PlsbtcOnTwitter",
    "DerHodler",
    "LightningJoe",
    "CryptoKai",
    "NoKYC",
    "WhyNotBitcoin",
    "BitBoxer",
    "ColdCardUser",
    "NodeRunner42",
    "OrangePixel",
    "StackingSats",
    "BitcoinBeliever",
    "LedgerLegend",
    "WalletWise",
    "HashPower",
    "SeedPhrase",
    "PrivateKey"
  ]

  @impl true
  def mount(%{"slug" => card_slug}, _session, socket) do
    case Cards.get_card_by_slug(card_slug) do
      {:ok, card} ->
        if connected?(socket) do
          # Subscribe to price updates for this specific card using the card ID
          Phoenix.PubSub.subscribe(Sammelkarten.PubSub, "card_prices:#{card.id}")
        end

        mount_with_card(card, socket)

      {:error, :not_found} ->
        mount_with_error("Card not found", socket)

      {:error, reason} ->
        mount_with_error("Failed to load card: #{inspect(reason)}", socket)
    end
  end

  defp mount_with_card(card, socket) do
    # Generate combined trader data for this card
    {offer_traders, search_traders} = generate_combined_trader_data(card)

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
      # Regenerate combined trader data
      {offer_traders, search_traders} = generate_combined_trader_data(updated_card)

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
  def handle_event("go_back", _params, socket) do
    {:noreply, push_navigate(socket, to: "/trading/exchanges")}
  end

  # Generate combined trader data for both offers and searches
  defp generate_combined_trader_data(card) do
    base_seed = :erlang.phash2({card.id, "combined"})
    :rand.seed(:exsss, {base_seed, base_seed + 1, base_seed + 2})

    offer_count = calculate_offer_quantity(card)
    search_count = calculate_search_quantity(card)
    trader_data = generate_base_trader_data(card)

    offer_traders = build_offer_traders(trader_data, offer_count, card)
    search_traders = build_search_traders(trader_data, search_count, card)

    {offer_traders, search_traders}
  end

  # Generate base trader data with exchange bundles and timestamps
  defp generate_base_trader_data(card) do
    all_traders = Enum.shuffle(@pseudonym_names)

    Enum.map(all_traders, fn name ->
      trader_seed = :erlang.phash2({card.id, name})
      :rand.seed(:exsss, {trader_seed, trader_seed + 1, trader_seed + 2})

      # Generate realistic exchange bundles
      offer_bundle = generate_offer_bundle(card, trader_seed)
      search_bundle = generate_search_bundle(card, trader_seed + 100)

      %{
        trader: name,
        offer_bundle: offer_bundle,
        search_bundle: search_bundle,
        # 0-180 minutes
        offer_minutes_ago: :rand.uniform(180),
        # 0-240 minutes
        search_minutes_ago: :rand.uniform(240)
      }
    end)
  end

  # Build offer traders list
  defp build_offer_traders(trader_data, offer_count, _card) do
    trader_data
    |> Enum.take(offer_count)
    |> Enum.map(&format_offer_trader/1)
    |> Enum.sort_by(&calculate_bundle_value(&1.offer_bundle), :desc)
  end

  # Build search traders list
  defp build_search_traders(trader_data, search_count, _card) do
    trader_data
    # Start from index 1 to get different traders
    |> Enum.drop(1)
    |> Enum.take(search_count)
    |> Enum.map(&format_search_trader/1)
    |> Enum.sort_by(&calculate_bundle_value(&1.search_bundle), :desc)
  end

  # Format trader for offers section
  defp format_offer_trader(trader) do
    %{
      trader: trader.trader,
      offer_bundle: trader.offer_bundle,
      search_bundle: trader.search_bundle,
      minutes_ago: trader.offer_minutes_ago
    }
  end

  # Format trader for searches section
  defp format_search_trader(trader) do
    %{
      trader: trader.trader,
      offer_bundle: trader.offer_bundle,
      search_bundle: trader.search_bundle,
      minutes_ago: trader.search_minutes_ago
    }
  end

  # Generate offer quantity - same logic as exchange dashboard
  defp calculate_offer_quantity(card) do
    base_seed = :erlang.phash2({card.id, "offer"})
    :rand.seed(:exsss, {base_seed, base_seed + 1, base_seed + 2})

    price_factor = min(card.current_price / 5000, 2.0)

    rarity_factor =
      case String.downcase(card.rarity) do
        "common" -> 1.5
        "uncommon" -> 1.2
        "rare" -> 1.0
        "epic" -> 0.7
        "legendary" -> 0.4
        "mythic" -> 0.2
        _ -> 1.0
      end

    base_quantity = trunc(1.0 / price_factor * rarity_factor * 3)
    variation = :rand.uniform(8) - 4
    # Max 8 for detail view
    max(0, min(8, base_quantity + variation))
  end

  # Generate search quantity - same logic as exchange dashboard
  defp calculate_search_quantity(card) do
    base_seed = :erlang.phash2({card.id, "search"})
    :rand.seed(:exsss, {base_seed + 10, base_seed + 20, base_seed + 30})

    price_factor = min(card.current_price / 5000, 2.0)

    rarity_factor =
      case String.downcase(card.rarity) do
        "common" -> 0.3
        "uncommon" -> 0.6
        "rare" -> 1.0
        "epic" -> 1.4
        "legendary" -> 1.8
        "mythic" -> 2.1
        _ -> 1.0
      end

    base_quantity = trunc(price_factor * rarity_factor * 3.5)
    variation = :rand.uniform(6) - 3
    # Max 12 for detail view
    max(0, min(12, base_quantity + variation))
  end

  # Generate realistic offer bundle - what trader is offering
  defp generate_offer_bundle(current_card, seed) do
    :rand.seed(:exsss, {seed, seed + 1, seed + 2})
    
    # 70% chance of offering multiple cards, 30% single card
    if :rand.uniform(100) <= 70 do
      generate_multi_card_bundle(current_card, :offer, seed)
    else
      generate_single_card_bundle(current_card, :offer, seed)
    end
  end

  # Generate realistic search bundle - what trader wants in return
  defp generate_search_bundle(current_card, seed) do
    :rand.seed(:exsss, {seed, seed + 1, seed + 2})
    
    # 60% chance of wanting multiple cards, 40% single card
    if :rand.uniform(100) <= 60 do
      generate_multi_card_bundle(current_card, :search, seed)
    else
      generate_single_card_bundle(current_card, :search, seed)
    end
  end

  # Generate single card bundle
  defp generate_single_card_bundle(current_card, type, seed) do
    :rand.seed(:exsss, {seed, seed + 10, seed + 20})
    
    quantity = case type do
      :offer -> 1 + :rand.uniform(3)  # 1-4 of current card
      :search -> 1 + :rand.uniform(2) # 1-3 of current card
    end
    
    [{current_card.name, quantity, current_card.rarity}]
  end

  # Generate multi-card bundle with variety
  defp generate_multi_card_bundle(current_card, _type, seed) do
    :rand.seed(:exsss, {seed, seed + 30, seed + 40})
    
    # Available card pool (realistic card names from the project)
    card_pool = [
      {"Satoshi", "mythic"}, {"Bitcoin Hotel", "legendary"}, {"Christian Decker", "legendary"},
      {"Der Gigi", "legendary"}, {"Jonas Nick", "epic"}, {"Blocktrainer", "epic"},
      {"Markus Turm", "epic"}, {"Zitadelle", "epic"}, {"Seed or Chris", "rare"},
      {"BitcoinHotel Holo", "rare"}, {"Der Pleb", "uncommon"}, {"Pleb Rap", "uncommon"},
      {"FAB", "uncommon"}, {"Dennis", "uncommon"}, {"Maurice Effekt", "common"},
      {"Paddepadde", "common"}, {"Netdiver", "common"}, {"Toxic Booster", "common"}
    ]
    
    # Include the current card
    bundle = [{current_card.name, 1 + :rand.uniform(2), current_card.rarity}]
    
    # Add 1-3 other cards
    num_other_cards = 1 + :rand.uniform(2)
    other_cards = card_pool 
                  |> Enum.filter(fn {name, _} -> name != current_card.name end)
                  |> Enum.shuffle()
                  |> Enum.take(num_other_cards)
                  |> Enum.map(fn {name, rarity} -> {name, 1 + :rand.uniform(2), rarity} end)
    
    bundle ++ other_cards
  end

  # Calculate total value of a bundle for sorting
  defp calculate_bundle_value(bundle) do
    bundle
    |> Enum.map(fn {_name, quantity, rarity} ->
      rarity_value = case String.downcase(rarity) do
        "mythic" -> 100
        "legendary" -> 80
        "epic" -> 60
        "rare" -> 40
        "uncommon" -> 20
        "common" -> 10
        _ -> 10
      end
      quantity * rarity_value
    end)
    |> Enum.sum()
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
                    <.link navigate="/trading/exchanges" class="hover:text-gray-700 dark:hover:text-gray-300">
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
                                <p class="font-medium text-gray-900 dark:text-white">{offer.trader}</p>
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
                          <div class="flex items-center space-x-4">
                            <!-- What they're offering -->
                            <div class="flex-1">
                              <p class="text-xs font-medium text-gray-600 dark:text-gray-400 mb-2 uppercase tracking-wide">Offering</p>
                              <div class="space-y-1">
                                <%= for {card_name, quantity, rarity} <- offer.offer_bundle do %>
                                  <div class="flex items-center justify-between p-2 bg-white dark:bg-gray-800 rounded border">
                                    <div class="flex items-center space-x-2">
                                      <span class={["w-2 h-2 rounded-full", rarity_dot_color(rarity)]}></span>
                                      <span class="text-sm font-medium text-gray-900 dark:text-white">{card_name}</span>
                                    </div>
                                    <span class="text-sm font-bold text-green-600 dark:text-green-400">×{quantity}</span>
                                  </div>
                                <% end %>
                              </div>
                            </div>
                            
                            <!-- Exchange Arrow -->
                            <div class="flex flex-col items-center justify-center px-2">
                              <svg class="w-8 h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7l5 5m0 0l-5 5m5-5H6"></path>
                              </svg>
                              <span class="text-xs text-gray-500 mt-1">FOR</span>
                            </div>
                            
                            <!-- What they want -->
                            <div class="flex-1">
                              <p class="text-xs font-medium text-gray-600 dark:text-gray-400 mb-2 uppercase tracking-wide">Wants</p>
                              <div class="space-y-1">
                                <%= for {card_name, quantity, rarity} <- offer.search_bundle do %>
                                  <div class="flex items-center justify-between p-2 bg-white dark:bg-gray-800 rounded border">
                                    <div class="flex items-center space-x-2">
                                      <span class={["w-2 h-2 rounded-full", rarity_dot_color(rarity)]}></span>
                                      <span class="text-sm font-medium text-gray-900 dark:text-white">{card_name}</span>
                                    </div>
                                    <span class="text-sm font-bold text-blue-600 dark:text-blue-400">×{quantity}</span>
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
                                <p class="font-medium text-gray-900 dark:text-white">{search.trader}</p>
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
                          <div class="flex items-center space-x-4">
                            <!-- What they want -->
                            <div class="flex-1">
                              <p class="text-xs font-medium text-gray-600 dark:text-gray-400 mb-2 uppercase tracking-wide">Looking For</p>
                              <div class="space-y-1">
                                <%= for {card_name, quantity, rarity} <- search.search_bundle do %>
                                  <div class="flex items-center justify-between p-2 bg-white dark:bg-gray-800 rounded border">
                                    <div class="flex items-center space-x-2">
                                      <span class={["w-2 h-2 rounded-full", rarity_dot_color(rarity)]}></span>
                                      <span class="text-sm font-medium text-gray-900 dark:text-white">{card_name}</span>
                                    </div>
                                    <span class="text-sm font-bold text-blue-600 dark:text-blue-400">×{quantity}</span>
                                  </div>
                                <% end %>
                              </div>
                            </div>
                            
                            <!-- Exchange Arrow -->
                            <div class="flex flex-col items-center justify-center px-2">
                              <svg class="w-8 h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16l-4-4m0 0l4-4m-4 4h18"></path>
                              </svg>
                              <span class="text-xs text-gray-500 mt-1">FOR</span>
                            </div>
                            
                            <!-- What they're offering -->
                            <div class="flex-1">
                              <p class="text-xs font-medium text-gray-600 dark:text-gray-400 mb-2 uppercase tracking-wide">Offering</p>
                              <div class="space-y-1">
                                <%= for {card_name, quantity, rarity} <- search.offer_bundle do %>
                                  <div class="flex items-center justify-between p-2 bg-white dark:bg-gray-800 rounded border">
                                    <div class="flex items-center space-x-2">
                                      <span class={["w-2 h-2 rounded-full", rarity_dot_color(rarity)]}></span>
                                      <span class="text-sm font-medium text-gray-900 dark:text-white">{card_name}</span>
                                    </div>
                                    <span class="text-sm font-bold text-green-600 dark:text-green-400">×{quantity}</span>
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

  defp format_price(price_in_sats) when is_integer(price_in_sats) do
    Sammelkarten.Formatter.format_german_price(price_in_sats)
  end

  defp format_price(price) when is_float(price) do
    price_sats = trunc(price)
    Sammelkarten.Formatter.format_german_price(price_sats)
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
