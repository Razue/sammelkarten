defmodule SammelkartenWeb.Components.PriceTicker do
  @moduledoc """
  Price ticker component that displays streaming price updates for all cards.
  
  This component shows a horizontally scrolling ticker with the latest price 
  changes, similar to financial news tickers. It receives card data from the 
  parent LiveView.
  """
  
  use SammelkartenWeb, :live_component
  
  @impl true
  def update(assigns, socket) do
    # Filter cards to show only those with price changes for more interesting ticker
    ticker_cards = 
      assigns.cards
      |> Enum.filter(fn card -> card.price_change_24h != 0 end)
      |> Enum.sort_by(fn card -> abs(card.price_change_24h) end, :desc)
      |> Enum.take(10) # Limit to 10 cards for performance
    
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
                  <div class="flex items-center space-x-2 text-sm">
                    <span class="font-medium text-blue-300"><%= card.name %></span>
                    <span class="font-bold">
                      €<%= format_price(card.current_price) %>
                    </span>
                    <span class={[
                      "flex items-center space-x-1 text-xs font-medium",
                      price_change_color(card.price_change_24h)
                    ]}>
                      <%= if card.price_change_24h >= 0 do %>
                        <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                          <path fill-rule="evenodd" d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L10 6.414 6.707 9.707a1 1 0 01-1.414 0z" clip-rule="evenodd" />
                        </svg>
                      <% else %>
                        <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                          <path fill-rule="evenodd" d="M14.707 10.293a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 111.414-1.414L10 13.586l3.293-3.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                        </svg>
                      <% end %>
                      <span><%= format_percentage_change(card.price_change_24h) %></span>
                    </span>
                  </div>
                <% end %>
              </div>
              
              <!-- Duplicate set for seamless scrolling -->
              <div class="flex space-x-8 px-4 py-2 whitespace-nowrap">
                <%= for card <- @cards do %>
                  <div class="flex items-center space-x-2 text-sm">
                    <span class="font-medium text-blue-300"><%= card.name %></span>
                    <span class="font-bold">
                      €<%= format_price(card.current_price) %>
                    </span>
                    <span class={[
                      "flex items-center space-x-1 text-xs font-medium",
                      price_change_color(card.price_change_24h)
                    ]}>
                      <%= if card.price_change_24h >= 0 do %>
                        <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                          <path fill-rule="evenodd" d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L10 6.414 6.707 9.707a1 1 0 01-1.414 0z" clip-rule="evenodd" />
                        </svg>
                      <% else %>
                        <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                          <path fill-rule="evenodd" d="M14.707 10.293a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 111.414-1.414L10 13.586l3.293-3.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                        </svg>
                      <% end %>
                      <span><%= format_percentage_change(card.price_change_24h) %></span>
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
            <span>💱 Waiting for price updates...</span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
  
  # Helper functions
  
  defp format_price(price_in_cents) when is_integer(price_in_cents) do
    :erlang.float_to_binary(price_in_cents / 100, decimals: 2)
  end
  
  defp format_price(price) when is_float(price) do
    :erlang.float_to_binary(price, decimals: 2)
  end
  
  defp format_percentage_change(change) when is_integer(change) do
    decimal_change = change / 100
    case decimal_change do
      change when change > 0 -> "+#{:erlang.float_to_binary(change, decimals: 2)}%"
      change when change < 0 -> "#{:erlang.float_to_binary(change, decimals: 2)}%"
      _ -> "0.00%"
    end
  end
  
  defp format_percentage_change(change) when is_float(change) do
    case change do
      change when change > 0 -> "+#{:erlang.float_to_binary(change, decimals: 2)}%"
      change when change < 0 -> "#{:erlang.float_to_binary(change, decimals: 2)}%"
      _ -> "0.00%"
    end
  end
  
  defp price_change_color(change) when change > 0, do: "text-green-400"
  defp price_change_color(change) when change < 0, do: "text-red-400"  
  defp price_change_color(_), do: "text-gray-400"
  
  defp format_time(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
    |> String.replace("T", " ")
    |> String.replace("Z", " UTC")
  end
end