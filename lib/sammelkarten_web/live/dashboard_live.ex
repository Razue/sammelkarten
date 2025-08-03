defmodule SammelkartenWeb.DashboardLive do
  use SammelkartenWeb, :live_view

  alias Sammelkarten.Cards

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:cards, [])
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> assign(:search_term, "")
      |> assign(:sort_by, "name")
      |> assign(:sort_direction, "asc")
      |> assign(:connection_status, "connecting")

    if connected?(socket) do
      # Subscribe to price updates
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

  defp price_change_class(change) when is_integer(change) do
    cond do
      change > 0 -> "text-green-600"
      change < 0 -> "text-red-600"
      true -> "text-gray-600"
    end
  end

  defp price_change_class(change) when is_float(change) do
    cond do
      change > 0.0 -> "text-green-600"
      change < 0.0 -> "text-red-600"
      true -> "text-gray-600"
    end
  end

  defp price_change_class(change) do
    zero = Decimal.new(0)

    case Decimal.compare(change, zero) do
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
      "mythic" -> "bg-red-100 text-red-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end
end
