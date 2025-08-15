defmodule Sammelkarten.Nostr.Client do
  @moduledoc """
  Nostr client for managing relay connections and event publishing/subscribing.

  This module handles:
  - WebSocket connections to multiple Nostr relays
  - Event publishing and subscription management
  - Connection health monitoring and automatic reconnection
  - Event filtering and processing
  """

  use GenServer
  require Logger

  # alias Sammelkarten.Nostr.Event

  @type relay_url :: String.t()
  @type subscription_id :: String.t()
  @type event_filter :: map()

  defstruct [
    :relays,
    :connections,
    :subscriptions,
    :event_handlers,
    :config
  ]

  # Client API

  @doc """
  Start the Nostr client with default configuration.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Publish an event to all connected relays.
  """
  def publish_event(event) do
    GenServer.call(__MODULE__, {:publish_event, event})
  end

  @doc """
  Subscribe to events matching the given filters.
  """
  def subscribe(subscription_id, filters, handler) when is_function(handler, 1) do
    GenServer.call(__MODULE__, {:subscribe, subscription_id, filters, handler})
  end

  @doc """
  Unsubscribe from a subscription.
  """
  def unsubscribe(subscription_id) do
    GenServer.call(__MODULE__, {:unsubscribe, subscription_id})
  end

  @doc """
  Get the current connection status for all relays.
  """
  def connection_status do
    GenServer.call(__MODULE__, :connection_status)
  end

  @doc """
  Manually reconnect to all relays.
  """
  def reconnect_all do
    GenServer.cast(__MODULE__, :reconnect_all)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    config = get_config()

    state = %__MODULE__{
      relays: config.relays,
      connections: %{},
      subscriptions: %{},
      event_handlers: %{},
      config: config
    }

    # Start connecting to relays asynchronously
    send(self(), :connect_relays)

    {:ok, state}
  end

  @impl true
  def handle_call({:publish_event, event}, _from, state) do
    # Publish event to all connected relays
    results =
      state.connections
      |> Enum.filter(fn {_url, conn} -> conn.status == :connected end)
      |> Enum.map(fn {url, conn} ->
        case send_to_relay(conn.pid, ["EVENT", event]) do
          :ok -> {url, :ok}
          error -> {url, error}
        end
      end)

    {:reply, results, state}
  end

  @impl true
  def handle_call({:subscribe, sub_id, filters, handler}, _from, state) do
    # Create subscription message
    subscription_msg = ["REQ", sub_id | filters]

    # Send to all connected relays
    results =
      state.connections
      |> Enum.filter(fn {_url, conn} -> conn.status == :connected end)
      |> Enum.map(fn {url, conn} ->
        case send_to_relay(conn.pid, subscription_msg) do
          :ok -> {url, :ok}
          error -> {url, error}
        end
      end)

    # Store subscription and handler
    new_state = %{
      state
      | subscriptions: Map.put(state.subscriptions, sub_id, filters),
        event_handlers: Map.put(state.event_handlers, sub_id, handler)
    }

    {:reply, results, new_state}
  end

  @impl true
  def handle_call({:unsubscribe, sub_id}, _from, state) do
    # Send CLOSE message to all connected relays
    close_msg = ["CLOSE", sub_id]

    results =
      state.connections
      |> Enum.filter(fn {_url, conn} -> conn.status == :connected end)
      |> Enum.map(fn {url, conn} ->
        case send_to_relay(conn.pid, close_msg) do
          :ok -> {url, :ok}
          error -> {url, error}
        end
      end)

    # Remove subscription and handler
    new_state = %{
      state
      | subscriptions: Map.delete(state.subscriptions, sub_id),
        event_handlers: Map.delete(state.event_handlers, sub_id)
    }

    {:reply, results, new_state}
  end

  @impl true
  def handle_call(:connection_status, _from, state) do
    status =
      state.connections
      |> Enum.map(fn {url, conn} -> {url, conn.status} end)
      |> Map.new()

    {:reply, status, state}
  end

  @impl true
  def handle_cast(:reconnect_all, state) do
    # Disconnect all and reconnect
    disconnect_all_relays(state)
    send(self(), :connect_relays)

    new_state = %{state | connections: %{}}
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:connect_relays, state) do
    Logger.info("Connecting to Nostr relays...")

    connections =
      state.relays
      |> Enum.map(&connect_to_relay/1)
      |> Enum.filter(fn {_url, conn} -> conn.status != :error end)
      |> Map.new()

    new_state = %{state | connections: connections}

    # Resubscribe to existing subscriptions
    resubscribe_all(new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:relay_message, url, message}, state) do
    case decode_message(message) do
      ["EVENT", sub_id, event] ->
        handle_event(state, sub_id, event)

      ["EOSE", sub_id] ->
        Logger.debug("End of stored events for subscription: #{sub_id}")

      ["OK", event_id, success, message] ->
        handle_event_response(event_id, success, message)

      ["NOTICE", notice] ->
        Logger.info("Notice from relay #{url}: #{notice}")

      _ ->
        Logger.debug("Unknown message from relay #{url}: #{inspect(message)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:relay_disconnected, url}, state) do
    Logger.warning("Relay disconnected: #{url}")

    # Update connection status
    new_connections =
      case Map.get(state.connections, url) do
        nil -> state.connections
        conn -> Map.put(state.connections, url, %{conn | status: :disconnected})
      end

    # Schedule reconnection
    Process.send_after(self(), {:reconnect_relay, url}, state.config.reconnect_interval)

    {:noreply, %{state | connections: new_connections}}
  end

  @impl true
  def handle_info({:reconnect_relay, url}, state) do
    case Map.get(state.connections, url) do
      %{attempt: attempt} when attempt < state.config.max_reconnect_attempts ->
        Logger.info("Attempting to reconnect to #{url} (attempt #{attempt + 1})")

        case connect_to_relay(url) do
          {^url, %{status: :connected} = new_conn} ->
            new_connections = Map.put(state.connections, url, new_conn)

            # Resubscribe to existing subscriptions
            resubscribe_to_relay(new_conn.pid, state.subscriptions)

            {:noreply, %{state | connections: new_connections}}

          {^url, %{status: :error}} ->
            new_conn = %{pid: nil, status: :disconnected, attempt: attempt + 1}
            new_connections = Map.put(state.connections, url, new_conn)

            # Schedule another reconnection attempt
            Process.send_after(self(), {:reconnect_relay, url}, state.config.reconnect_interval)

            {:noreply, %{state | connections: new_connections}}
        end

      _ ->
        Logger.error("Max reconnection attempts reached for #{url}")
        {:noreply, state}
    end
  end

  # Private Helper Functions

  defp get_config do
    config = Application.get_env(:sammelkarten, :nostr)

    %{
      relays: Keyword.get(config, :relays, []),
      connection_timeout: Keyword.get(config, :connection_timeout, 10_000),
      reconnect_interval: Keyword.get(config, :reconnect_interval, 5_000),
      max_reconnect_attempts: Keyword.get(config, :max_reconnect_attempts, 10)
    }
  end

  defp connect_to_relay(url) do
    case :websocket_client.start_link(url, __MODULE__.RelayHandler, parent: self(), url: url) do
      {:ok, pid} ->
        Logger.info("Connected to Nostr relay: #{url}")
        {url, %{pid: pid, status: :connected, attempt: 0}}

      {:error, reason} ->
        Logger.error("Failed to connect to relay #{url}: #{inspect(reason)}")
        {url, %{pid: nil, status: :error, attempt: 1}}
    end
  end

  defp disconnect_all_relays(state) do
    Enum.each(state.connections, fn {_url, conn} ->
      if conn.pid && Process.alive?(conn.pid) do
        GenServer.stop(conn.pid)
      end
    end)
  end

  defp send_to_relay(pid, message) do
    json_message = Jason.encode!(message)
    :websocket_client.cast(pid, {:text, json_message})
  end

  defp decode_message(message) do
    case Jason.decode(message) do
      {:ok, decoded} -> decoded
      {:error, _} -> []
    end
  end

  defp handle_event(state, sub_id, event) do
    case Map.get(state.event_handlers, sub_id) do
      nil ->
        Logger.debug("No handler for subscription: #{sub_id}")

      handler ->
        try do
          handler.(event)
        rescue
          error ->
            Logger.error("Error in event handler for #{sub_id}: #{inspect(error)}")
        end
    end
  end

  defp handle_event_response(event_id, success, message) do
    if success do
      Logger.debug("Event #{event_id} published successfully")
    else
      Logger.warning("Event #{event_id} failed to publish: #{message}")
    end
  end

  defp resubscribe_all(state) do
    Enum.each(state.connections, fn {_url, conn} ->
      if conn.status == :connected do
        resubscribe_to_relay(conn.pid, state.subscriptions)
      end
    end)
  end

  defp resubscribe_to_relay(relay_pid, subscriptions) do
    Enum.each(subscriptions, fn {sub_id, filters} ->
      subscription_msg = ["REQ", sub_id | filters]
      send_to_relay(relay_pid, subscription_msg)
    end)
  end
end

defmodule Sammelkarten.Nostr.Client.RelayHandler do
  @moduledoc """
  WebSocket handler for Nostr relay connections.
  """

  @behaviour :websocket_client

  def init(parent: parent, url: url) do
    {:ok, %{parent: parent, url: url}}
  end

  def onconnect(_req, state) do
    {:ok, state}
  end

  def ondisconnect(_reason, state) do
    send(state.parent, {:relay_disconnected, state.url})
    {:ok, state}
  end

  def websocket_handle({:text, message}, _conn_state, state) do
    send(state.parent, {:relay_message, state.url, message})
    {:ok, state}
  end

  def websocket_handle(_frame, _conn_state, state) do
    {:ok, state}
  end

  def websocket_info(_info, _conn_state, state) do
    {:ok, state}
  end

  def websocket_terminate(_reason, _conn_state, state) do
    send(state.parent, {:relay_disconnected, state.url})
    :ok
  end
end
