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
    :config,
    :relay_health,
    :discovery_cache
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
  Get relay health metrics and performance data.
  """
  def relay_health do
    GenServer.call(__MODULE__, :relay_health)
  end

  @doc """
  Discover additional Sammelkarten-focused relays.
  """
  def discover_relays do
    GenServer.call(__MODULE__, :discover_relays)
  end

  @doc """
  Add a new relay to the connection pool.
  """
  def add_relay(url) when is_binary(url) do
    GenServer.call(__MODULE__, {:add_relay, url})
  end

  @doc """
  Remove a relay from the connection pool.
  """
  def remove_relay(url) when is_binary(url) do
    GenServer.call(__MODULE__, {:remove_relay, url})
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
      config: config,
      relay_health: %{},
      discovery_cache: %{last_discovery: nil, relays: []}
    }

    # Start connecting to relays asynchronously
    send(self(), :connect_relays)

    {:ok, state}
  end

  @impl true
  def handle_call({:publish_event, event}, _from, state) do
    # Publish event to all connected relays with improved redundancy
    connected_relays = 
      state.connections
      |> Enum.filter(fn {_url, conn} -> conn.status == :connected end)
    
    if Enum.empty?(connected_relays) do
      {:reply, {:error, :no_connected_relays}, state}
    else
      {results, updated_state} =
        connected_relays
        |> Enum.map_reduce(state, fn {url, conn}, acc_state ->
          case send_to_relay(conn.pid, ["EVENT", event]) do
            :ok -> 
              # Update health metrics for successful send
              new_state = update_relay_health(acc_state, url, :event_sent)
              {{url, :ok}, new_state}
            _error -> 
              # Update health metrics for error
              new_state = update_relay_health(acc_state, url, :error)
              {{url, :error}, new_state}
          end
        end)

      # Consider event published if at least one relay succeeded
      success_count = Enum.count(results, fn {_url, result} -> result == :ok end)
      
      response = if success_count > 0 do
        {:ok, %{total: length(results), successful: success_count, results: results}}
      else
        {:error, %{total: length(results), successful: 0, results: results}}
      end
      
      {:reply, response, updated_state}
    end
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
  def handle_call(:relay_health, _from, state) do
    health_data = 
      state.relay_health
      |> Enum.map(fn {url, health} ->
        connection_status = case Map.get(state.connections, url) do
          %{status: status} -> status
          _ -> :unknown
        end
        {url, Map.put(health, :connection_status, connection_status)}
      end)
      |> Map.new()

    {:reply, health_data, state}
  end

  @impl true
  def handle_call(:discover_relays, _from, state) do
    # Check if we need to perform discovery (cache for 1 hour)
    now = :os.system_time(:second)
    last_discovery = state.discovery_cache.last_discovery
    
    should_discover = is_nil(last_discovery) or (now - last_discovery) > 3600

    if should_discover do
      discovered_relays = perform_relay_discovery()
      
      new_cache = %{
        last_discovery: now,
        relays: discovered_relays
      }
      
      new_state = %{state | discovery_cache: new_cache}
      {:reply, {:ok, discovered_relays}, new_state}
    else
      {:reply, {:cached, state.discovery_cache.relays}, state}
    end
  end

  @impl true
  def handle_call({:add_relay, url}, _from, state) do
    # Validate URL format
    case validate_relay_url(url) do
      :ok ->
        # Add to relay list if not already present
        if url in state.relays do
          {:reply, {:error, :already_exists}, state}
        else
          new_relays = [url | state.relays]
          new_state = %{state | relays: new_relays}
          
          # Attempt to connect to the new relay
          case connect_to_relay(url) do
            {^url, %{status: :connected} = conn} ->
              new_connections = Map.put(state.connections, url, conn)
              final_state = %{new_state | connections: new_connections}
              
              # Resubscribe to existing subscriptions
              resubscribe_to_relay(conn.pid, state.subscriptions)
              
              {:reply, :ok, final_state}
              
            {^url, %{status: :error}} ->
              {:reply, {:error, :connection_failed}, new_state}
          end
        end
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:remove_relay, url}, _from, state) do
    if url in state.relays do
      # Disconnect from relay if connected
      case Map.get(state.connections, url) do
        %{pid: pid} when not is_nil(pid) ->
          if Process.alive?(pid), do: GenServer.stop(pid)
        _ -> :ok
      end
      
      # Remove from state
      new_relays = List.delete(state.relays, url)
      new_connections = Map.delete(state.connections, url)
      new_health = Map.delete(state.relay_health, url)
      
      new_state = %{
        state | 
        relays: new_relays,
        connections: new_connections,
        relay_health: new_health
      }
      
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_found}, state}
    end
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
    # Update health metrics
    new_state = update_relay_health(state, url, :message_received)
    
    case decode_message(message) do
      ["EVENT", sub_id, event] ->
        handle_event(new_state, sub_id, event)

      ["EOSE", sub_id] ->
        Logger.debug("End of stored events for subscription: #{sub_id}")

      ["OK", event_id, success, message] ->
        handle_event_response(event_id, success, message)

      ["NOTICE", notice] ->
        Logger.info("Notice from relay #{url}: #{notice}")

      _ ->
        Logger.debug("Unknown message from relay #{url}: #{inspect(message)}")
    end

    {:noreply, new_state}
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
    
    base_relays = Keyword.get(config, :relays, [])
    dedicated_relay = Keyword.get(config, :dedicated_relay, nil)
    
    # Add dedicated relay if configured
    relays = if dedicated_relay && dedicated_relay != "" do
      [dedicated_relay | base_relays] |> Enum.uniq()
    else
      base_relays
    end

    %{
      relays: relays,
      connection_timeout: Keyword.get(config, :connection_timeout, 10_000),
      reconnect_interval: Keyword.get(config, :reconnect_interval, 5_000),
      max_reconnect_attempts: Keyword.get(config, :max_reconnect_attempts, 10),
      discovery_enabled: Keyword.get(config, :discovery_enabled, true),
      discovery_cache_ttl: Keyword.get(config, :discovery_cache_ttl, 3600),
      health_check_interval: Keyword.get(config, :health_check_interval, 30_000),
      min_relay_count: Keyword.get(config, :min_relay_count, 2)
    }
  end

  defp connect_to_relay(url) do
    start_time = :os.system_time(:millisecond)
    
    case :websocket_client.start_link(url, __MODULE__.RelayHandler, parent: self(), url: url) do
      {:ok, pid} ->
        connection_time = :os.system_time(:millisecond) - start_time
        Logger.info("Connected to Nostr relay: #{url} (#{connection_time}ms)")
        
        # Initialize health metrics
        health_metrics = %{
          connected_at: :os.system_time(:second),
          connection_time_ms: connection_time,
          message_count: 0,
          error_count: 0,
          last_message: nil,
          avg_response_time: nil
        }
        
        {url, %{pid: pid, status: :connected, attempt: 0, health: health_metrics}}

      {:error, reason} ->
        Logger.error("Failed to connect to relay #{url}: #{inspect(reason)}")
        {url, %{pid: nil, status: :error, attempt: 1, health: nil}}
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

  defp update_relay_health(state, url, event_type) do
    case Map.get(state.connections, url) do
      %{health: health} = conn when not is_nil(health) ->
        updated_health = case event_type do
          :message_received ->
            %{health | 
              message_count: health.message_count + 1,
              last_message: :os.system_time(:second)
            }
          :event_sent ->
            %{health | 
              message_count: health.message_count + 1,
              last_message: :os.system_time(:second)
            }
          :error ->
            %{health | error_count: health.error_count + 1}
        end
        
        updated_conn = %{conn | health: updated_health}
        new_connections = Map.put(state.connections, url, updated_conn)
        new_relay_health = Map.put(state.relay_health, url, updated_health)
        
        %{state | connections: new_connections, relay_health: new_relay_health}
        
      _ ->
        state
    end
  end

  defp perform_relay_discovery do
    # Known Nostr relay discovery endpoints and methods
    discovery_methods = [
      &discover_from_well_known_relays/0,
      &discover_from_nip11_endpoints/0,
      &discover_sammelkarten_specific_relays/0
    ]
    
    discovered_relays = 
      discovery_methods
      |> Enum.flat_map(fn method ->
        try do
          method.()
        rescue
          error ->
            Logger.warning("Relay discovery method failed: #{inspect(error)}")
            []
        end
      end)
      |> Enum.uniq()
      |> Enum.filter(&validate_relay_url/1)
    
    Logger.info("Discovered #{length(discovered_relays)} potential relays")
    discovered_relays
  end

  defp discover_from_well_known_relays do
    # Well-known high-quality Nostr relays
    [
      "wss://nostr.oxtr.dev",
      "wss://relay.primal.net",
      "wss://nostr.fmt.wiz.biz",
      "wss://relay.mostr.pub",
      "wss://relay.current.fyi",
      "wss://eden.nostr.land",
      "wss://nostr.milou.lol",
      "wss://relay.nostr.bg"
    ]
  end

  defp discover_from_nip11_endpoints do
    # Could implement NIP-11 relay information discovery
    # For now, return empty list as this requires HTTP requests
    []
  end

  defp discover_sammelkarten_specific_relays do
    # Future: Could include dedicated Sammelkarten relays
    # For now, return empty list
    []
  end

  defp validate_relay_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["ws", "wss"] and not is_nil(host) ->
        :ok
      _ ->
        {:error, :invalid_url}
    end
  end

  defp validate_relay_url(_), do: {:error, :invalid_format}
end

if not Code.ensure_loaded?(Sammelkarten.Nostr.Client.RelayHandler) do
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
end
