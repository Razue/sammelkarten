defmodule SammelkartenWeb.DashboardLive do
  use SammelkartenWeb, :live_view

  alias Sammelkarten.Cards

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to price updates
      Phoenix.PubSub.subscribe(Sammelkarten.PubSub, "price_updates")
    end

    {:ok, cards} = Cards.list_cards()

    socket = 
      socket
      |> assign(:cards, cards)
      |> assign(:loading, false)
      |> assign(:search_term, "")
      |> assign(:sort_by, "name")
      |> assign(:sort_direction, "asc")

    {:ok, socket}
  end

  @impl true
  def handle_info({:price_update_completed, %{updated_count: _count}}, socket) do
    # Refresh all cards when price updates complete
    {:ok, cards} = Cards.list_cards()
    
    # Apply current filtering and sorting
    filtered_cards = filter_cards(cards, socket.assigns.search_term)
    sorted_cards = sort_cards(filtered_cards, socket.assigns.sort_by, socket.assigns.sort_direction)
    
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
  def handle_event("search", %{"search" => %{"term" => term}}, socket) do
    {:ok, all_cards} = Cards.list_cards()
    filtered_cards = filter_cards(all_cards, term)
    {:noreply, assign(socket, cards: filtered_cards, search_term: term)}
  end

  @impl true
  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    current_sort = socket.assigns.sort_by
    direction = if current_sort == sort_by and socket.assigns.sort_direction == "asc", do: "desc", else: "asc"
    
    sorted_cards = sort_cards(socket.assigns.cards, sort_by, direction)
    
    {:noreply, assign(socket, cards: sorted_cards, sort_by: sort_by, sort_direction: direction)}
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
  defp sort_cards(cards, "price", "asc"), do: Enum.sort_by(cards, & &1.current_price)
  defp sort_cards(cards, "price", "desc"), do: Enum.sort_by(cards, & &1.current_price, :desc)
  defp sort_cards(cards, "change", "asc"), do: Enum.sort_by(cards, & &1.price_change_24h)
  defp sort_cards(cards, "change", "desc"), do: Enum.sort_by(cards, & &1.price_change_24h, :desc)

  defp format_price(price) when is_integer(price) do
    (price / 100)
    |> Decimal.from_float()
    |> Decimal.round(2)
    |> Decimal.to_string()
  end
  
  defp format_price(price) do
    price
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp format_percentage_change(change) when is_integer(change) do
    decimal_change = Decimal.from_float(change / 100)
    case Decimal.compare(decimal_change, 0) do
      :gt -> "+#{Decimal.round(decimal_change, 2)}%"
      :lt -> "#{Decimal.round(decimal_change, 2)}%"
      :eq -> "0.00%"
    end
  end
  
  defp format_percentage_change(change) do
    case Decimal.compare(change, 0) do
      :gt -> "+#{Decimal.round(change, 2)}%"
      :lt -> "#{Decimal.round(change, 2)}%"
      :eq -> "0.00%"
    end
  end

  defp price_change_class(change) when is_integer(change) do
    cond do
      change > 0 -> "text-green-600"
      change < 0 -> "text-red-600"
      true -> "text-gray-600"
    end
  end
  
  defp price_change_class(change) do
    case Decimal.compare(change, 0) do
      :gt -> "text-green-600"
      :lt -> "text-red-600"
      :eq -> "text-gray-600"
    end
  end

  defp rarity_color(rarity) do
    case String.downcase(rarity) do
      "common" -> "bg-gray-100 text-gray-800"
      "uncommon" -> "bg-green-100 text-green-800"
      "rare" -> "bg-blue-100 text-blue-800"
      "epic" -> "bg-purple-100 text-purple-800"
      "legendary" -> "bg-yellow-100 text-yellow-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end
end