defmodule Sammelkarten.Nostr.Relay do
  @moduledoc """
  Simple Nostr relay server implementation following NIP-01.
  
  Supports basic relay operations:
  - EVENT: Store and broadcast events
  - REQ: Query events with filters
  - CLOSE: Close subscription
  - COUNT: Count events matching filters
  
  Specialized for kinds 32121-32130 with SQLite persistence.
  """
  
  use GenServer
  require Logger
  
  alias Sammelkarten.Nostr.{Event, Schema}
  alias Sammelkarten.Nostr.Relay.Storage
  
  @allowed_kinds 32121..32130
  @rate_limit_window 60_000  # 1 minute
  @rate_limit_count 100      # 100 events per minute per pubkey
  
  defstruct [:storage, :subscriptions, :rate_limits]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    {:ok, storage} = Storage.start_link()
    
    state = %__MODULE__{
      storage: storage,
      subscriptions: %{},
      rate_limits: %{}
    }
    
    Logger.info("Nostr Relay started")
    {:ok, state}
  end
  
  # Public API
  
  def handle_message(message, client_pid) do
    GenServer.cast(__MODULE__, {:handle_message, message, client_pid})
  end
  
  def subscribe(subscription_id, filters, client_pid) do
    GenServer.cast(__MODULE__, {:subscribe, subscription_id, filters, client_pid})
  end
  
  def close_subscription(subscription_id, client_pid) do
    GenServer.cast(__MODULE__, {:close, subscription_id, client_pid})
  end
  
  # GenServer callbacks
  
  @impl true
  def handle_cast({:handle_message, message, client_pid}, state) do
    case Jason.decode(message) do
      {:ok, parsed} -> 
        handle_parsed_message(parsed, client_pid, state)
      {:error, _} -> 
        send_notice(client_pid, "Invalid JSON")
        {:noreply, state}
    end
  end
  
  def handle_cast({:subscribe, sub_id, filters, client_pid}, state) do
    # Store subscription
    subscriptions = Map.put(state.subscriptions, {client_pid, sub_id}, filters)
    
    # Send matching events
    events = Storage.query_events(state.storage, filters)
    for event <- events do
      send_event(client_pid, sub_id, event)
    end
    
    # Send EOSE
    send_eose(client_pid, sub_id)
    
    {:noreply, %{state | subscriptions: subscriptions}}
  end
  
  def handle_cast({:close, sub_id, client_pid}, state) do
    subscriptions = Map.delete(state.subscriptions, {client_pid, sub_id})
    send_closed(client_pid, sub_id)
    {:noreply, %{state | subscriptions: subscriptions}}
  end
  
  # Private functions
  
  defp handle_parsed_message(["EVENT", event_data], client_pid, state) do
    case validate_and_store_event(event_data, client_pid, state) do
      {:ok, event, new_state} ->
        broadcast_event(event, new_state)
        send_ok(client_pid, event.id, true, "")
        {:noreply, new_state}
      
      {:error, reason, new_state} ->
        event_id = Map.get(event_data, "id", "unknown")
        send_ok(client_pid, event_id, false, reason)
        {:noreply, new_state}
    end
  end
  
  defp handle_parsed_message(["REQ", sub_id | filters], client_pid, state) do
    subscribe(sub_id, filters, client_pid)
    {:noreply, state}
  end
  
  defp handle_parsed_message(["CLOSE", sub_id], client_pid, state) do
    close_subscription(sub_id, client_pid)
    {:noreply, state}
  end
  
  defp handle_parsed_message(["COUNT", sub_id | filters], client_pid, state) do
    count = Storage.count_events(state.storage, filters)
    send_count(client_pid, sub_id, count)
    {:noreply, state}
  end
  
  defp handle_parsed_message(_, client_pid, state) do
    send_notice(client_pid, "Unsupported message type")
    {:noreply, state}
  end
  
  defp validate_and_store_event(event_data, _client_pid, state) do
    with {:ok, event} <- parse_event(event_data),
         :ok <- validate_event(event),
         :ok <- check_rate_limit(event.pubkey, state),
         {:ok, new_state} <- update_rate_limit(event.pubkey, state),
         :ok <- Storage.store_event(state.storage, event) do
      {:ok, event, new_state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end
  
  defp parse_event(event_data) do
    try do
      event = %Event{
        id: event_data["id"],
        pubkey: event_data["pubkey"],
        created_at: event_data["created_at"],
        kind: event_data["kind"],
        tags: event_data["tags"] || [],
        content: event_data["content"] || "",
        sig: event_data["sig"]
      }
      {:ok, event}
    rescue
      _ -> {:error, "Invalid event format"}
    end
  end
  
  defp validate_event(event) do
    with :ok <- validate_kind(event.kind),
         {:ok, _} <- Event.verify(event),
         {:ok, _} <- Schema.validate(event) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, "Event validation failed"}
    end
  end
  
  defp validate_kind(kind) do
    if kind in @allowed_kinds do
      :ok
    else
      {:error, "Kind #{kind} not allowed"}
    end
  end
  
  defp check_rate_limit(pubkey, state) do
    now = System.system_time(:millisecond)
    window_start = now - @rate_limit_window
    
    case Map.get(state.rate_limits, pubkey) do
      nil -> :ok
      {first_time, _count} when first_time < window_start -> :ok
      {_first_time, count} when count < @rate_limit_count -> :ok
      _ -> {:error, "Rate limit exceeded"}
    end
  end
  
  defp update_rate_limit(pubkey, state) do
    now = System.system_time(:millisecond)
    window_start = now - @rate_limit_window
    
    rate_limits = case Map.get(state.rate_limits, pubkey) do
      nil -> Map.put(state.rate_limits, pubkey, {now, 1})
      {first_time, _count} when first_time < window_start -> 
        Map.put(state.rate_limits, pubkey, {now, 1})
      {first_time, count} -> 
        Map.put(state.rate_limits, pubkey, {first_time, count + 1})
    end
    
    {:ok, %{state | rate_limits: rate_limits}}
  end
  
  defp broadcast_event(event, state) do
    for {{client_pid, sub_id}, filters} <- state.subscriptions do
      if event_matches_filters?(event, filters) do
        send_event(client_pid, sub_id, event)
      end
    end
  end
  
  defp event_matches_filters?(event, filters) do
    Enum.any?(filters, fn filter ->
      filter = Enum.into(filter, %{})
      
      Enum.all?(filter, fn
        {"kinds", kinds} -> event.kind in kinds
        {"authors", authors} -> event.pubkey in authors
        {"ids", ids} -> event.id in ids
        {"#" <> tag_name, values} -> 
          event.tags
          |> Enum.filter(fn [name | _] -> name == tag_name end)
          |> Enum.any?(fn [_ | tag_values] -> 
            Enum.any?(tag_values, &(&1 in values))
          end)
        {"since", since} -> event.created_at >= since
        {"until", until} -> event.created_at <= until
        {"limit", _} -> true
        _ -> true
      end)
    end)
  end
  
  # Message sending helpers
  
  defp send_ok(client_pid, event_id, success, message) do
    response = Jason.encode!(["OK", event_id, success, message])
    send(client_pid, {:relay_message, response})
  end
  
  defp send_event(client_pid, sub_id, event) do
    event_map = Map.from_struct(event)
    response = Jason.encode!(["EVENT", sub_id, event_map])
    send(client_pid, {:relay_message, response})
  end
  
  defp send_eose(client_pid, sub_id) do
    response = Jason.encode!(["EOSE", sub_id])
    send(client_pid, {:relay_message, response})
  end
  
  defp send_closed(client_pid, sub_id) do
    response = Jason.encode!(["CLOSED", sub_id])
    send(client_pid, {:relay_message, response})
  end
  
  defp send_count(client_pid, sub_id, count) do
    response = Jason.encode!(["COUNT", sub_id, %{"count" => count}])
    send(client_pid, {:relay_message, response})
  end
  
  defp send_notice(client_pid, message) do
    response = Jason.encode!(["NOTICE", message])
    send(client_pid, {:relay_message, response})
  end
end