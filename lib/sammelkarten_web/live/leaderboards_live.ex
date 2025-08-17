defmodule SammelkartenWeb.LeaderboardsLive do
  @moduledoc """
  LiveView for displaying top traders and collections leaderboards.
  """

  use SammelkartenWeb, :live_view
  alias Sammelkarten.{Leaderboards, Formatter}

  @impl true
  def mount(_params, session, socket) do
    user = get_session_user(session)
    
    socket = 
      socket
      |> assign(:user, user)
      |> assign(:loading, true)
      |> assign(:period, 30)  # Default to 30 days
      |> assign(:leaderboards, nil)
      |> assign(:user_rankings, nil)
      |> assign(:error, nil)
      |> assign(:active_tab, "traders")

    # Load leaderboards data asynchronously
    send(self(), :load_leaderboards)
    
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
    
    send(self(), :load_leaderboards)
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("refresh_leaderboards", _params, socket) do
    socket = 
      socket
      |> assign(:loading, true)
      |> assign(:error, nil)
    
    send(self(), :load_leaderboards)
    
    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_leaderboards, socket) do
    period = socket.assigns.period
    user = socket.assigns.user
    
    # Load leaderboards data
    with {:ok, leaderboards} <- Leaderboards.get_all_leaderboards(period) do
      
      # Load user rankings if user is authenticated
      user_rankings = if user do
        case Leaderboards.get_user_rankings(user.pubkey, period) do
          {:ok, rankings} -> rankings
          {:error, _} -> nil
        end
      else
        nil
      end
      
      socket = 
        socket
        |> assign(:loading, false)
        |> assign(:leaderboards, leaderboards)
        |> assign(:user_rankings, user_rankings)
        |> assign(:error, nil)
      
      {:noreply, socket}
    else
      {:error, reason} ->
        socket = 
          socket
          |> assign(:loading, false)
          |> assign(:error, "Failed to load leaderboards: #{inspect(reason)}")
        
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

  defp format_pubkey(pubkey) when is_binary(pubkey) do
    if String.length(pubkey) > 16 do
      String.slice(pubkey, 0, 8) <> "..." <> String.slice(pubkey, -8, 8)
    else
      pubkey
    end
  end

  defp format_pubkey(_), do: "Unknown"

  defp rank_badge(rank) when rank <= 3 do
    case rank do
      1 -> "🥇"
      2 -> "🥈"
      3 -> "🥉"
    end
  end

  defp rank_badge(_), do: ""

  defp rank_color(rank) when rank <= 3, do: "text-yellow-600 font-bold"
  defp rank_color(rank) when rank <= 10, do: "text-blue-600 font-semibold"
  defp rank_color(_), do: "text-gray-600"

  defp metric_color(value) when is_number(value) and value > 0, do: "text-green-600"
  defp metric_color(value) when is_number(value) and value < 0, do: "text-red-600"
  defp metric_color(_), do: "text-gray-600"

  defp tab_class(current_tab, tab_name) do
    base_class = "px-4 py-2 text-sm font-medium rounded-lg transition-colors"
    
    if current_tab == tab_name do
      base_class <> " bg-blue-600 text-white"
    else
      base_class <> " text-gray-600 hover:text-gray-900 hover:bg-gray-100"
    end
  end

  # defp get_user_rank(user_rankings, category, subcategory) when is_map(user_rankings) do
  #   case get_in(user_rankings, [category, subcategory]) do
  #     %{rank: rank} -> rank
  #     _ -> nil
  #   end
  # end

  # defp get_user_rank(_, _, _), do: nil

  # defp render_leaderboard_entry(entry, _index) do
  #   %{
  #     rank: entry.rank,
  #     user_pubkey: entry.user_pubkey,
  #     value: entry.value,
  #     display_rank: "#{rank_badge(entry.rank)} ##{entry.rank}",
  #     formatted_pubkey: format_pubkey(entry.user_pubkey)
  #   }
  # end

  defp capitalize_atom(atom) when is_atom(atom) do
    atom |> Atom.to_string() |> String.capitalize()
  end

  defp capitalize_atom(value), do: value
end