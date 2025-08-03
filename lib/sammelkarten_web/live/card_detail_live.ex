defmodule SammelkartenWeb.CardDetailLive do
  @moduledoc """
  LiveView for individual card detail pages.

  Shows comprehensive card information including:
  - Card details and metadata
  - Current price and price changes
  - Price history chart
  - Card image gallery
  """

  use SammelkartenWeb, :live_view

  alias Sammelkarten.Cards

  @impl true
  def mount(%{"id" => card_id}, _session, socket) do
    if connected?(socket) do
      # Subscribe to price updates for this specific card
      Phoenix.PubSub.subscribe(Sammelkarten.PubSub, "card_prices:#{card_id}")
    end

    case Cards.get_card(card_id) do
      {:ok, card} ->
        # Get price history for the card
        {:ok, price_history} = Cards.get_price_history(card_id, 30)

        socket =
          socket
          |> assign(:card, card)
          |> assign(:price_history, price_history)
          |> assign(:loading, false)
          |> assign(:error, nil)

        {:ok, socket}

      {:error, :not_found} ->
        socket =
          socket
          |> assign(:card, nil)
          |> assign(:price_history, [])
          |> assign(:loading, false)
          |> assign(:error, "Card not found")

        {:ok, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:card, nil)
          |> assign(:price_history, [])
          |> assign(:loading, false)
          |> assign(:error, "Failed to load card: #{inspect(reason)}")

        {:ok, socket}
    end
  end

  @impl true
  def handle_info({:price_updated, updated_card}, socket) do
    # Update the card if it matches the one we're displaying
    if socket.assigns.card && socket.assigns.card.id == updated_card.id do
      # Also refresh price history
      {:ok, price_history} = Cards.get_price_history(updated_card.id, 30)

      socket =
        socket
        |> assign(:card, updated_card)
        |> assign(:price_history, price_history)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("go_back", _params, socket) do
    {:noreply, push_navigate(socket, to: "/cards")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="min-h-screen bg-gray-50"
      id="card-detail-container"
      phx-hook="CardDetailKeyboardShortcuts"
    >
      <%= if @error do %>
        <div class="max-w-4xl mx-auto px-4 py-8">
          <div class="bg-red-50 border border-red-200 rounded-lg p-6 text-center">
            <h2 class="text-xl font-semibold text-red-800 mb-2">Error</h2>
            <p class="text-red-600">{@error}</p>
            <.link
              navigate="/cards"
              class="inline-block mt-4 text-blue-600 hover:text-blue-800 underline"
            >
              ← Back to Cards
            </.link>
          </div>
        </div>
      <% else %>
        <%= if @card do %>
          <!-- Breadcrumb Navigation -->
          <div class="bg-white border-b border-gray-200">
            <div class="max-w-6xl mx-auto px-4 py-3">
              <nav class="flex" aria-label="Breadcrumb">
                <ol class="flex items-center space-x-2 text-sm text-gray-500">
                  <li>
                    <.link navigate="/cards" class="hover:text-gray-700">
                      Cards
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
                    <span class="font-medium text-gray-900">{@card.name}</span>
                  </li>
                </ol>
              </nav>
            </div>
          </div>
          
    <!-- Main Content -->
          <div class="max-w-6xl mx-auto px-4 py-8">
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
              
    <!-- Left Column: Card Image and Basic Info -->
              <div class="space-y-6">
                <!-- Card Image -->
                <div class="bg-white rounded-lg shadow-sm p-6">
                  <div class="aspect-square bg-gray-100 rounded-lg overflow-hidden">
                    <img src={@card.image_path} alt={@card.name} class="w-full h-full object-cover" />
                  </div>
                </div>
                
    <!-- Card Metadata -->
                <div class="bg-white rounded-lg shadow-sm p-6">
                  <h3 class="text-lg font-semibold text-gray-900 mb-4">Card Details</h3>
                  <div class="space-y-3">
                    <div class="flex justify-between">
                      <span class="text-gray-600">Rarity</span>
                      <span class={[
                        "px-2 py-1 rounded-full text-xs font-medium",
                        rarity_color_class(@card.rarity)
                      ]}>
                        {String.upcase(@card.rarity)}
                      </span>
                    </div>
                    <div class="flex justify-between">
                      <span class="text-gray-600">Last Updated</span>
                      <span class="text-gray-900">
                        {format_datetime(@card.last_updated)}
                      </span>
                    </div>
                  </div>

                  <%= if @card.description && @card.description != "" do %>
                    <div class="mt-6 pt-6 border-t border-gray-200">
                      <h4 class="font-medium text-gray-900 mb-2">Description</h4>
                      <p class="text-gray-600 text-sm leading-relaxed">
                        {@card.description}
                      </p>
                    </div>
                  <% end %>
                </div>
              </div>
              
    <!-- Right Column: Price Info and Chart -->
              <div class="space-y-6">
                <!-- Price Information -->
                <div class="bg-white rounded-lg shadow-sm p-6">
                  <h1 class="text-2xl font-bold text-gray-900 mb-6">{@card.name}</h1>
                  
    <!-- Current Price -->
                  <div class="mb-6">
                    <div class="text-3xl font-bold text-gray-900 mb-2">
                      {format_price(@card.current_price)}
                    </div>
                    
    <!-- Price Change -->
                    <div class="flex items-center space-x-4">
                      <div class={[
                        "flex items-center text-sm font-medium",
                        price_change_color(@card.price_change_24h)
                      ]}>
                        <%= if @card.price_change_24h >= 0 do %>
                          <svg class="w-4 h-4 mr-1" fill="currentColor" viewBox="0 0 20 20">
                            <path
                              fill-rule="evenodd"
                              d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L10 6.414 6.707 9.707a1 1 0 01-1.414 0z"
                              clip-rule="evenodd"
                            />
                          </svg>
                        <% else %>
                          <svg class="w-4 h-4 mr-1" fill="currentColor" viewBox="0 0 20 20">
                            <path
                              fill-rule="evenodd"
                              d="M14.707 10.293a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 111.414-1.414L10 13.586l3.293-3.293a1 1 0 011.414 0z"
                              clip-rule="evenodd"
                            />
                          </svg>
                        <% end %>
                        {format_price_change(@card.price_change_24h)}
                      </div>

                      <div class={[
                        "text-sm font-medium",
                        price_change_color(@card.price_change_24h)
                      ]}>
                        ({format_percentage(@card.price_change_percentage)})
                      </div>
                    </div>
                  </div>
                </div>
                
    <!-- Price History Chart -->
                <div class="bg-white rounded-lg shadow-sm p-6">
                  <div class="flex justify-between items-center mb-4">
                    <h3 class="text-lg font-semibold text-gray-900">Price History</h3>
                    <div class="text-xs text-gray-500">
                      <div>📈 Scroll to zoom • Drag to pan • Double-click to reset</div>
                    </div>
                  </div>

                  <%= if length(@price_history) > 0 do %>
                    <div class="relative">
                      <canvas
                        id="price-chart"
                        phx-hook="PriceChart"
                        data-chart-data={prepare_chart_data(@price_history)}
                        class="w-full border border-gray-200 rounded"
                        style="height: 300px;"
                      >
                      </canvas>
                    </div>
                    
    <!-- Recent price data table -->
                    <div class="mt-6 pt-6 border-t border-gray-200">
                      <h4 class="text-sm font-medium text-gray-900 mb-3">Recent Price Changes</h4>
                      <div class="space-y-2 max-h-32 overflow-y-auto">
                        <%= for entry <- Enum.take(@price_history, 5) do %>
                          <div class="flex justify-between items-center py-1 text-sm">
                            <span class="text-gray-600">
                              {format_datetime(entry.timestamp)}
                            </span>
                            <span class="font-medium text-gray-900">
                              {format_price(entry.price)}
                            </span>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% else %>
                    <div class="text-center py-8 text-gray-500">
                      <svg
                        class="mx-auto h-12 w-12 text-gray-400 mb-4"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
                        />
                      </svg>
                      <p>No price history available yet.</p>
                      <p class="text-xs mt-1">Charts will appear once price updates begin.</p>
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

  defp format_price(price_in_cents) when is_integer(price_in_cents) do
    Sammelkarten.Formatter.format_german_price(price_in_cents)
  end

  defp format_price(price) when is_float(price) do
    price_cents = trunc(price * 100)
    Sammelkarten.Formatter.format_german_price(price_cents)
  end

  defp format_price_change(change_in_cents) when is_integer(change_in_cents) do
    sign = if change_in_cents >= 0, do: "+", else: ""
    formatted_amount = Sammelkarten.Formatter.format_german_price(abs(change_in_cents)) |> String.replace("€", "")
    "#{sign}€#{formatted_amount}"
  end

  defp format_price_change(change) when is_float(change) do
    sign = if change >= 0, do: "+", else: ""
    change_cents = trunc(abs(change) * 100)
    formatted_amount = Sammelkarten.Formatter.format_german_price(change_cents) |> String.replace("€", "")
    "#{sign}€#{formatted_amount}"
  end

  defp format_percentage(percentage) when is_float(percentage) do
    Sammelkarten.Formatter.format_german_percentage(percentage)
  end

  defp price_change_color(change) when change > 0, do: "text-green-600"
  defp price_change_color(change) when change < 0, do: "text-red-600"
  defp price_change_color(_), do: "text-gray-600"

  defp rarity_color_class("common"), do: "bg-gray-100 text-gray-800"
  defp rarity_color_class("uncommon"), do: "bg-green-100 text-green-800"
  defp rarity_color_class("rare"), do: "bg-blue-100 text-blue-800"
  defp rarity_color_class("epic"), do: "bg-purple-100 text-purple-800"
  defp rarity_color_class("legendary"), do: "bg-yellow-100 text-yellow-800"
  defp rarity_color_class(_), do: "bg-gray-100 text-gray-800"

  defp format_datetime(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
    |> String.replace("T", " ")
    |> String.replace("Z", " UTC")
  end

  defp prepare_chart_data(price_history) do
    chart_data =
      price_history
      |> Enum.map(fn entry ->
        %{
          price: entry.price,
          timestamp: DateTime.to_iso8601(entry.timestamp)
        }
      end)

    Jason.encode!(chart_data)
  end
end
