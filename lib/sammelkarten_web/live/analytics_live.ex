defmodule SammelkartenWeb.AnalyticsLive do
  @moduledoc """
  LiveView for displaying user trading performance and portfolio analytics.
  """

  use SammelkartenWeb, :live_view
  alias Sammelkarten.{Analytics, Formatter}

  @impl true
  def mount(_params, session, socket) do
    user = get_session_user(session)
    
    if user do
      # Load initial analytics data
      socket = 
        socket
        |> assign(:user, user)
        |> assign(:loading, true)
        |> assign(:period, 30)  # Default to 30 days
        |> assign(:performance, nil)
        |> assign(:growth_analysis, nil)
        |> assign(:comparative, nil)
        |> assign(:insights, nil)
        |> assign(:error, nil)

      # Load analytics data asynchronously
      send(self(), :load_analytics)
      
      {:ok, socket}
    else
      {:ok, redirect(socket, to: "/auth")}
    end
  end

  @impl true
  def handle_event("change_period", %{"period" => period_str}, socket) do
    period = String.to_integer(period_str)
    
    socket = 
      socket
      |> assign(:period, period)
      |> assign(:loading, true)
      |> assign(:error, nil)
    
    send(self(), :load_analytics)
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh_analytics", _params, socket) do
    socket = 
      socket
      |> assign(:loading, true)
      |> assign(:error, nil)
    
    send(self(), :load_analytics)
    
    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_analytics, socket) do
    user = socket.assigns.user
    period = socket.assigns.period
    
    # Load all analytics data
    with {:ok, performance} <- Analytics.get_user_performance(user.pubkey, period),
         {:ok, growth_analysis} <- Analytics.get_portfolio_growth_analysis(user.pubkey, period),
         {:ok, comparative} <- Analytics.get_comparative_performance(user.pubkey, period),
         {:ok, insights} <- Analytics.get_trading_insights(user.pubkey, min(period * 2, 90)) do
      
      socket = 
        socket
        |> assign(:loading, false)
        |> assign(:performance, performance)
        |> assign(:growth_analysis, growth_analysis)
        |> assign(:comparative, comparative)
        |> assign(:insights, insights)
        |> assign(:error, nil)
      
      {:noreply, socket}
    else
      {:error, reason} ->
        socket = 
          socket
          |> assign(:loading, false)
          |> assign(:error, "Failed to load analytics: #{inspect(reason)}")
        
        {:noreply, socket}
    end
  end

  # Helper functions

  defp get_session_user(session) do
    case Map.get(session, "nostr_user") do
      nil -> nil
      user_data when is_map(user_data) -> user_data
      _ -> nil
    end
  end

  defp format_percentage(value) when is_number(value) do
    Formatter.format_german_percentage(value * 100)
  end

  defp format_percentage(_), do: "0,00%"

  defp format_currency(value) when is_number(value) do
    Formatter.format_german_price(trunc(value))
  end

  defp format_currency(_), do: "€0,00"

  defp format_number(value) when is_number(value) do
    Formatter.format_german_number(to_string(value))
  end

  defp format_number(_), do: "0"

  defp performance_color(value) when is_number(value) and value > 0, do: "text-green-600"
  defp performance_color(value) when is_number(value) and value < 0, do: "text-red-600"
  defp performance_color(_), do: "text-gray-600"

  defp score_color(score) when is_number(score) do
    cond do
      score >= 80 -> "text-green-600"
      score >= 60 -> "text-yellow-600"
      score >= 40 -> "text-orange-600"
      true -> "text-red-600"
    end
  end

  defp score_color(_), do: "text-gray-600"

  defp risk_level_color(level) do
    case level do
      :low -> "text-green-600"
      :moderate -> "text-yellow-600"
      :high -> "text-orange-600"
      :very_high -> "text-red-600"
      _ -> "text-gray-600"
    end
  end

  defp capitalize_atom(atom) when is_atom(atom) do
    atom |> Atom.to_string() |> String.capitalize()
  end

  defp capitalize_atom(value), do: value
end