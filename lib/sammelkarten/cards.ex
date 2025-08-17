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
          {:cards, card.id, card.name, card.slug, card.image_path, card.current_price,
           card.price_change_24h, card.price_change_percentage, card.rarity, card.description,
           card.last_updated}
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
  Get a card by slug.
  """
  def get_card_by_slug(slug) do
    match_spec = [{{:cards, :_, :_, slug, :_, :_, :_, :_, :_, :_, :_}, [], [:"$_"]}]

    case :mnesia.transaction(fn -> :mnesia.select(:cards, match_spec) end) do
      {:atomic, []} ->
        {:error, :not_found}

      {:atomic, [record]} ->
        {:ok, card_from_record(record)}

      {:aborted, reason} ->
        Logger.error("Failed to get card by slug: #{inspect(reason)}")
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
            {:cards, updated_card.id, updated_card.name, updated_card.slug,
             updated_card.image_path, updated_card.current_price, updated_card.price_change_24h,
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
         {:cards, id, name, slug, image_path, current_price, price_change_24h,
          price_change_percentage, rarity, description, last_updated}
       ) do
    %Card{
      id: id,
      name: name,
      slug: slug,
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
  Get multiple cards by their IDs.
  """
  def get_cards_by_ids(card_ids) when is_list(card_ids) do
    case :mnesia.transaction(fn ->
           Enum.map(card_ids, fn id ->
             case :mnesia.read({:cards, id}) do
               [record] -> card_from_record(record)
               [] -> nil
             end
           end)
         end) do
      {:atomic, results} ->
        Enum.reject(results, &is_nil/1)

      {:aborted, reason} ->
        Logger.error("Failed to get cards by IDs: #{inspect(reason)}")
        []
    end
  end

  @doc """
  Get all cards owned by a user.
  """
  def get_user_cards(user_pubkey) do
    match_spec = [{{:user_collections, :_, user_pubkey, :"$3", :"$4", :"$5", :_}, [], [:"$_"]}]

    case :mnesia.transaction(fn -> :mnesia.select(:user_collections, match_spec) end) do
      {:atomic, records} ->
        Enum.map(records, &user_card_from_record/1)

      {:aborted, reason} ->
        Logger.error("Failed to get user cards: #{inspect(reason)}")
        []
    end
  end

  @doc """
  Add cards to a user's collection.
  """
  def add_to_user_collection(user_pubkey, card_id, quantity, purchase_price) do
    collection_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

    # Check if user already owns this card
    existing_record = find_user_card_record(user_pubkey, card_id)

    transaction_result =
      :mnesia.transaction(fn ->
        case existing_record do
          nil ->
            # Create new collection entry
            record = {
              :user_collections,
              collection_id,
              user_pubkey,
              card_id,
              quantity,
              purchase_price,
              DateTime.utc_now()
            }

            :mnesia.write(record)

          {_, existing_id, _, _, existing_quantity, existing_price, _} ->
            # Update existing entry with averaged price
            new_quantity = existing_quantity + quantity
            avg_price = (existing_price * existing_quantity + purchase_price * quantity) / new_quantity

            updated_record = {
              :user_collections,
              existing_id,
              user_pubkey,
              card_id,
              new_quantity,
              avg_price,
              DateTime.utc_now()
            }

            :mnesia.write(updated_record)
        end
      end)

    case transaction_result do
      {:atomic, :ok} ->
        Logger.info("Added #{quantity} of #{card_id} to #{user_pubkey}'s collection")
        :ok

      {:aborted, reason} ->
        Logger.error("Failed to add to user collection: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Remove cards from a user's collection.
  """
  def remove_from_user_collection(user_pubkey, card_id, quantity) do
    existing_record = find_user_card_record(user_pubkey, card_id)

    case existing_record do
      nil ->
        {:error, :card_not_owned}

      {_, _record_id, _, _, existing_quantity, _price, _} when existing_quantity < quantity ->
        {:error, :insufficient_quantity}

      {_, record_id, _, _, existing_quantity, price, _} ->
        transaction_result =
          :mnesia.transaction(fn ->
            if existing_quantity == quantity do
              # Remove the entire record
              :mnesia.delete({:user_collections, record_id})
            else
              # Update with reduced quantity
              new_quantity = existing_quantity - quantity

              updated_record = {
                :user_collections,
                record_id,
                user_pubkey,
                card_id,
                new_quantity,
                price,
                DateTime.utc_now()
              }

              :mnesia.write(updated_record)
            end
          end)

        case transaction_result do
          {:atomic, :ok} ->
            Logger.info("Removed #{quantity} of #{card_id} from #{user_pubkey}'s collection")
            :ok

          {:aborted, reason} ->
            Logger.error("Failed to remove from user collection: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp find_user_card_record(user_pubkey, card_id) do
    match_spec = [{{:user_collections, :_, user_pubkey, card_id, :_, :_, :_}, [], [:"$_"]}]

    case :mnesia.transaction(fn -> :mnesia.select(:user_collections, match_spec) end) do
      {:atomic, [record]} -> record
      {:atomic, []} -> nil
      {:aborted, _} -> nil
    end
  end

  defp user_card_from_record({:user_collections, _id, user_pubkey, card_id, quantity, purchase_price, updated_at}) do
    %{
      user_pubkey: user_pubkey,
      card_id: card_id,
      quantity: quantity,
      purchase_price: purchase_price,
      updated_at: updated_at
    }
  end

  @doc """
  Transfer cards from one user to another.
  """
  def transfer_card(from_pubkey, to_pubkey, card_id, quantity) do
    transaction_result =
      :mnesia.transaction(fn ->
        # Remove from sender
        case remove_from_user_collection(from_pubkey, card_id, quantity) do
          :ok ->
            # Get current market price for transfer
            case get_card(card_id) do
              {:ok, card} ->
                # Add to receiver at current market price
                add_to_user_collection(to_pubkey, card_id, quantity, card.current_price)

              {:error, reason} ->
                {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end
      end)

    case transaction_result do
      {:atomic, :ok} ->
        Logger.info("Transferred #{quantity} of #{card_id} from #{from_pubkey} to #{to_pubkey}")
        :ok

      {:atomic, {:error, reason}} ->
        {:error, reason}

      {:aborted, reason} ->
        Logger.error("Failed to transfer card: #{inspect(reason)}")
        {:error, reason}
    end
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
