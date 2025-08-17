defmodule SammelkartenWeb.MarketInsightsLive do
  @moduledoc """
  LiveView for displaying cross-user trading patterns and market insights.
  """

  use SammelkartenWeb, :live_view
  alias Sammelkarten.{MarketInsights, Formatter}

  @impl true
  def mount(_params, _session, socket) do
    socket = 
      socket
      |> assign(:loading, true)
      |> assign(:period, 30)  # Default to 30 days
      |> assign(:patterns, nil)
      |> assign(:trends, nil)
      |> assign(:network, nil)
      |> assign(:health, nil)
      |> assign(:error, nil)
      |> assign(:active_tab, "patterns")

    # Load market insights data asynchronously
    send(self(), :load_insights)
    
    {:ok, socket}
  end

  @impl true
  def handle_event("change_period", %{"period" => period_str}, socket) do
    period = String.to_integer(period_str)
    
    socket = 
      socket
      |> assign(:period, period)
      |> assign(:loading, true)
      |> assign(:error, nil)
    
    send(self(), :load_insights)
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("refresh_insights", _params, socket) do
    socket = 
      socket
      |> assign(:loading, true)
      |> assign(:error, nil)
    
    send(self(), :load_insights)
    
    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_insights, socket) do
    period = socket.assigns.period
    
    # Load all market insights data
    with {:ok, patterns} <- MarketInsights.get_market_patterns(period),
         {:ok, trends} <- MarketInsights.get_trending_analysis(min(period, 14)),
         {:ok, network} <- MarketInsights.get_trading_network_analysis(period),
         {:ok, health} <- MarketInsights.get_market_health_metrics(period) do
      
      socket = 
        socket
        |> assign(:loading, false)
        |> assign(:patterns, patterns)
        |> assign(:trends, trends)
        |> assign(:network, network)
        |> assign(:health, health)
        |> assign(:error, nil)
      
      {:noreply, socket}
    else
      {:error, reason} ->
        socket = 
          socket
          |> assign(:loading, false)
          |> assign(:error, "Failed to load market insights: #{inspect(reason)}")
        
        {:noreply, socket}
    end
  end

  # Helper functions

  defp format_currency(value) when is_number(value) do
    Formatter.format_german_price(trunc(value))
  end

  defp format_currency(_), do: "€0,00"

  defp format_number(value) when is_number(value) do
    Formatter.format_german_number(to_string(trunc(value)))
  end

  defp format_number(_), do: "0"

  defp format_percentage(value) when is_number(value) do
    Formatter.format_german_percentage(value * 100)
  end

  defp format_percentage(_), do: "0,00%"

  defp sentiment_color(:bullish), do: "text-green-600"
  defp sentiment_color(:bearish), do: "text-red-600"
  defp sentiment_color(:neutral), do: "text-gray-600"
  defp sentiment_color(_), do: "text-gray-600"

  defp trend_color(:up), do: "text-green-600"
  defp trend_color(:increasing), do: "text-green-600"
  defp trend_color(:upward), do: "text-green-600"
  defp trend_color(:down), do: "text-red-600"
  defp trend_color(:decreasing), do: "text-red-600"
  defp trend_color(:downward), do: "text-red-600"
  defp trend_color(:stable), do: "text-blue-600"
  defp trend_color(:neutral), do: "text-gray-600"
  defp trend_color(_), do: "text-gray-600"

  defp health_color(score) when is_number(score) do
    cond do
      score >= 80 -> "text-green-600"
      score >= 60 -> "text-yellow-600"
      score >= 40 -> "text-orange-600"
      true -> "text-red-600"
    end
  end

  defp health_color(_), do: "text-gray-600"

  defp tab_class(current_tab, tab_name) do
    base_class = "px-4 py-2 text-sm font-medium rounded-lg transition-colors"
    
    if current_tab == tab_name do
      base_class <> " bg-blue-600 text-white"
    else
      base_class <> " text-gray-600 hover:text-gray-900 hover:bg-gray-100"
    end
  end

  defp capitalize_atom(atom) when is_atom(atom) do
    atom |> Atom.to_string() |> String.capitalize()
  end

  defp capitalize_atom(value), do: value
end