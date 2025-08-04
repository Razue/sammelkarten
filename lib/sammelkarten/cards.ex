defmodule Sammelkarten.Cards do
  @moduledoc """
  Context module for managing cards and price history.

  This module provides the API for:
  - Creating, reading, updating, and deleting cards
  - Managing price history
  - Querying card data with filters and sorting
  """

  alias Sammelkarten.Card
  alias Sammelkarten.PriceHistory

  require Logger

  @doc """
  Create a new card and save it to Mnesia.
  """
  def create_card(attrs \\ %{}) do
    card = Card.new(attrs)

    transaction_result =
      :mnesia.transaction(fn ->
        :mnesia.write(
          {:cards, card.id, card.name, card.image_path, card.current_price, card.price_change_24h,
           card.price_change_percentage, card.rarity, card.description, card.last_updated}
        )
      end)

    case transaction_result do
      {:atomic, :ok} ->
        {:ok, card}

      {:aborted, reason} ->
        Logger.error("Failed to create card: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get a card by ID.
  """
  def get_card(id) do
    case :mnesia.transaction(fn -> :mnesia.read({:cards, id}) end) do
      {:atomic, []} ->
        {:error, :not_found}

      {:atomic, [record]} ->
        {:ok, card_from_record(record)}

      {:aborted, reason} ->
        Logger.error("Failed to get card: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get all cards.
  """
  def list_cards do
    case :mnesia.transaction(fn -> :mnesia.select(:cards, [{:_, [], [:"$_"]}]) end) do
      {:atomic, records} ->
        cards = Enum.map(records, &card_from_record/1)
        {:ok, cards}

      {:aborted, reason} ->
        Logger.error("Failed to list cards: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Update a card's price and create price history entry.
  """
  def update_card_price(card_id, new_price) do
    with {:ok, card} <- get_card(card_id) do
      # Calculate price changes
      price_change_24h = new_price - card.current_price

      price_change_percentage =
        if card.current_price > 0 do
          price_change_24h / card.current_price * 100.0
        else
          0.0
        end

      # Update card
      updated_card = %{
        card
        | current_price: new_price,
          price_change_24h: price_change_24h,
          price_change_percentage: price_change_percentage,
          last_updated: DateTime.utc_now()
      }

      # Save updated card and create price history entry
      transaction_result =
        :mnesia.transaction(fn ->
          # Update card
          :mnesia.write(
            {:cards, updated_card.id, updated_card.name, updated_card.image_path,
             updated_card.current_price, updated_card.price_change_24h,
             updated_card.price_change_percentage, updated_card.rarity, updated_card.description,
             updated_card.last_updated}
          )

          # Create price history entry
          price_history =
            PriceHistory.new(%{
              card_id: card_id,
              price: new_price,
              # Simulated volume
              volume: :rand.uniform(1000)
            })

          :mnesia.write(
            {:price_history, price_history.id, price_history.card_id, price_history.price,
             price_history.timestamp, price_history.volume}
          )
        end)

      case transaction_result do
        {:atomic, :ok} ->
          {:ok, updated_card}

        {:aborted, reason} ->
          Logger.error("Failed to update card price: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Get price history for a card.
  """
  def get_price_history(card_id, limit \\ 100) do
    match_spec = [{{:price_history, :_, card_id, :_, :_, :_}, [], [:"$_"]}]

    case :mnesia.transaction(fn -> :mnesia.select(:price_history, match_spec, limit, :read) end) do
      {:atomic, result} ->
        process_price_history_result(result)

      {:aborted, reason} ->
        Logger.error("Failed to get price history: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_price_history_result({records, _continuation}) when is_list(records) do
    {:ok, convert_and_sort_price_records(records)}
  end

  defp process_price_history_result(records) when is_list(records) do
    {:ok, convert_and_sort_price_records(records)}
  end

  defp process_price_history_result(:"$end_of_table") do
    {:ok, []}
  end

  defp convert_and_sort_price_records(records) do
    records
    |> Enum.map(&price_history_from_record/1)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  # Private helpers
  defp card_from_record(
         {:cards, id, name, image_path, current_price, price_change_24h, price_change_percentage,
          rarity, description, last_updated}
       ) do
    %Card{
      id: id,
      name: name,
      image_path: image_path,
      current_price: current_price,
      price_change_24h: price_change_24h,
      price_change_percentage: price_change_percentage,
      rarity: rarity,
      description: description,
      last_updated: last_updated
    }
  end

  defp price_history_from_record({:price_history, id, card_id, price, timestamp, volume}) do
    %PriceHistory{
      id: id,
      card_id: card_id,
      price: price,
      timestamp: timestamp,
      volume: volume
    }
  end

  @doc """
  Delete a card and all its price history.
  """
  def delete_card(card_id) do
    transaction_result =
      :mnesia.transaction(fn ->
        # Delete card
        :mnesia.delete({:cards, card_id})

        # Delete all price history for this card
        match_spec = [{{:price_history, :"$1", card_id, :_, :_, :_}, [], [:"$1"]}]
        price_history_ids = :mnesia.select(:price_history, match_spec)

        Enum.each(price_history_ids, fn id ->
          :mnesia.delete({:price_history, id})
        end)
      end)

    case transaction_result do
      {:atomic, :ok} ->
        :ok

      {:aborted, reason} ->
        Logger.error("Failed to delete card: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
