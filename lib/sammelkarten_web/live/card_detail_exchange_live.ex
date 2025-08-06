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
    {:noreply, push_navigate(socket, to: "/")}
  end

  # Generate combined trader data for both offers and searches
  defp generate_combined_trader_data(card) do
    base_seed = :erlang.phash2({card.id, "combined"})
    :rand.seed(:exsss, {base_seed, base_seed + 1, base_seed + 2})

    offer_count = calculate_offer_quantity(card)
    search_count = calculate_search_quantity(card)
    trader_data = generate_base_trader_data(card)

    offer_traders = build_offer_traders(trader_data, offer_count)
    search_traders = build_search_traders(trader_data, search_count)

    {offer_traders, search_traders}
  end

  # Generate base trader data with quantities and timestamps
  defp generate_base_trader_data(card) do
    all_traders = Enum.shuffle(@pseudonym_names)
    
    Enum.map(all_traders, fn name ->
      trader_seed = :erlang.phash2({card.id, name})
      :rand.seed(:exsss, {trader_seed, trader_seed + 1, trader_seed + 2})
      
      %{
        trader: name,
        offer_quantity: 1 + :rand.uniform(9),  # 1-10
        search_quantity: 1 + :rand.uniform(9), # 1-10
        offer_minutes_ago: :rand.uniform(180), # 0-180 minutes
        search_minutes_ago: :rand.uniform(240) # 0-240 minutes
      }
    end)
  end

  # Build offer traders list
  defp build_offer_traders(trader_data, offer_count) do
    trader_data
    |> Enum.take(offer_count)
    |> Enum.map(&format_offer_trader/1)
    |> Enum.sort_by(& &1.offer_quantity, :desc)
  end

  # Build search traders list
  defp build_search_traders(trader_data, search_count) do
    trader_data
    |> Enum.drop(1) # Start from index 1 to get different traders
    |> Enum.take(search_count)
    |> Enum.map(&format_search_trader/1)
    |> Enum.sort_by(& &1.search_quantity, :desc)
  end

  # Format trader for offers section
  defp format_offer_trader(trader) do
    %{
      trader: trader.trader,
      offer_quantity: trader.offer_quantity,
      search_quantity: trader.search_quantity,
      minutes_ago: trader.offer_minutes_ago
    }
  end

  # Format trader for searches section
  defp format_search_trader(trader) do
    %{
      trader: trader.trader,
      offer_quantity: trader.offer_quantity,
      search_quantity: trader.search_quantity,
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
                    <div class="space-y-3">
                      <%= for offer <- @offer_traders do %>
                        <div class="flex items-center justify-between p-3 bg-green-50 dark:bg-green-900/20 rounded-lg border border-green-200 dark:border-green-800">
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
                          <div class="text-right">
                            <p class="font-semibold text-green-600 dark:text-green-400 text-xl">
                              🔍 {offer.offer_quantity} → {offer.search_quantity}
                            </p>
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
                    <div class="space-y-3">
                      <%= for search <- @search_traders do %>
                        <div class="flex items-center justify-between p-3 bg-blue-50 dark:bg-blue-900/20 rounded-lg border border-blue-200 dark:border-blue-800">
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
                          <div class="text-right">
                            <p class="font-semibold text-blue-600 dark:text-blue-400 text-xl">
                              🔍 {search.offer_quantity} → {search.search_quantity}
                            </p>
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
