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

  def format_offer_quantity(card) do
    quantity = calculate_offer_quantity(card)
    "#{quantity}"
  end

  def format_search_quantity(card) do
    quantity = calculate_search_quantity(card)
    "#{quantity}"
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
