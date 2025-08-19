defmodule Sammelkarten.Nostr.PriceAlertWatcher do
  @moduledoc """
  GenServer that watches for price changes and triggers alert notifications.
  Subscribes to price updates and portfolio snapshots to detect alert conditions.
  """

  use GenServer
  alias Sammelkarten.Cards
  alias Phoenix.PubSub

  require Logger


  defstruct [
    :alerts,
    :last_prices
  ]

  @type t :: %__MODULE__{
          alerts: map(),
          last_prices: map()
        }

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a price alert for a card.
  """
  def register_alert(pubkey, card_id, direction, threshold) when direction in [:above, :below] do
    GenServer.call(__MODULE__, {:register_alert, pubkey, card_id, direction, threshold})
  end

  @doc """
  Remove a price alert.
  """
  def remove_alert(pubkey, card_id, direction) do
    GenServer.call(__MODULE__, {:remove_alert, pubkey, card_id, direction})
  end

  @doc """
  List all active alerts.
  """
  def list_alerts do
    GenServer.call(__MODULE__, :list_alerts)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Subscribe to price updates
    PubSub.subscribe(Sammelkarten.PubSub, "price_updates")
    
    # Subscribe to Nostr portfolio updates
    PubSub.subscribe(Sammelkarten.PubSub, "nostr:portfolios")

    # Get current prices
    current_prices = get_current_prices()

    state = %__MODULE__{
      alerts: %{},
      last_prices: current_prices
    }

    Logger.info("Price Alert Watcher started")
    {:ok, state}
  end

  @impl true
  def handle_call({:register_alert, pubkey, card_id, direction, threshold}, _from, state) do
    alert_key = {pubkey, card_id, direction}
    
    alert = %{
      pubkey: pubkey,
      card_id: card_id,
      direction: direction,
      threshold: threshold,
      created_at: DateTime.utc_now() |> DateTime.to_unix(),
      triggered: false
    }

    new_alerts = Map.put(state.alerts, alert_key, alert)
    new_state = %{state | alerts: new_alerts}

    # Broadcast alert registration
    PubSub.broadcast(
      Sammelkarten.PubSub,
      "nostr:alerts",
      {:alert_registered, alert}
    )

    Logger.debug("Registered price alert: #{pubkey} #{card_id} #{direction} #{threshold}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:remove_alert, pubkey, card_id, direction}, _from, state) do
    alert_key = {pubkey, card_id, direction}
    new_alerts = Map.delete(state.alerts, alert_key)
    new_state = %{state | alerts: new_alerts}

    # Broadcast alert removal
    PubSub.broadcast(
      Sammelkarten.PubSub,
      "nostr:alerts",
      {:alert_removed, {pubkey, card_id, direction}}
    )

    Logger.debug("Removed price alert: #{pubkey} #{card_id} #{direction}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:list_alerts, _from, state) do
    alerts = Map.values(state.alerts)
    {:reply, alerts, state}
  end

  @impl true
  def handle_info({:price_update, updates}, state) do
    new_state = check_price_alerts(updates, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:portfolio_updated, _portfolio_data}, state) do
    # Portfolio updates might indicate price changes, recheck alerts
    current_prices = get_current_prices()
    new_state = %{state | last_prices: current_prices}
    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp get_current_prices do
    try do
      Cards.list_cards()
      |> Enum.reduce(%{}, fn card, acc ->
        Map.put(acc, card.card_id, card.current_price)
      end)
    rescue
      _ -> %{}
    end
  end

  defp check_price_alerts(price_updates, state) do
    # Update our price tracking
    new_prices = 
      Enum.reduce(price_updates, state.last_prices, fn {card_id, new_price}, acc ->
        Map.put(acc, card_id, new_price)
      end)

    # Check each alert
    triggered_alerts = 
      Enum.reduce(state.alerts, [], fn {{_pubkey, card_id, direction} = key, alert}, acc ->
        old_price = Map.get(state.last_prices, card_id, 0)
        new_price = Map.get(new_prices, card_id, old_price)

        if should_trigger_alert?(alert, old_price, new_price) do
          # Mark as triggered and add to list
          triggered_alert = %{alert | triggered: true}
          PubSub.broadcast(
            Sammelkarten.PubSub,
            "nostr:alerts",
            {:alert_triggered, triggered_alert, old_price, new_price}
          )

          Logger.info("Price alert triggered: #{card_id} #{direction} threshold #{alert.threshold}, price: #{old_price} -> #{new_price}")
          
          [key | acc]
        else
          acc
        end
      end)

    # Remove triggered alerts (one-time alerts)
    new_alerts = 
      Enum.reduce(triggered_alerts, state.alerts, fn key, alerts ->
        Map.delete(alerts, key)
      end)

    %{state | alerts: new_alerts, last_prices: new_prices}
  end

  defp should_trigger_alert?(%{direction: :above, threshold: threshold, triggered: false}, old_price, new_price) do
    old_price <= threshold and new_price > threshold
  end

  defp should_trigger_alert?(%{direction: :below, threshold: threshold, triggered: false}, old_price, new_price) do
    old_price >= threshold and new_price < threshold
  end

  defp should_trigger_alert?(_, _, _), do: false
end