defmodule SammelkartenWeb.MarketLive do
  use SammelkartenWeb, :live_view

  alias Sammelkarten.Cards
  # alias Sammelkarten.Nostr.User
  require Logger

  @impl true
  def mount(_params, session, socket) do
    # Check for Nostr authentication for potential future features
    _nostr_user =
      case get_nostr_user_from_session(session) do
        {:ok, user} -> user
        {:error, :not_authenticated} -> nil
      end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sammelkarten.PubSub, "price_updates")
    end

    socket =
      socket
      |> assign(:time_range, "24h")
      |> assign(:loading, true)
      |> assign(:market_stats, %{})
      |> assign(:top_gainers, [])
      |> assign(:top_losers, [])
      |> assign(:chart_data, [])

    {:ok, socket, temporary_assigns: [loading: false]}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, load_market_data(socket)}
  end

  @impl true
  def handle_event("change_time_range", %{"time_range" => time_range}, socket) do
    socket =
      socket
      |> assign(:time_range, time_range)
      |> assign(:loading, true)
      |> load_market_data()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:price_updated, _card_id}, socket) do
    {:noreply, load_market_data(socket)}
  end

  @impl true
  def handle_info({:price_update_completed, _stats}, socket) do
    {:noreply, load_market_data(socket)}
  end

  defp load_market_data(socket) do
    case Cards.list_cards() do
      {:ok, cards} ->
        market_stats = calculate_market_stats(cards)
        top_gainers = get_top_movers(cards, :gainers, 3)
        top_losers = get_top_movers(cards, :losers, 3)
        chart_data = get_market_chart_data(socket.assigns.time_range)

        socket
        |> assign(:market_stats, market_stats)
        |> assign(:top_gainers, top_gainers)
        |> assign(:top_losers, top_losers)
        |> assign(:chart_data, chart_data)
        |> assign(:loading, false)

      {:error, _reason} ->
        socket
        |> assign(:market_stats, %{})
        |> assign(:top_gainers, [])
        |> assign(:top_losers, [])
        |> assign(:chart_data, [])
        |> assign(:loading, false)
    end
  end

  defp calculate_market_stats(cards) do
    total_market_cap =
      cards
      |> Enum.map(& &1.current_price)
      |> Enum.sum()

    # Calculate 24h volume as a percentage of market cap
    volume_24h = Decimal.mult(total_market_cap, Decimal.new("0.1"))

    # Calculate market cap change based on average price change
    avg_change =
      cards
      |> Enum.map(& &1.price_change_percentage)
      |> Enum.sum()
      |> Kernel./(length(cards))

    %{
      market_cap: total_market_cap,
      market_cap_change: avg_change,
      volume_24h: volume_24h,
      # Volume typically more volatile
      volume_change: avg_change * 2,
      active_cards: length(cards)
    }
  end

  defp get_top_movers(cards, type, limit) do
    cards
    |> Enum.sort_by(
      & &1.price_change_percentage,
      case type do
        :gainers -> :desc
        :losers -> :asc
      end
    )
    |> Enum.take(limit)
  end

  defp get_market_chart_data(time_range) do
    # Get aggregated market data for the chart
    # This simulates market overview data points
    hours_back = get_hours_back_for_range(time_range)
    interval = get_interval_for_range(time_range)
    now = DateTime.utc_now()

    0..hours_back
    |> Enum.take_every(interval)
    |> Enum.map(&generate_market_data_point(&1, now))
    |> Enum.reverse()
  end

  defp get_hours_back_for_range(time_range) do
    case time_range do
      "24h" -> 24
      "7d" -> 24 * 7
      "30d" -> 24 * 30
      _ -> 24
    end
  end

  defp get_interval_for_range(time_range) do
    case time_range do
      # hourly
      "24h" -> 1
      # every 4 hours
      "7d" -> 4
      # daily
      "30d" -> 24
      _ -> 1
    end
  end

  defp generate_market_data_point(hours_ago, now) do
    timestamp = DateTime.add(now, -hours_ago * 3600, :second)
    value = calculate_simulated_market_value(hours_ago)

    %{
      timestamp: timestamp,
      value: trunc(value)
    }
  end

  defp calculate_simulated_market_value(hours_ago) do
    # Simulate market value over time with some volatility
    # 200,000 sats
    base_value = 200_000
    # ±5%
    volatility = :rand.uniform() * 0.1 - 0.05
    # slight upward trend
    trend = -hours_ago * 10

    base_value + base_value * volatility + trend
  end

  defp format_currency(amount) when is_integer(amount) do
    amount
    |> Decimal.new()
    |> format_currency()
  end

  defp format_currency(%Decimal{} = amount) do
    amount
    |> Decimal.round(2)
    |> Sammelkarten.Formatter.format_german_decimal()
    |> then(&"#{&1} sats")
  end

  defp format_percentage(percentage) when is_float(percentage) do
    sign = if percentage >= 0, do: "+", else: ""

    formatted_number =
      percentage
      |> :erlang.float_to_binary(decimals: 1)
      |> String.replace(".", ",")

    "#{sign}#{formatted_number}%"
  end

  defp percentage_color(percentage) when percentage >= 0, do: "text-green-600"
  defp percentage_color(_), do: "text-red-600"

  defp card_initials(name) do
    name
    |> String.split()
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  defp get_nostr_user_from_session(session) do
    case session do
      %{"nostr_authenticated" => true, "nostr_user" => user_data} when user_data != nil ->
        try do
          user = struct(Sammelkarten.Nostr.User, atomize_keys(user_data))
          {:ok, user}
        rescue
          e ->
            Logger.error("Failed to load user from session: #{inspect(e)}")
            {:error, :invalid_user_data}
        end

      _ ->
        {:error, :not_authenticated}
    end
  end

  defp atomize_keys(map) when is_map(map) do
    for {key, val} <- map, into: %{} do
      cond do
        is_binary(key) -> {String.to_existing_atom(key), val}
        is_atom(key) -> {key, val}
        true -> {key, val}
      end
    end
  end
end
