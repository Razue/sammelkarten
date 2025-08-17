defmodule Sammelkarten.BatchTrading do
  @moduledoc """
  Batch trading functionality for executing multiple card trades in a single transaction.

  This module provides:
  - Bundle creation for multi-card trades
  - Atomic execution of trade batches
  - Bulk pricing calculations
  - Portfolio impact assessment
  - Nostr event publishing for batch trades
  """

  require Logger

  alias Sammelkarten.Cards
  # alias Sammelkarten.Nostr.Client

  # Batch trade types
  @type batch_id :: String.t()
  @type trade_item :: %{
          card_id: String.t(),
          quantity: integer(),
          price: integer(),
          trade_type: :buy | :sell
        }
  @type batch_trade :: %{
          batch_id: batch_id(),
          user_pubkey: String.t(),
          items: [trade_item()],
          total_value: integer(),
          status: :pending | :executing | :completed | :failed | :cancelled,
          created_at: DateTime.t(),
          executed_at: DateTime.t() | nil,
          counterparties: [String.t()],
          execution_method: :atomic | :sequential
        }

  defstruct [
    :batch_id,
    :user_pubkey,
    :items,
    :total_value,
    :status,
    :created_at,
    :executed_at,
    :counterparties,
    :execution_method,
    :error_reason
  ]

  @doc """
  Create a new batch trade containing multiple trade items.
  """
  def create_batch(user_pubkey, items, execution_method \\ :atomic) do
    batch_id = generate_batch_id()

    # Validate all trade items
    case validate_trade_items(items, user_pubkey) do
      :ok ->
        total_value = calculate_total_value(items)

        batch = %__MODULE__{
          batch_id: batch_id,
          user_pubkey: user_pubkey,
          items: items,
          total_value: total_value,
          status: :pending,
          created_at: DateTime.utc_now(),
          execution_method: execution_method,
          counterparties: []
        }

        case store_batch(batch) do
          :ok ->
            Logger.info("Created batch trade #{batch_id} with #{length(items)} items")
            {:ok, batch}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Execute a batch trade, either atomically or sequentially.
  """
  def execute_batch(batch_id) do
    case get_batch(batch_id) do
      {:ok, batch} when batch.status == :pending ->
        updated_batch = %{batch | status: :executing}
        update_batch(updated_batch)

        case batch.execution_method do
          :atomic ->
            execute_atomic_batch(batch)

          :sequential ->
            execute_sequential_batch(batch)
        end

      {:ok, batch} ->
        {:error, {:invalid_status, batch.status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get batch trade by ID.
  """
  def get_batch(batch_id) do
    case :mnesia.dirty_read(:batch_trades, batch_id) do
      [batch] -> {:ok, batch}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Get all batch trades for a user.
  """
  def get_user_batches(user_pubkey, limit \\ 50) do
    match_spec = [
      {{:batch_trades, :"$1", user_pubkey, :"$3", :"$4", :"$5", :"$6", :"$7", :"$8", :"$9"}, [],
       [:"$_"]}
    ]

    :mnesia.dirty_select(:batch_trades, match_spec)
    |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
    |> Enum.take(limit)
  end

  @doc """
  Cancel a pending batch trade.
  """
  def cancel_batch(batch_id, user_pubkey) do
    case get_batch(batch_id) do
      {:ok, batch} when batch.user_pubkey == user_pubkey and batch.status == :pending ->
        updated_batch = %{batch | status: :cancelled}

        case update_batch(updated_batch) do
          :ok ->
            Logger.info("Cancelled batch trade #{batch_id}")
            publish_batch_event(updated_batch, :cancelled)
            {:ok, updated_batch}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, batch} when batch.user_pubkey != user_pubkey ->
        {:error, :unauthorized}

      {:ok, batch} ->
        {:error, {:cannot_cancel_status, batch.status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Calculate the potential impact of a batch trade on a user's portfolio.
  """
  def calculate_portfolio_impact(user_pubkey, items) do
    # Get current portfolio
    current_cards = Cards.get_user_cards(user_pubkey)

    # Calculate changes for each item
    impacts =
      Enum.map(items, fn item ->
        current_quantity = get_current_quantity(current_cards, item.card_id)

        new_quantity =
          case item.trade_type do
            :buy -> current_quantity + item.quantity
            :sell -> current_quantity - item.quantity
          end

        %{
          card_id: item.card_id,
          current_quantity: current_quantity,
          new_quantity: max(0, new_quantity),
          quantity_change: new_quantity - current_quantity,
          value_change: item.price * item.quantity * if(item.trade_type == :buy, do: -1, else: 1)
        }
      end)

    total_value_change = Enum.sum(Enum.map(impacts, & &1.value_change))

    %{
      impacts: impacts,
      total_value_change: total_value_change,
      net_cards_change: Enum.sum(Enum.map(impacts, & &1.quantity_change))
    }
  end

  # Private helper functions

  defp generate_batch_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp validate_trade_items(items, user_pubkey) do
    with :ok <- validate_items_not_empty(items),
         :ok <- validate_items_structure(items),
         :ok <- validate_cards_exist(items),
         :ok <- validate_user_ownership(items, user_pubkey) do
      :ok
    end
  end

  defp validate_items_not_empty([]), do: {:error, :empty_batch}
  defp validate_items_not_empty(_), do: :ok

  defp validate_items_structure(items) do
    required_keys = [:card_id, :quantity, :price, :trade_type]

    invalid_items =
      Enum.filter(items, fn item ->
        not (is_map(item) and Enum.all?(required_keys, &Map.has_key?(item, &1)))
      end)

    if Enum.empty?(invalid_items) do
      :ok
    else
      {:error, {:invalid_items, length(invalid_items)}}
    end
  end

  defp validate_cards_exist(items) do
    card_ids = Enum.map(items, & &1.card_id)
    existing_cards = Cards.get_cards_by_ids(card_ids)
    existing_ids = Enum.map(existing_cards, & &1.id)

    missing_ids = card_ids -- existing_ids

    if Enum.empty?(missing_ids) do
      :ok
    else
      {:error, {:cards_not_found, missing_ids}}
    end
  end

  defp validate_user_ownership(items, user_pubkey) do
    # For sell items, verify user owns enough cards
    sell_items = Enum.filter(items, &(&1.trade_type == :sell))
    user_cards = Cards.get_user_cards(user_pubkey)

    insufficient_items =
      Enum.filter(sell_items, fn item ->
        current_quantity = get_current_quantity(user_cards, item.card_id)
        current_quantity < item.quantity
      end)

    if Enum.empty?(insufficient_items) do
      :ok
    else
      {:error, {:insufficient_cards, Enum.map(insufficient_items, & &1.card_id)}}
    end
  end

  defp calculate_total_value(items) do
    Enum.reduce(items, 0, fn item, acc ->
      item_value = item.price * item.quantity

      case item.trade_type do
        # Spending money
        :buy -> acc - item_value
        # Receiving money
        :sell -> acc + item_value
      end
    end)
  end

  defp execute_atomic_batch(batch) do
    # Execute all trades as a single Mnesia transaction
    transaction = fn ->
      try do
        # Execute all trade items
        counterparties =
          batch.items
          |> Enum.map(&execute_trade_item(&1, batch.user_pubkey))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        # Update batch status
        updated_batch = %{
          batch
          | status: :completed,
            executed_at: DateTime.utc_now(),
            counterparties: counterparties
        }

        # Store updated batch
        store_batch_record(updated_batch)

        {:ok, updated_batch}
      rescue
        error ->
          {:error, error}
      end
    end

    case :mnesia.transaction(transaction) do
      {:atomic, {:ok, updated_batch}} ->
        Logger.info("Executed atomic batch #{batch.batch_id} successfully")
        publish_batch_event(updated_batch, :completed)
        {:ok, updated_batch}

      {:atomic, {:error, reason}} ->
        failed_batch = %{batch | status: :failed, error_reason: reason}
        update_batch(failed_batch)
        {:error, reason}

      {:aborted, reason} ->
        failed_batch = %{batch | status: :failed, error_reason: reason}
        update_batch(failed_batch)
        {:error, reason}
    end
  end

  defp execute_sequential_batch(batch) do
    # Execute trades one by one, stopping on first failure
    {results, counterparties} =
      Enum.reduce_while(batch.items, {[], []}, fn item, {acc_results, acc_counterparties} ->
        case execute_trade_item(item, batch.user_pubkey) do
          {:ok, counterparty} ->
            new_counterparties =
              if counterparty, do: [counterparty | acc_counterparties], else: acc_counterparties

            {:cont, {[:ok | acc_results], new_counterparties}}

          {:error, reason} ->
            {:halt, {[{:error, reason} | acc_results], acc_counterparties}}
        end
      end)

    if Enum.all?(results, &(&1 == :ok)) do
      updated_batch = %{
        batch
        | status: :completed,
          executed_at: DateTime.utc_now(),
          counterparties: Enum.uniq(counterparties)
      }

      update_batch(updated_batch)
      Logger.info("Executed sequential batch #{batch.batch_id} successfully")
      publish_batch_event(updated_batch, :completed)
      {:ok, updated_batch}
    else
      failed_batch = %{batch | status: :failed, error_reason: :partial_execution}
      update_batch(failed_batch)
      {:error, :partial_execution}
    end
  end

  defp execute_trade_item(item, user_pubkey) do
    # Create individual trade record
    trade_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

    trade_record = {
      :user_trades,
      trade_id,
      user_pubkey,
      item.card_id,
      Atom.to_string(item.trade_type),
      item.quantity,
      item.price,
      item.price * item.quantity,
      # counterparty_pubkey - will be filled when matched
      nil,
      # For batch trades, we assume immediate execution
      "completed",
      DateTime.utc_now(),
      DateTime.utc_now(),
      # nostr_event_id
      nil
    }

    :mnesia.write(trade_record)

    # Update user collections for completed trade
    case item.trade_type do
      :buy ->
        Logger.info("Executing buy trade for #{item.card_id} x#{item.quantity} at #{item.price}")
        Cards.add_to_user_collection(user_pubkey, item.card_id, item.quantity, item.price)

      :sell ->
        Logger.info("Executing sell trade for #{item.card_id} x#{item.quantity} at #{item.price}")
        Cards.remove_from_user_collection(user_pubkey, item.card_id, item.quantity)
    end

    # Return mock counterparty for simulation
    mock_counterparty = generate_mock_counterparty()
    {:ok, mock_counterparty}
  end

  defp get_current_quantity(user_cards, card_id) do
    case Enum.find(user_cards, &(&1.card_id == card_id)) do
      nil -> 0
      card -> card.quantity
    end
  end

  defp store_batch(batch) do
    transaction = fn ->
      store_batch_record(batch)
    end

    case :mnesia.transaction(transaction) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:error, reason}
    end
  end

  defp store_batch_record(batch) do
    record = {
      :batch_trades,
      batch.batch_id,
      batch.user_pubkey,
      batch.items,
      batch.total_value,
      batch.status,
      batch.created_at,
      batch.executed_at,
      batch.counterparties,
      batch.execution_method
    }

    :mnesia.write(record)
  end

  defp update_batch(batch) do
    store_batch(batch)
  end

  defp generate_mock_counterparty do
    counterparties = [
      "npub1trader1mockuser000000000000000",
      "npub1trader2mockuser000000000000000",
      "npub1trader3mockuser000000000000000",
      "npub1trader4mockuser000000000000000",
      "npub1trader5mockuser000000000000000"
    ]

    Enum.random(counterparties)
  end

  defp publish_batch_event(batch, event_type) do
    # Publish Nostr event about batch execution
    event_content = %{
      batch_id: batch.batch_id,
      event_type: event_type,
      items_count: length(batch.items),
      total_value: batch.total_value,
      execution_method: batch.execution_method,
      timestamp: DateTime.utc_now()
    }

    # This would use the Nostr client to publish the event
    Logger.info("Batch event: #{inspect(event_content)}")
  end
end
