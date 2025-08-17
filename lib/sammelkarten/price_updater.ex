defmodule Sammelkarten.PriceUpdater do
  @moduledoc """
  GenServer for handling background price updates.

  This process:
  - Runs periodic price updates for all cards
  - Publishes price changes via PubSub for real-time UI updates
  - Handles manual update triggers
  - Manages update intervals and scheduling
  """

  use GenServer

  alias Sammelkarten.PriceEngine
  alias Phoenix.PubSub

  require Logger

  # Update every 420 seconds
  @update_interval :timer.seconds(420)
  @pubsub_topic "price_updates"

  ## Client API

  @doc """
  Start the price updater GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Trigger an immediate price update.
  """
  def update_now do
    GenServer.cast(__MODULE__, :update_prices)
  end

  @doc """
  Get the current update interval.
  """
  def get_interval do
    GenServer.call(__MODULE__, :get_interval)
  end

  @doc """
  Set a new update interval (in milliseconds).
  """
  def set_interval(new_interval) when is_integer(new_interval) and new_interval > 0 do
    GenServer.cast(__MODULE__, {:set_interval, new_interval})
  end

  @doc """
  Enable or disable automatic price refreshes.
  """
  def set_auto_refresh(enabled) when is_boolean(enabled) do
    GenServer.cast(__MODULE__, {:set_auto_refresh, enabled})
  end

  @doc """
  Pause automatic updates.
  """
  def pause do
    GenServer.cast(__MODULE__, :pause)
  end

  @doc """
  Resume automatic updates.
  """
  def resume do
    GenServer.cast(__MODULE__, :resume)
  end

  @doc """
  Get the current status of the price updater.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  ## Server Implementation

  @impl true
  def init(_opts) do
    # Load user preferences to get initial refresh rate and auto_refresh setting
    {default_interval, auto_refresh_enabled} =
      case Sammelkarten.Preferences.get_user_preferences("default_user") do
        {:ok, preferences} -> {preferences.refresh_rate, preferences.auto_refresh}
        {:error, _} -> {@update_interval, true}
      end

    state = %{
      interval: default_interval,
      timer_ref: nil,
      paused: false,
      auto_refresh_enabled: auto_refresh_enabled,
      last_update: nil,
      update_count: 0
    }

    # Schedule the first update only if auto_refresh is enabled
    state = schedule_next_update(state)

    Logger.info(
      "Price updater started with #{state.interval}ms interval, auto_refresh: #{auto_refresh_enabled}"
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:get_interval, _from, state) do
    {:reply, state.interval, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      interval: state.interval,
      paused: state.paused,
      auto_refresh_enabled: state.auto_refresh_enabled,
      last_update: state.last_update,
      update_count: state.update_count,
      next_update: if(state.timer_ref, do: "scheduled", else: "none")
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast(:update_prices, state) do
    new_state = perform_price_update(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_interval, new_interval}, state) do
    Logger.info("Updating price update interval to #{new_interval}ms")

    # Cancel existing timer and start new one
    state = cancel_timer(state)
    new_state = %{state | interval: new_interval}
    new_state = schedule_next_update(new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_auto_refresh, enabled}, state) do
    Logger.info("#{if enabled, do: "Enabling", else: "Disabling"} automatic price refreshes")

    state = cancel_timer(state)
    new_state = %{state | auto_refresh_enabled: enabled}

    # If enabling auto_refresh, schedule next update; if disabling, don't schedule
    new_state = if enabled, do: schedule_next_update(new_state), else: new_state

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:pause, state) do
    Logger.info("Pausing automatic price updates")
    state = cancel_timer(state)
    new_state = %{state | paused: true}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:resume, state) do
    Logger.info("Resuming automatic price updates")
    new_state = %{state | paused: false}
    new_state = schedule_next_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:update_prices, state) do
    new_state = perform_price_update(state)
    new_state = schedule_next_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Handle monitored process going down if needed
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Price updater terminating: #{inspect(reason)}")
    cancel_timer(state)
    :ok
  end

  ## Private Functions

  defp perform_price_update(state) do
    Logger.debug("Performing scheduled price update...")

    start_time = System.monotonic_time(:millisecond)

    case PriceEngine.update_all_prices() do
      {:ok, updated_count} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.info("Price update completed: #{updated_count} cards updated in #{duration}ms")

        # Broadcast price update notification
        PubSub.broadcast(
          Sammelkarten.PubSub,
          @pubsub_topic,
          {:price_update_completed, %{updated_count: updated_count, duration: duration}}
        )

        %{state | last_update: DateTime.utc_now(), update_count: state.update_count + 1}

      {:error, reason} ->
        Logger.error("Price update failed: #{inspect(reason)}")

        PubSub.broadcast(
          Sammelkarten.PubSub,
          @pubsub_topic,
          {:price_update_failed, %{reason: reason}}
        )

        state
    end
  end

  defp schedule_next_update(%{paused: true} = state), do: state
  defp schedule_next_update(%{auto_refresh_enabled: false} = state), do: state

  defp schedule_next_update(%{interval: interval} = state) do
    timer_ref = Process.send_after(self(), :update_prices, interval)
    %{state | timer_ref: timer_ref}
  end

  defp cancel_timer(%{timer_ref: nil} = state), do: state

  defp cancel_timer(%{timer_ref: timer_ref} = state) do
    Process.cancel_timer(timer_ref)
    %{state | timer_ref: nil}
  end

  ## PubSub Helper Functions

  @doc """
  Subscribe to price update notifications.
  """
  def subscribe do
    PubSub.subscribe(Sammelkarten.PubSub, @pubsub_topic)
  end

  @doc """
  Unsubscribe from price update notifications.
  """
  def unsubscribe do
    PubSub.unsubscribe(Sammelkarten.PubSub, @pubsub_topic)
  end
end
