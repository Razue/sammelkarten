defmodule Sammelkarten.TradingBot do
  @moduledoc """
  Programmatic trading system that enables automated trading via Nostr events.

  This module provides functionality for:
  - Processing automated trading commands via Nostr events
  - Bot authentication and permission management
  - Strategy execution with risk management
  - Rate limiting and anti-abuse measures
  - Real-time market response capabilities
  """

  use GenServer
  require Logger
  alias Sammelkarten.{Cards, Nostr}
  alias Sammelkarten.Trading

  # Bot-specific Nostr event kinds (use separate range to avoid collision with core 32121-32127)
  # Bot trading commands
  @bot_command_kind 32140
  # @bot_status_kind 32141   # Bot status updates (unused)
  # Bot execution responses
  @bot_response_kind 32242

  # Bot execution limits
  # Commands per minute
  @default_rate_limit 10
  # Maximum trade value in cents
  @max_trade_value 100_000
  # Milliseconds between commands
  @cooldown_period 5_000

  defstruct [
    :bot_pubkey,
    :owner_pubkey,
    :strategy,
    :permissions,
    :rate_limit,
    :last_command,
    :command_count,
    :status,
    :created_at
  ]

  # Client API

  @doc """
  Start the trading bot system.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Register a new trading bot with specific permissions and strategies.
  """
  def register_bot(bot_pubkey, owner_pubkey, opts \\ []) do
    GenServer.call(__MODULE__, {:register_bot, bot_pubkey, owner_pubkey, opts})
  end

  @doc """
  Process a bot trading command from a Nostr event.
  """
  def process_command(event) do
    GenServer.cast(__MODULE__, {:process_command, event})
  end

  @doc """
  Get all registered bots for a user.
  """
  def get_user_bots(owner_pubkey) do
    GenServer.call(__MODULE__, {:get_user_bots, owner_pubkey})
  end

  @doc """
  Enable or disable a trading bot.
  """
  def set_bot_status(bot_pubkey, status) when status in [:active, :paused, :disabled] do
    GenServer.call(__MODULE__, {:set_bot_status, bot_pubkey, status})
  end

  @doc """
  Remove a trading bot.
  """
  def remove_bot(bot_pubkey, owner_pubkey) do
    GenServer.call(__MODULE__, {:remove_bot, bot_pubkey, owner_pubkey})
  end

  # Server implementation

  @impl true
  def init(_) do
    # Subscribe to bot command events
    handler = fn event -> process_command(event) end

    Nostr.Client.subscribe(
      "trading_bots",
      [
        %{
          "kinds" => [@bot_command_kind],
          "#t" => ["sammelkarten", "bot_command"]
        }
      ],
      handler
    )

    {:ok, %{bots: %{}, command_history: %{}}}
  end

  @impl true
  def handle_call({:register_bot, bot_pubkey, owner_pubkey, opts}, _from, state) do
    strategy = Keyword.get(opts, :strategy, :market_maker)
    permissions = Keyword.get(opts, :permissions, default_permissions())
    rate_limit = Keyword.get(opts, :rate_limit, @default_rate_limit)

    bot = %__MODULE__{
      bot_pubkey: bot_pubkey,
      owner_pubkey: owner_pubkey,
      strategy: strategy,
      permissions: permissions,
      rate_limit: rate_limit,
      last_command: nil,
      command_count: 0,
      status: :active,
      created_at: :os.system_time(:second)
    }

    # Store bot in database
    case store_bot(bot) do
      :ok ->
        new_bots = Map.put(state.bots, bot_pubkey, bot)
        new_state = %{state | bots: new_bots}

        Logger.info("Trading bot registered: #{bot_pubkey} for owner #{owner_pubkey}")
        {:reply, {:ok, bot}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_user_bots, owner_pubkey}, _from, state) do
    user_bots =
      state.bots
      |> Enum.filter(fn {_pubkey, bot} -> bot.owner_pubkey == owner_pubkey end)
      |> Enum.map(fn {_pubkey, bot} -> bot end)

    {:reply, user_bots, state}
  end

  @impl true
  def handle_call({:set_bot_status, bot_pubkey, status}, _from, state) do
    case Map.get(state.bots, bot_pubkey) do
      nil ->
        {:reply, {:error, :bot_not_found}, state}

      bot ->
        updated_bot = %{bot | status: status}
        new_bots = Map.put(state.bots, bot_pubkey, updated_bot)
        new_state = %{state | bots: new_bots}

        # Update in database
        store_bot(updated_bot)

        Logger.info("Bot #{bot_pubkey} status changed to #{status}")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:remove_bot, bot_pubkey, owner_pubkey}, _from, state) do
    case Map.get(state.bots, bot_pubkey) do
      %{owner_pubkey: ^owner_pubkey} ->
        # Remove from state and database
        new_bots = Map.delete(state.bots, bot_pubkey)
        new_state = %{state | bots: new_bots}

        remove_bot_from_db(bot_pubkey)

        Logger.info("Bot #{bot_pubkey} removed by owner #{owner_pubkey}")
        {:reply, :ok, new_state}

      nil ->
        {:reply, {:error, :bot_not_found}, state}

      _ ->
        {:reply, {:error, :unauthorized}, state}
    end
  end

  @impl true
  def handle_cast({:process_command, event}, state) do
    case validate_and_execute_command(event, state) do
      {:ok, response, new_state} ->
        # Publish response event
        publish_bot_response(response)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("Bot command failed: #{reason}")
        publish_error_response(event, reason)
        {:noreply, state}
    end
  end

  # Private functions

  defp default_permissions do
    %{
      can_buy: true,
      can_sell: true,
      can_exchange: true,
      max_trade_value: @max_trade_value,
      # or list of card IDs
      allowed_cards: :all,
      max_daily_trades: 100
    }
  end

  defp validate_and_execute_command(event, state) do
    with {:ok, bot} <- get_bot_for_event(event, state),
         :ok <- validate_rate_limit(bot),
         :ok <- validate_permissions(event, bot),
         {:ok, command} <- parse_command(event),
         {:ok, result} <- execute_command(command, bot) do
      # Update bot state
      updated_bot = update_bot_after_command(bot)
      new_bots = Map.put(state.bots, bot.bot_pubkey, updated_bot)
      new_state = %{state | bots: new_bots}

      response = create_response(event, result)
      {:ok, response, new_state}
    else
      error -> error
    end
  end

  defp get_bot_for_event(event, state) do
    bot_pubkey = event["pubkey"]

    case Map.get(state.bots, bot_pubkey) do
      nil -> {:error, :bot_not_registered}
      %{status: :disabled} -> {:error, :bot_disabled}
      %{status: :paused} -> {:error, :bot_paused}
      bot -> {:ok, bot}
    end
  end

  defp validate_rate_limit(bot) do
    now = :os.system_time(:millisecond)

    case bot.last_command do
      nil -> :ok
      last_time when now - last_time > @cooldown_period -> :ok
      _ -> {:error, :rate_limited}
    end
  end

  defp validate_permissions(event, bot) do
    # Parse command type from event content
    case parse_command_type(event) do
      {:ok, :buy} when bot.permissions.can_buy -> :ok
      {:ok, :sell} when bot.permissions.can_sell -> :ok
      {:ok, :exchange} when bot.permissions.can_exchange -> :ok
      {:ok, command_type} -> {:error, {:permission_denied, command_type}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_command(event) do
    try do
      content = Jason.decode!(event["content"])

      command = %{
        type: content["type"],
        card_id: content["card_id"],
        quantity: content["quantity"],
        price: content["price"],
        strategy_params: content["strategy_params"] || %{}
      }

      {:ok, command}
    rescue
      _ -> {:error, :invalid_command_format}
    end
  end

  defp parse_command_type(event) do
    try do
      content = Jason.decode!(event["content"])
      command_type = String.to_atom(content["type"])

      if command_type in [:buy, :sell, :exchange] do
        {:ok, command_type}
      else
        {:error, :unknown_command_type}
      end
    rescue
      _ -> {:error, :invalid_command_format}
    end
  end

  defp execute_command(command, bot) do
    case command.type do
      "buy" -> execute_buy_command(command, bot)
      "sell" -> execute_sell_command(command, bot)
      "exchange" -> execute_exchange_command(command, bot)
      "market_make" -> execute_market_make_command(command, bot)
      _ -> {:error, :unknown_command}
    end
  end

  defp execute_buy_command(command, bot) do
    # Validate trade value against bot permissions
    trade_value = command.price * command.quantity

    if trade_value <= bot.permissions.max_trade_value do
      # Create buy offer via Trading module
      offer_params = %{
        user_pubkey: bot.owner_pubkey,
        card_id: command.card_id,
        type: "buy",
        quantity: command.quantity,
        price: command.price,
        # 24 hours
        expires_at: :os.system_time(:second) + 86400
      }

      case Trading.create_offer(offer_params) do
        {:ok, offer} -> {:ok, %{action: :buy_offer_created, offer_id: offer.id}}
        error -> error
      end
    else
      {:error, :trade_value_exceeds_limit}
    end
  end

  defp execute_sell_command(command, bot) do
    # Check if owner has the cards to sell
    case Trading.get_user_card_quantity(bot.owner_pubkey, command.card_id) do
      quantity when quantity >= command.quantity ->
        offer_params = %{
          user_pubkey: bot.owner_pubkey,
          card_id: command.card_id,
          type: "sell",
          quantity: command.quantity,
          price: command.price,
          expires_at: :os.system_time(:second) + 86400
        }

        case Trading.create_offer(offer_params) do
          {:ok, offer} -> {:ok, %{action: :sell_offer_created, offer_id: offer.id}}
          error -> error
        end

      _ ->
        {:error, :insufficient_cards}
    end
  end

  defp execute_exchange_command(_command, _bot) do
    # Exchange command for card-for-card trading
    {:ok, %{action: :exchange_offer_created, message: "Exchange functionality pending"}}
  end

  defp execute_market_make_command(command, bot) do
    # Market making strategy - create both buy and sell orders
    case Cards.get_card(command.card_id) do
      {:ok, card} ->
        current_price = card.current_price

        # Create buy order at 2% below market
        buy_price = trunc(current_price * 0.98)

        buy_offer = %{
          user_pubkey: bot.owner_pubkey,
          card_id: command.card_id,
          type: "buy",
          quantity: command.quantity,
          price: buy_price,
          # 12 hours
          expires_at: :os.system_time(:second) + 43200
        }

        # Create sell order at 2% above market (if user has cards)
        sell_price = trunc(current_price * 1.02)
        user_quantity = Trading.get_user_card_quantity(bot.owner_pubkey, command.card_id)

        results = []

        # Create buy offer
        results =
          case Trading.create_offer(buy_offer) do
            {:ok, offer} -> [{:buy_offer_created, offer.id} | results]
            _ -> results
          end

        # Create sell offer if user has cards
        results =
          if user_quantity > 0 do
            sell_quantity = min(user_quantity, command.quantity)

            sell_offer = %{
              user_pubkey: bot.owner_pubkey,
              card_id: command.card_id,
              type: "sell",
              quantity: sell_quantity,
              price: sell_price,
              expires_at: :os.system_time(:second) + 43200
            }

            case Trading.create_offer(sell_offer) do
              {:ok, offer} -> [{:sell_offer_created, offer.id} | results]
              _ -> results
            end
          else
            results
          end

        {:ok, %{action: :market_make_completed, results: results}}

      {:error, _reason} ->
        {:error, :card_not_found}
    end
  end

  defp update_bot_after_command(bot) do
    %{bot | last_command: :os.system_time(:millisecond), command_count: bot.command_count + 1}
  end

  defp create_response(original_event, result) do
    %{
      kind: @bot_response_kind,
      content:
        Jason.encode!(%{
          original_id: original_event["id"],
          result: result,
          timestamp: :os.system_time(:second)
        }),
      tags: [
        ["e", original_event["id"]],
        ["p", original_event["pubkey"]],
        ["t", "sammelkarten"],
        ["t", "bot_response"]
      ]
    }
  end

  defp publish_bot_response(response) do
    case Nostr.Client.publish_event(response) do
      {:ok, _} -> Logger.debug("Bot response published successfully")
      error -> Logger.error("Failed to publish bot response: #{inspect(error)}")
    end
  end

  defp publish_error_response(original_event, reason) do
    error_response = %{
      kind: @bot_response_kind,
      content:
        Jason.encode!(%{
          original_id: original_event["id"],
          error: reason,
          timestamp: :os.system_time(:second)
        }),
      tags: [
        ["e", original_event["id"]],
        ["p", original_event["pubkey"]],
        ["t", "sammelkarten"],
        ["t", "bot_error"]
      ]
    }

    Nostr.Client.publish_event(error_response)
  end

  defp store_bot(_bot) do
    # For now, we'll store in memory. In production, this would use Mnesia
    # TODO: Add proper database storage for bots
    :ok
  end

  defp remove_bot_from_db(_bot_pubkey) do
    # TODO: Remove from database
    :ok
  end
end
