defmodule SammelkartenWeb.MarketLive do
  use SammelkartenWeb, :live_view

  alias Sammelkarten.Cards

  @impl true
  def mount(_params, _session, socket) do
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
      volume_change: avg_change * 2, # Volume typically more volatile
      active_cards: length(cards)
    }
  end

  defp get_top_movers(cards, type, limit) do
    cards
    |> Enum.sort_by(& &1.price_change_percentage, 
        case type do
          :gainers -> :desc
          :losers -> :asc
        end)
    |> Enum.take(limit)
  end

  defp get_market_chart_data(time_range) do
    # Get aggregated market data for the chart
    # This simulates market overview data points
    hours_back = case time_range do
      "24h" -> 24
      "7d" -> 24 * 7
      "30d" -> 24 * 30
      _ -> 24
    end

    interval = case time_range do
      "24h" -> 1 # hourly
      "7d" -> 4 # every 4 hours  
      "30d" -> 24 # daily
      _ -> 1
    end

    now = DateTime.utc_now()
    
    0..hours_back
    |> Enum.take_every(interval)
    |> Enum.map(fn hours_ago ->
      timestamp = DateTime.add(now, -hours_ago * 3600, :second)
      
      # Simulate market value over time with some volatility
      base_value = 20_000_00 # €200,000 in cents
      volatility = :rand.uniform() * 0.1 - 0.05 # ±5%
      trend = -hours_ago * 10 # slight upward trend
      
      value = base_value + (base_value * volatility) + trend
      
      %{
        timestamp: timestamp,
        value: trunc(value)
      }
    end)
    |> Enum.reverse()
  end

  defp format_currency(amount) when is_integer(amount) do
    amount
    |> Decimal.new()
    |> Decimal.div(100)
    |> format_currency()
  end

  defp format_currency(%Decimal{} = amount) do
    amount
    |> Decimal.round(2)
    |> Decimal.to_string()
    |> then(&"€#{&1}")
  end

  defp format_percentage(percentage) when is_float(percentage) do
    sign = if percentage >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(percentage, decimals: 1)}%"
  end

  defp percentage_color(percentage) when percentage >= 0, do: "text-green-600"
  defp percentage_color(_), do: "text-red-600"

  defp card_initials(name) do
    name
    |> String.split()
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end
end