defmodule SammelkartenWeb.RelayAdminLive do
  @moduledoc """
  LiveView for Nostr relay administration and monitoring.

  Features:
  - Relay health monitoring and performance metrics
  - Add/remove relays dynamically
  - Relay discovery and management
  - Connection status monitoring
  """

  use SammelkartenWeb, :live_view

  alias Sammelkarten.Nostr.Client

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to relay status updates
      Phoenix.PubSub.subscribe(Sammelkarten.PubSub, "relay_status")
    end

    socket =
      socket
      |> assign(:page_title, "Relay Administration")
      |> load_relay_data()

    {:ok, socket}
  end

  @impl true
  def handle_event("discover_relays", _params, socket) do
    case Client.discover_relays() do
      {:ok, relays} ->
        socket =
          socket
          |> put_flash(:info, "Discovered #{length(relays)} new relays")
          |> assign(:discovered_relays, relays)
          |> load_relay_data()

        {:noreply, socket}

      {:cached, relays} ->
        socket =
          socket
          |> put_flash(:info, "Using cached discovery results (#{length(relays)} relays)")
          |> assign(:discovered_relays, relays)

        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Discovery failed: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_relay", %{"url" => url}, socket) do
    case Client.add_relay(url) do
      :ok ->
        socket =
          socket
          |> put_flash(:info, "Relay added successfully: #{url}")
          |> load_relay_data()

        {:noreply, socket}

      {:error, :already_exists} ->
        socket = put_flash(socket, :error, "Relay already exists: #{url}")
        {:noreply, socket}

      {:error, :connection_failed} ->
        socket = put_flash(socket, :error, "Failed to connect to relay: #{url}")
        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Error adding relay: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_relay", %{"url" => url}, socket) do
    case Client.remove_relay(url) do
      :ok ->
        socket =
          socket
          |> put_flash(:info, "Relay removed successfully: #{url}")
          |> load_relay_data()

        {:noreply, socket}

      {:error, :not_found} ->
        socket = put_flash(socket, :error, "Relay not found: #{url}")
        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Error removing relay: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reconnect_all", _params, socket) do
    Client.reconnect_all()

    socket =
      socket
      |> put_flash(:info, "Reconnecting to all relays...")
      |> load_relay_data()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:relay_status_update, _data}, socket) do
    # Reload relay data when status changes
    {:noreply, load_relay_data(socket)}
  end

  defp load_relay_data(socket) do
    connection_status = Client.connection_status()
    relay_health = Client.relay_health()

    socket
    |> assign(:connection_status, connection_status)
    |> assign(:relay_health, relay_health)
    |> assign(:discovered_relays, Map.get(socket.assigns, :discovered_relays, []))
  end

  defp format_uptime(connected_at) when is_integer(connected_at) do
    now = :os.system_time(:second)
    uptime_seconds = now - connected_at

    cond do
      uptime_seconds < 60 ->
        "#{uptime_seconds}s"

      uptime_seconds < 3600 ->
        "#{div(uptime_seconds, 60)}m"

      uptime_seconds < 86400 ->
        hours = div(uptime_seconds, 3600)
        minutes = div(rem(uptime_seconds, 3600), 60)
        "#{hours}h #{minutes}m"

      true ->
        days = div(uptime_seconds, 86400)
        hours = div(rem(uptime_seconds, 86400), 3600)
        "#{days}d #{hours}h"
    end
  end

  defp format_uptime(_), do: "Unknown"

  # defp status_color(:connected), do: "text-green-600"
  # defp status_color(:connecting), do: "text-yellow-600"
  # defp status_color(:disconnected), do: "text-red-600"
  # defp status_color(:error), do: "text-red-600"
  # defp status_color(_), do: "text-gray-600"

  defp status_badge(:connected), do: "bg-green-100 text-green-800"
  defp status_badge(:connecting), do: "bg-yellow-100 text-yellow-800"
  defp status_badge(:disconnected), do: "bg-red-100 text-red-800"
  defp status_badge(:error), do: "bg-red-100 text-red-800"
  defp status_badge(_), do: "bg-gray-100 text-gray-800"
end
