defmodule SammelkartenWeb.PortfolioLive do
  @moduledoc """
  LiveView for authenticated users to manage their personal card collection and portfolio.

  This page handles:
  - Personal card collection display
  - Portfolio value calculations
  - Collection statistics and performance metrics
  - Nostr authentication requirement
  """

  use SammelkartenWeb, :live_view

  alias Sammelkarten.{Cards, Formatter}
  alias Sammelkarten.Nostr.User
  require Logger

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:page_title, "My Portfolio")
      |> assign(:current_user, nil)
      |> assign(:authenticated, false)
      |> assign(:collection, [])
      |> assign(:portfolio_stats, %{})
      |> assign(:loading, true)
      |> assign(:error_message, nil)
      |> assign(:search_term, "")
      |> assign(:search_results, [])
      |> assign(:show_search_dropdown, false)
      |> assign(:selected_card, nil)
      |> assign(:editing_item, nil)

    # Check if user is authenticated
    case get_nostr_user_from_session(session) do
      {:ok, user} ->
        socket =
          socket
          |> assign(:current_user, user)
          |> assign(:authenticated, true)

        # Subscribe to price updates
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Sammelkarten.PubSub, "price_updates")
        end

        # Load user's collection and portfolio data
        send(self(), :load_portfolio_data)

        {:ok, socket}

      {:error, :not_authenticated} ->
        # Show unauthenticated state
        socket =
          socket
          |> assign(:authenticated, false)
          |> assign(:current_user, nil)
          |> assign(:loading, false)

        {:ok, socket}
    end
  end

  @impl true
  def handle_info(:load_portfolio_data, socket) do
    if socket.assigns.authenticated do
      user_pubkey = socket.assigns.current_user.pubkey

      # Load user's collection
      collection = load_user_collection(user_pubkey)

      # Calculate portfolio statistics
      portfolio_stats = calculate_portfolio_stats(collection)

      socket =
        socket
        |> assign(:collection, collection)
        |> assign(:portfolio_stats, portfolio_stats)
        |> assign(:loading, false)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:price_update_completed, _update_info}, socket) do
    if socket.assigns.authenticated do
      # Recalculate portfolio when prices update
      user_pubkey = socket.assigns.current_user.pubkey
      collection = load_user_collection(user_pubkey)
      portfolio_stats = calculate_portfolio_stats(collection)

      socket =
        socket
        |> assign(:collection, collection)
        |> assign(:portfolio_stats, portfolio_stats)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:price_update, _card_id}, socket) do
    if socket.assigns.authenticated do
      # Recalculate portfolio when prices update
      user_pubkey = socket.assigns.current_user.pubkey
      collection = load_user_collection(user_pubkey)
      portfolio_stats = calculate_portfolio_stats(collection)

      socket =
        socket
        |> assign(:collection, collection)
        |> assign(:portfolio_stats, portfolio_stats)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_new_card", %{"value" => search_term}, socket) do
    if socket.assigns.authenticated do
      search_term = String.trim(search_term)

      if search_term == "" do
        socket =
          socket
          |> assign(:search_term, "")
          |> assign(:search_results, [])
          |> assign(:show_search_dropdown, false)

        {:noreply, socket}
      else
        # Search for cards matching the term
        search_results = search_available_cards(search_term)

        socket =
          socket
          |> assign(:search_term, search_term)
          |> assign(:search_results, search_results)
          |> assign(:show_search_dropdown, length(search_results) > 0)

        {:noreply, socket}
      end
    else
      socket = put_flash(socket, :error, "Authentication required")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_card", %{"card_id" => card_id}, socket) do
    if socket.assigns.authenticated do
      case Cards.get_card(card_id) do
        {:ok, card} ->
          socket =
            socket
            |> assign(:selected_card, card)
            |> assign(:search_term, card.name)
            |> assign(:show_search_dropdown, false)
            |> assign(:search_results, [])

          {:noreply, socket}

        {:error, _} ->
          socket = put_flash(socket, :error, "Card not found")
          {:noreply, socket}
      end
    else
      socket = put_flash(socket, :error, "Authentication required")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    socket =
      socket
      |> assign(:selected_card, nil)
      |> assign(:search_term, "")
      |> assign(:show_search_dropdown, false)
      |> assign(:search_results, [])

    {:noreply, socket}
  end

  @impl true
  def handle_event("add_selected_card", %{"quantity" => quantity_str}, socket) do
    if socket.assigns.authenticated and socket.assigns.selected_card do
      card = socket.assigns.selected_card

      case Integer.parse(quantity_str) do
        {quantity, _} when quantity > 0 ->
          user_pubkey = socket.assigns.current_user.pubkey

          case add_card_to_collection(user_pubkey, card.id, quantity) do
            {:ok, _} ->
              # Clear selection and reload collection data
              socket =
                socket
                |> assign(:selected_card, nil)
                |> assign(:search_term, "")
                |> assign(:show_search_dropdown, false)
                |> assign(:search_results, [])
                |> put_flash(:info, "#{quantity} #{card.name} card(s) added to collection")

              send(self(), :load_portfolio_data)
              {:noreply, socket}

            {:error, reason} ->
              socket = put_flash(socket, :error, "Failed to add card: #{reason}")
              {:noreply, socket}
          end

        _ ->
          socket = put_flash(socket, :error, "Please enter a valid quantity")
          {:noreply, socket}
      end
    else
      socket = put_flash(socket, :error, "Please select a card first")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "add_to_collection",
        %{"card_id" => card_id, "quantity" => quantity_str},
        socket
      ) do
    if socket.assigns.authenticated do
      user_pubkey = socket.assigns.current_user.pubkey

      case Integer.parse(quantity_str) do
        {quantity, _} when quantity > 0 ->
          case add_card_to_collection(user_pubkey, card_id, quantity) do
            {:ok, _} ->
              # Reload collection data
              send(self(), :load_portfolio_data)

              socket = put_flash(socket, :info, "Card added to collection successfully")
              {:noreply, socket}

            {:error, reason} ->
              socket = put_flash(socket, :error, "Failed to add card: #{reason}")
              {:noreply, socket}
          end

        _ ->
          socket = put_flash(socket, :error, "Please enter a valid quantity")
          {:noreply, socket}
      end
    else
      socket = put_flash(socket, :error, "Authentication required")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("edit_quantity", %{"collection_id" => collection_id}, socket) do
    if socket.assigns.authenticated do
      # Find the collection item to edit
      collection_item = Enum.find(socket.assigns.collection, fn item -> item.id == collection_id end)
      
      if collection_item do
        socket = assign(socket, :editing_item, collection_item)
        {:noreply, socket}
      else
        socket = put_flash(socket, :error, "Collection item not found")
        {:noreply, socket}
      end
    else
      socket = put_flash(socket, :error, "Authentication required")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    socket = assign(socket, :editing_item, nil)
    {:noreply, socket}
  end

  @impl true
  def handle_event("save_quantity", %{"new_quantity" => quantity_str}, socket) do
    if socket.assigns.authenticated and socket.assigns.editing_item do
      collection_id = socket.assigns.editing_item.id
      user_pubkey = socket.assigns.current_user.pubkey

      case Integer.parse(quantity_str) do
        {quantity, _} when quantity > 0 ->
          case update_collection_quantity(user_pubkey, collection_id, quantity) do
            {:ok, _} ->
              # Reload collection data
              send(self(), :load_portfolio_data)

              socket = 
                socket
                |> assign(:editing_item, nil)
                |> put_flash(:info, "Quantity updated successfully")
              {:noreply, socket}

            {:error, reason} ->
              socket = put_flash(socket, :error, "Failed to update quantity: #{reason}")
              {:noreply, socket}
          end

        {0, _} ->
          # Remove if quantity is 0
          handle_event("remove_from_collection", %{"collection_id" => collection_id}, socket)

        _ ->
          socket = put_flash(socket, :error, "Please enter a valid quantity")
          {:noreply, socket}
      end
    else
      socket = put_flash(socket, :error, "Please select an item to edit")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_from_collection", %{"collection_id" => collection_id}, socket) do
    if socket.assigns.authenticated do
      user_pubkey = socket.assigns.current_user.pubkey

      case remove_card_from_collection(user_pubkey, collection_id) do
        {:ok, _} ->
          # Reload collection data
          send(self(), :load_portfolio_data)

          socket = put_flash(socket, :info, "Card removed from collection")
          {:noreply, socket}

        {:error, reason} ->
          socket = put_flash(socket, :error, "Failed to remove card: #{reason}")
          {:noreply, socket}
      end
    else
      socket = put_flash(socket, :error, "Authentication required")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "update_quantity",
        %{"collection_id" => collection_id, "new_quantity" => quantity_str},
        socket
      ) do
    if socket.assigns.authenticated do
      user_pubkey = socket.assigns.current_user.pubkey

      case Integer.parse(quantity_str) do
        {quantity, _} when quantity > 0 ->
          case update_collection_quantity(user_pubkey, collection_id, quantity) do
            {:ok, _} ->
              # Reload collection data
              send(self(), :load_portfolio_data)

              socket = put_flash(socket, :info, "Quantity updated successfully")
              {:noreply, socket}

            {:error, reason} ->
              socket = put_flash(socket, :error, "Failed to update quantity: #{reason}")
              {:noreply, socket}
          end

        {0, _} ->
          # Remove if quantity is 0
          handle_event("remove_from_collection", %{"collection_id" => collection_id}, socket)

        _ ->
          socket = put_flash(socket, :error, "Please enter a valid quantity")
          {:noreply, socket}
      end
    else
      socket = put_flash(socket, :error, "Authentication required")
      {:noreply, socket}
    end
  end

  # Private helper functions

  defp get_nostr_user_from_session(session) do
    # Get user from session data directly
    case session do
      %{"nostr_authenticated" => true, "nostr_user" => user_data} when user_data != nil ->
        try do
          # Convert map back to User struct
          user = struct(Sammelkarten.Nostr.User, atomize_keys(user_data))
          {:ok, user}
        rescue
          e ->
            Logger.error("Failed to load user from session: #{inspect(e)}")
            {:error, :invalid_user_data}
        end

      _ ->
        {:error, :not_authenticated}
    end
  end

  # Helper function to convert string keys to atoms
  defp atomize_keys(map) when is_map(map) do
    for {key, val} <- map, into: %{} do
      cond do
        is_binary(key) -> {String.to_existing_atom(key), val}
        is_atom(key) -> {key, val}
        true -> {key, val}
      end
    end
  end

  defp load_user_collection(user_pubkey) do
    try do
      # Query user's collection from Mnesia
      transaction = fn ->
        :mnesia.match_object({:user_collections, :_, user_pubkey, :_, :_, :_, :_, :_})
      end

      case :mnesia.transaction(transaction) do
        {:atomic, collection_records} ->
          # Enrich collection records with current card data
          Enum.map(collection_records, fn {_, id, _, card_id, quantity, acquired_at,
                                           acquisition_price, notes} ->
            case Cards.get_card(card_id) do
              {:ok, card} ->
                current_value = card.current_price * quantity
                acquisition_total = acquisition_price * quantity
                profit_loss = current_value - acquisition_total

                profit_loss_percentage =
                  if acquisition_total > 0, do: profit_loss / acquisition_total * 100, else: 0

                %{
                  id: id,
                  card: card,
                  quantity: quantity,
                  acquired_at: acquired_at,
                  acquisition_price: acquisition_price,
                  acquisition_total: acquisition_total,
                  current_value: current_value,
                  profit_loss: profit_loss,
                  profit_loss_percentage: profit_loss_percentage,
                  notes: notes
                }

              {:error, _} ->
                nil
            end
          end)
          |> Enum.filter(fn item -> item != nil end)
          |> Enum.sort_by(fn item -> item.current_value end, :desc)

        {:aborted, reason} ->
          Logger.error("Failed to load user collection: #{inspect(reason)}")
          []
      end
    rescue
      e ->
        Logger.error("Error loading user collection: #{inspect(e)}")
        []
    end
  end

  defp calculate_portfolio_stats(collection) do
    if Enum.empty?(collection) do
      %{
        total_value: 0,
        total_cards: 0,
        unique_cards: 0,
        total_invested: 0,
        total_profit_loss: 0,
        profit_loss_percentage: 0,
        top_performer: nil,
        worst_performer: nil
      }
    else
      total_value = Enum.sum(Enum.map(collection, & &1.current_value))
      total_cards = Enum.sum(Enum.map(collection, & &1.quantity))
      unique_cards = length(collection)
      total_invested = Enum.sum(Enum.map(collection, & &1.acquisition_total))
      total_profit_loss = total_value - total_invested

      profit_loss_percentage =
        if total_invested > 0, do: total_profit_loss / total_invested * 100, else: 0

      top_performer = Enum.max_by(collection, & &1.profit_loss_percentage, fn -> nil end)
      worst_performer = Enum.min_by(collection, & &1.profit_loss_percentage, fn -> nil end)

      %{
        total_value: total_value,
        total_cards: total_cards,
        unique_cards: unique_cards,
        total_invested: total_invested,
        total_profit_loss: total_profit_loss,
        profit_loss_percentage: profit_loss_percentage,
        top_performer: top_performer,
        worst_performer: worst_performer
      }
    end
  end

  defp add_card_to_collection(user_pubkey, card_id, quantity) do
    case Cards.get_card(card_id) do
      {:ok, card} ->
        collection_id = generate_collection_id()

        record = {
          :user_collections,
          collection_id,
          user_pubkey,
          card_id,
          quantity,
          DateTime.utc_now(),
          # Use current price as acquisition price
          card.current_price,
          # No notes initially
          nil
        }

        transaction = fn ->
          :mnesia.write(record)
        end

        case :mnesia.transaction(transaction) do
          {:atomic, :ok} ->
            Logger.info(
              "Added #{quantity} #{card.name} cards to user #{User.short_pubkey(%{pubkey: user_pubkey})} collection"
            )

            {:ok, collection_id}

          {:aborted, reason} ->
            Logger.error("Failed to add card to collection: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp remove_card_from_collection(user_pubkey, collection_id) do
    transaction = fn ->
      case :mnesia.read({:user_collections, collection_id}) do
        [{_, ^collection_id, ^user_pubkey, _, _, _, _, _}] ->
          :mnesia.delete({:user_collections, collection_id})

        [] ->
          {:error, :not_found}

        _ ->
          {:error, :unauthorized}
      end
    end

    case :mnesia.transaction(transaction) do
      {:atomic, :ok} ->
        {:ok, collection_id}

      {:atomic, {:error, reason}} ->
        {:error, reason}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  defp update_collection_quantity(user_pubkey, collection_id, new_quantity) do
    transaction = fn ->
      case :mnesia.read({:user_collections, collection_id}) do
        [{_, ^collection_id, ^user_pubkey, card_id, _, acquired_at, acquisition_price, notes}] ->
          updated_record = {
            :user_collections,
            collection_id,
            user_pubkey,
            card_id,
            new_quantity,
            acquired_at,
            acquisition_price,
            notes
          }

          :mnesia.write(updated_record)

        [] ->
          {:error, :not_found}

        _ ->
          {:error, :unauthorized}
      end
    end

    case :mnesia.transaction(transaction) do
      {:atomic, :ok} ->
        {:ok, collection_id}

      {:atomic, {:error, reason}} ->
        {:error, reason}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  defp generate_collection_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp search_available_cards(search_term) do
    search_term_lower = String.downcase(search_term)

    case Cards.list_cards() do
      {:ok, cards} ->
        cards
        |> Enum.filter(fn card ->
          String.contains?(String.downcase(card.name), search_term_lower) or
            String.contains?(String.downcase(card.description || ""), search_term_lower) or
            String.contains?(String.downcase(card.rarity), search_term_lower)
        end)
        # Limit to 5 results for UI
        |> Enum.take(5)

      {:error, _} ->
        []
    end
  end
end
