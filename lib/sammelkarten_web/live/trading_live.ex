defmodule SammelkartenWeb.TradingLive do
  import SammelkartenWeb.TradingLive.ActiveOffersTab, only: [active_offers_tab: 1]
  import SammelkartenWeb.TradingLive.MyOffersTab, only: [my_offers_tab: 1]
  import SammelkartenWeb.TradingLive.TradeHistoryTab, only: [trade_history_tab: 1]
  import SammelkartenWeb.TradingLive.CreateOfferTab, only: [create_offer_tab: 1]
  import SammelkartenWeb.TradingLive.ExchangesTab, only: [exchanges_tab: 1]

  @moduledoc """
  LiveView for peer-to-peer card trading via Nostr events.

  This page handles:
  - Real-time trade offer broadcasting and discovery
  - Trade matching between buyers and sellers
  - Trade execution and ownership transfers
  - Trading history and reputation tracking
  - Nostr authentication requirement
  """

  use SammelkartenWeb, :live_view

  alias Sammelkarten.{Cards, Formatter}
  alias Sammelkarten.Nostr.{User, Event, Client}
  require Logger

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:page_title, "P2P Trading")
      |> assign(:current_user, nil)
      |> assign(:authenticated, false)
      |> assign(:active_offers, [])
      |> assign(:my_offers, [])
      |> assign(:trade_history, [])
      |> assign(:available_cards, [])
      |> assign(:selected_card, nil)
      |> assign(:offer_form, %{"card_id" => "", "price" => "", "quantity" => "1"})
      |> assign(:loading, true)
      |> assign(:error_message, nil)
      # "all", "buy", "sell"
      |> assign(:filter_type, "all")
      # "newest", "price_low", "price_high"
      |> assign(:sort_by, "newest")
      # Default tab for trading
      |> assign(:active_tab, "active_offers")
      # Exchange-specific data
      |> assign(:exchange_offers, [])
      # Search functionality
      |> assign(:search_query, "")
      # Offer form state
      |> assign(:selected_offer_type, nil)
      # Exchange form fields
      |> assign(:exchange_form, %{
        "offering_card_id" => "",
        "wanted_type" => "specific",
        "wanted_card_ids" => [],
        "quantity" => "1"
      })
      # Form visibility
      |> assign(:show_create_form, false)
      |> assign(:show_exchange_form, false)

    # Check if user is authenticated
    case get_nostr_user_from_session(session) do
      {:ok, user} ->
        socket =
          socket
          |> assign(:current_user, user)
          |> assign(:authenticated, true)

        # Subscribe to price updates and trade events
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Sammelkarten.PubSub, "price_updates")
          Phoenix.PubSub.subscribe(Sammelkarten.PubSub, "trade_events")
        end

        # Load trading data
        send(self(), :load_trading_data)

        {:ok, socket}

      {:error, :not_authenticated} ->
        # Show reduced functionality without authentication
        socket =
          socket
          |> assign(:authenticated, false)
          |> assign(:current_user, nil)
          |> assign(:loading, true)

        # Load only active offers for non-authenticated users
        if connected?(socket) do
          send(self(), :load_limited_trading_data)
        else
          send(self(), :load_limited_trading_data)
        end

        {:ok, socket}
    end
  end

  @impl true
  def handle_info(:load_trading_data, socket) do
    if socket.assigns.authenticated do
      user_pubkey = socket.assigns.current_user.pubkey
      Logger.info("Loading trading data for user #{User.short_pubkey(%{pubkey: user_pubkey})}")

      # Load active trade offers (including user's own offers)
      active_offers = load_active_offers(user_pubkey)

      # Load user's own offers
      my_offers = load_user_offers(user_pubkey)

      # Load trade history
      trade_history = load_trade_history(user_pubkey)

      # Load exchange offers
      exchange_offers = load_exchange_offers(user_pubkey)

      # Load available cards for the create offer form
      available_cards =
        case Cards.list_cards() do
          {:ok, cards} -> cards
          {:error, _} -> []
        end

      # Load user's portfolio cards for exchange offers
      portfolio_cards = load_user_portfolio_cards(user_pubkey)

      socket =
        socket
        |> assign(:active_offers, active_offers)
        |> assign(:my_offers, my_offers)
        |> assign(:trade_history, trade_history)
        |> assign(:exchange_offers, exchange_offers)
        |> assign(:available_cards, available_cards)
        |> assign(:portfolio_cards, portfolio_cards)
        |> assign(:loading, false)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:load_limited_trading_data, socket) do
    # Load only active offers for non-authenticated users
    active_offers = load_active_offers(nil)

    # Load available cards for display purposes
    available_cards =
      case Cards.list_cards() do
        {:ok, cards} -> cards
        {:error, _} -> []
      end

    socket =
      socket
      |> assign(:active_offers, active_offers)
      |> assign(:my_offers, [])
      |> assign(:trade_history, [])
      |> assign(:exchange_offers, [])
      |> assign(:available_cards, available_cards)
      |> assign(:portfolio_cards, [])
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:price_update, _card_id}, socket) do
    if socket.assigns.authenticated do
      # Reload trading data when prices update
      send(self(), :load_trading_data)
    else
      # Reload limited data for non-authenticated users
      send(self(), :load_limited_trading_data)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:price_update_completed, _stats}, socket) do
    # Handle price update completion - we can ignore this or use it for UI feedback
    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_trade_offer, offer}, socket) do
    if socket.assigns.authenticated do
      # Add new offer to active offers if it's not from current user
      current_offers = socket.assigns.active_offers

      if offer.user_pubkey != socket.assigns.current_user.pubkey do
        updated_offers =
          [offer | current_offers]
          |> sort_offers(socket.assigns.sort_by)
          |> filter_offers(socket.assigns.filter_type)

        socket = assign(socket, :active_offers, updated_offers)
        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    socket = assign(socket, :active_tab, tab)
    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    socket = assign(socket, :search_query, query)
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_offer_type", %{"type" => offer_type}, socket) do
    socket = assign(socket, :selected_offer_type, offer_type)
    {:noreply, socket}
  end

  @impl true
  def handle_event("show_create_form", _params, socket) do
    socket = assign(socket, :show_create_form, true)
    {:noreply, socket}
  end

  @impl true
  def handle_event("hide_create_form", _params, socket) do
    socket =
      socket
      |> assign(:show_create_form, false)
      |> assign(:selected_offer_type, nil)
      |> assign(:offer_form, %{"card_id" => "", "price" => "", "quantity" => "1"})

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_exchange_form", _params, socket) do
    socket = assign(socket, :show_exchange_form, true)
    {:noreply, socket}
  end

  @impl true
  def handle_event("hide_exchange_form", _params, socket) do
    socket =
      socket
      |> assign(:show_exchange_form, false)
      |> assign(:exchange_form, %{
        "offering_card_id" => "",
        "wanted_type" => "specific",
        "wanted_card_ids" => [],
        "quantity" => "1"
      })

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_form", params, socket) do
    # LiveView phx-change sends the entire form data
    # Extract the form fields we care about
    offer_form = %{
      "card_id" => params["card_id"] || "",
      "price" => params["price"] || "",
      "quantity" => params["quantity"] || "1"
    }

    socket = assign(socket, :offer_form, offer_form)
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_exchange_form", params, socket) do
    Logger.info("Exchange form update - params: #{inspect(params)}")

    # Extract exchange form fields
    wanted_card_ids =
      case params["wanted_card_ids"] do
        list when is_list(list) -> list
        string when is_binary(string) -> [string]
        _ -> []
      end

    exchange_form = %{
      "offering_card_id" => params["offering_card_id"] || "",
      "wanted_type" => params["wanted_type"] || "specific",
      "wanted_card_ids" => wanted_card_ids,
      "quantity" => params["quantity"] || "1"
    }

    Logger.info("Exchange form updated: #{inspect(exchange_form)}")

    socket = assign(socket, :exchange_form, exchange_form)
    {:noreply, socket}
  end

  @impl true
  def handle_event("create_offer", _params, socket) do
    if socket.assigns.authenticated do
      user_pubkey = socket.assigns.current_user.pubkey
      offer_type = socket.assigns.selected_offer_type
      offer_form = socket.assigns.offer_form

      card_id = offer_form["card_id"]
      price_str = offer_form["price"]
      quantity_str = offer_form["quantity"]

      # Validate that offer type is selected
      if offer_type == nil do
        socket = put_flash(socket, :error, "Please select Buy Order or Sell Order")
        {:noreply, socket}
      else
        with {price, _} <- Float.parse(price_str),
             {quantity, _} <- Integer.parse(quantity_str),
             true <- price > 0 and quantity > 0,
             true <- card_id != "",
             {:ok, _card} <- Cards.get_card(card_id) do
          # Convert price to cents for storage
          price_cents = round(price * 100)

          # Create trade offer event
          offer_data = %{
            card_id: card_id,
            offer_type: offer_type,
            price: price_cents,
            quantity: quantity,
            # 24 hours
            expires_at: DateTime.utc_now() |> DateTime.add(24 * 60 * 60) |> DateTime.to_unix()
          }

          event = Event.trade_offer(user_pubkey, offer_data)

          # Store offer locally and broadcast via Nostr
          case create_trade_offer(user_pubkey, card_id, offer_type, price_cents, quantity, event) do
            {:ok, _offer_id} ->
              # Broadcast event via Nostr
              Client.publish_event(event)

              # Reload trading data
              send(self(), :load_trading_data)

              socket =
                socket
                # |> put_flash(:info, "Trade offer created successfully")
                |> assign(:offer_form, %{"card_id" => "", "price" => "", "quantity" => "1"})
                |> assign(:selected_offer_type, nil)
                |> assign(:show_create_form, false)

              {:noreply, socket}

            {:error, reason} ->
              socket = put_flash(socket, :error, "Failed to create offer: #{reason}")
              {:noreply, socket}
          end
        else
          _ ->
            socket = put_flash(socket, :error, "Please enter valid price and quantity")
            {:noreply, socket}
        end
      end
    else
      socket = put_flash(socket, :error, "Authentication required")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("accept_offer", %{"offer_id" => offer_id}, socket) do
    if socket.assigns.authenticated do
      user_pubkey = socket.assigns.current_user.pubkey

      case execute_trade(offer_id, user_pubkey) do
        {:ok, trade_execution} ->
          # Create trade execution event
          execution_event = Event.trade_execution(user_pubkey, trade_execution)
          Client.publish_event(execution_event)

          # Reload trading data
          send(self(), :load_trading_data)

        # socket = put_flash(socket, :info, "Trade executed successfully!")
        # {:noreply, socket}

        {:error, reason} ->
          socket = put_flash(socket, :error, "Failed to execute trade: #{reason}")
          {:noreply, socket}
      end
    else
      socket = put_flash(socket, :error, "Authentication required")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_offer", %{"offer_id" => offer_id}, socket) do
    Logger.info("Cancel offer request - offer_id: #{offer_id}")

    if socket.assigns.authenticated do
      user_pubkey = socket.assigns.current_user.pubkey
      Logger.info("User attempting to cancel: #{User.short_pubkey(%{pubkey: user_pubkey})}")

      case cancel_trade_offer(offer_id, user_pubkey) do
        {:ok, _} ->
          # Reload trading data
          send(self(), :load_trading_data)

        # socket = put_flash(socket, :info, "Offer cancelled successfully")
        # {:noreply, socket}

        {:error, reason} ->
          socket = put_flash(socket, :error, "Failed to cancel offer: #{reason}")
          {:noreply, socket}
      end
    else
      socket = put_flash(socket, :error, "Authentication required")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("create_exchange", params, socket) do
    Logger.info("Exchange form submission - params: #{inspect(params)}")
    Logger.info("Exchange form state: #{inspect(socket.assigns.exchange_form)}")

    if socket.assigns.authenticated do
      user_pubkey = socket.assigns.current_user.pubkey
      exchange_form = socket.assigns.exchange_form

      offering_card_id = exchange_form["offering_card_id"]
      wanted_type = exchange_form["wanted_type"] || "specific"
      wanted_card_ids = exchange_form["wanted_card_ids"] || []
      quantity_str = exchange_form["quantity"]

      Logger.info(
        "Exchange creation attempt: offering=#{offering_card_id}, wanted_type=#{wanted_type}, wanted_cards=#{inspect(wanted_card_ids)}, qty=#{quantity_str}"
      )

      with {quantity, _} <- Integer.parse(quantity_str || ""),
           true <- quantity > 0,
           true <- offering_card_id != "",
           true <- valid_wanted_cards?(wanted_type, wanted_card_ids, offering_card_id),
           {:ok, _offering_card} <- Cards.get_card(offering_card_id) do
        Logger.info("Exchange validation passed, creating offer...")

        # Create exchange offer event (adapt to existing trade_offer format)
        offer_data = %{
          card_id: offering_card_id,
          offer_type: "exchange",
          # Exchange has no price
          price: 0,
          quantity: quantity,
          expires_at: DateTime.utc_now() |> DateTime.add(24 * 60 * 60) |> DateTime.to_unix(),
          # Add exchange-specific data as additional fields
          wanted_type: wanted_type,
          wanted_card_ids: wanted_card_ids
        }

        event = Event.trade_offer(user_pubkey, offer_data)

        # Store exchange offer locally and broadcast via Nostr
        case create_exchange_offer(
               user_pubkey,
               offering_card_id,
               wanted_type,
               wanted_card_ids,
               quantity,
               event
             ) do
          {:ok, _offer_id} ->
            # Broadcast event via Nostr
            Client.publish_event(event)

            # Reload trading data
            send(self(), :load_trading_data)

            socket =
              socket
              # |> put_flash(:info, "Exchange offer created successfully")
              |> assign(:exchange_form, %{
                "offering_card_id" => "",
                "wanted_type" => "specific",
                "wanted_card_ids" => [],
                "quantity" => "1"
              })
              |> assign(:show_exchange_form, false)

            {:noreply, socket}

          {:error, reason} ->
            socket = put_flash(socket, :error, "Failed to create exchange offer: #{reason}")
            {:noreply, socket}
        end
      else
        error ->
          Logger.error("Exchange validation failed: #{inspect(error)}")

          Logger.error(
            "Form data: offering=#{offering_card_id}, wanted_type=#{wanted_type}, wanted_cards=#{inspect(wanted_card_ids)}, qty=#{quantity_str}"
          )

          socket =
            put_flash(
              socket,
              :error,
              "Please select valid cards for exchange (offering card and wanted card must be different)"
            )

          {:noreply, socket}
      end
    else
      socket = put_flash(socket, :error, "Authentication required")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("filter_offers", %{"type" => filter_type}, socket) do
    socket = assign(socket, :filter_type, filter_type)
    {:noreply, socket}
  end

  @impl true
  def handle_event("sort_offers", %{"by" => sort_by}, socket) do
    socket = assign(socket, :sort_by, sort_by)
    {:noreply, socket}
  end

  # Private helper functions

  defp valid_wanted_cards?(wanted_type, wanted_card_ids, offering_card_id) do
    case wanted_type do
      "open" ->
        true

      "specific" ->
        # Must have at least one wanted card and none should match offering card
        # Validate all wanted cards exist
        length(wanted_card_ids) > 0 and
          not Enum.member?(wanted_card_ids, offering_card_id) and
          Enum.all?(wanted_card_ids, fn card_id ->
            case Cards.get_card(card_id) do
              {:ok, _} -> true
              _ -> false
            end
          end)

      _ ->
        false
    end
  end

  defp get_nostr_user_from_session(session) do
    case session do
      %{"nostr_authenticated" => true, "nostr_user" => user_data} when user_data != nil ->
        try do
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

  defp atomize_keys(map) when is_map(map) do
    for {key, val} <- map, into: %{} do
      cond do
        is_binary(key) -> {String.to_existing_atom(key), val}
        is_atom(key) -> {key, val}
        true -> {key, val}
      end
    end
  end

  defp load_active_offers(_user_pubkey) do
    # Load all open offers from all users (both money offers and card exchanges)
    try do
      # Load money-based trade offers from user_trades
      money_transaction = fn ->
        # Get all open offers (buy/sell with money)
        :mnesia.match_object({:user_trades, :_, :_, :_, :_, :_, :_, :_, :_, "open", :_, :_, :_})
      end

      money_offers = case :mnesia.transaction(money_transaction) do
        {:atomic, trade_records} ->
          Logger.info("Found #{length(trade_records)} money-based active offers")

          trade_records
          |> Enum.map(&format_trade_offer/1)
          |> Enum.filter(fn offer -> offer != nil end)

        {:aborted, reason} ->
          Logger.error("Failed to load money offers: #{inspect(reason)}")
          []
      end

      # Load card exchange offers from market_maker
      exchange_offers = load_market_maker_exchange_offers()
      
      # Convert exchange offers to the same format as money offers for Active Offers tab
      exchange_offers_for_active = exchange_offers
      |> Enum.map(&convert_exchange_to_active_offer/1)
      |> Enum.filter(fn offer -> offer != nil end)

      # Combine both types
      all_offers = money_offers ++ exchange_offers_for_active
      Logger.info("Total active offers: #{length(all_offers)} (#{length(money_offers)} money + #{length(exchange_offers_for_active)} exchanges)")

      all_offers
      |> sort_offers("newest")

    rescue
      e ->
        Logger.error("Error loading active offers: #{inspect(e)}")
        []
    end
  end

  defp load_user_offers(user_pubkey) do
    try do
      transaction = fn ->
        :mnesia.match_object(
          {:user_trades, :_, user_pubkey, :_, :_, :_, :_, :_, :_, "open", :_, :_, :_}
        )
      end

      case :mnesia.transaction(transaction) do
        {:atomic, trade_records} ->
          Logger.info(
            "Found #{length(trade_records)} user trade records for #{User.short_pubkey(%{pubkey: user_pubkey})}"
          )

          trade_records
          |> Enum.map(&format_trade_offer/1)
          |> Enum.filter(fn offer -> offer != nil end)
          |> sort_offers("newest")

        {:aborted, reason} ->
          Logger.error("Failed to load user offers: #{inspect(reason)}")
          []
      end
    rescue
      e ->
        Logger.error("Error loading user offers: #{inspect(e)}")
        []
    end
  end

  defp load_trade_history(user_pubkey) do
    try do
      transaction = fn ->
        # Load completed trades where user was involved (either as seller or buyer)
        all_completed_trades =
          :mnesia.match_object(
            {:user_trades, :_, :_, :_, :_, :_, :_, :_, :_, "completed", :_, :_, :_}
          )

        # Filter to include only trades where the current user was involved
        Enum.filter(all_completed_trades, fn
          {_, _, seller_pubkey, _, _, _, _, _, buyer_pubkey, "completed", _, _, _} ->
            seller_pubkey == user_pubkey or buyer_pubkey == user_pubkey
        end)
      end

      case :mnesia.transaction(transaction) do
        {:atomic, trade_records} ->
          trade_records
          |> Enum.map(&format_trade_execution/1)
          |> Enum.filter(fn trade -> trade != nil end)
          |> Enum.sort_by(fn trade -> trade.completed_at end, :desc)

        {:aborted, reason} ->
          Logger.error("Failed to load trade history: #{inspect(reason)}")
          []
      end
    rescue
      e ->
        Logger.error("Error loading trade history: #{inspect(e)}")
        []
    end
  end

  defp format_trade_offer(
         {_, trade_id, user_pubkey, card_id, trade_type, quantity, price, total_value, _, "open",
          created_at, _, _}
       ) do
    case Cards.get_card(card_id) do
      {:ok, card} ->
        # Calculate expires_at as 24 hours from created_at
        expires_at = created_at |> DateTime.add(24 * 60 * 60)

        %{
          id: trade_id,
          user_pubkey: user_pubkey,
          user_short: User.short_pubkey(%{pubkey: user_pubkey}),
          card: card,
          offer_type: trade_type,
          price: price,
          quantity: quantity,
          created_at: created_at,
          expires_at: expires_at,
          total_value: total_value
        }

      {:error, _} ->
        nil
    end
  end

  defp format_trade_execution(
         {_, trade_id, seller_pubkey, card_id, trade_type, quantity, price, total_value,
          buyer_pubkey, "completed", _, completed_at, _}
       ) do
    case Cards.get_card(card_id) do
      {:ok, card} ->
        %{
          id: trade_id,
          seller_pubkey: seller_pubkey,
          seller_short: User.short_pubkey(%{pubkey: seller_pubkey}),
          buyer_pubkey: buyer_pubkey,
          buyer_short: User.short_pubkey(%{pubkey: buyer_pubkey}),
          card: card,
          offer_type: trade_type,
          price: price,
          quantity: quantity,
          executed_at: completed_at,
          completed_at: completed_at,
          total_value: total_value
        }

      {:error, _} ->
        nil
    end
  end

  defp create_trade_offer(user_pubkey, card_id, offer_type, price, quantity, _event) do
    trade_id = generate_trade_id()
    total_value = price * quantity
    created_at = DateTime.utc_now()

    # New table structure: {:user_trades, id, user_pubkey, card_id, trade_type, quantity, price, total_value, counterparty_pubkey, status, created_at, completed_at, nostr_event_id}
    record = {
      :user_trades,
      trade_id,
      user_pubkey,
      card_id,
      offer_type,
      quantity,
      price,
      total_value,
      # counterparty_pubkey - nil for open offers
      nil,
      "open",
      created_at,
      # completed_at - nil for open offers
      nil,
      # nostr_event_id - nil for now
      nil
    }

    transaction = fn ->
      :mnesia.write(record)
    end

    case :mnesia.transaction(transaction) do
      {:atomic, :ok} ->
        Logger.info(
          "Created #{offer_type} offer for #{quantity} #{card_id} at #{Formatter.format_german_price(price)} by #{User.short_pubkey(%{pubkey: user_pubkey})}"
        )

        {:ok, trade_id}

      {:aborted, reason} ->
        Logger.error("Failed to create trade offer: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp execute_trade(offer_id, buyer_pubkey) do
    transaction = fn ->
      case :mnesia.read({:user_trades, offer_id}) do
        [
          {_, ^offer_id, seller_pubkey, card_id, trade_type, quantity, price, total_value, nil,
           "open", created_at, nil, _}
        ] ->
          # Check if offer is still valid (24 hours from creation)
          expires_at = created_at |> DateTime.add(24 * 60 * 60)

          if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
            completed_at = DateTime.utc_now()

            # Determine actual seller and buyer based on offer type
            {actual_seller_pubkey, actual_buyer_pubkey} =
              case trade_type do
                # Offer creator is selling
                "sell" -> {seller_pubkey, buyer_pubkey}
                # Offer creator is buying
                "buy" -> {buyer_pubkey, seller_pubkey}
              end

            # Update offer to completed
            executed_record = {
              :user_trades,
              offer_id,
              actual_seller_pubkey,
              card_id,
              trade_type,
              quantity,
              price,
              total_value,
              # counterparty_pubkey
              actual_buyer_pubkey,
              "completed",
              created_at,
              completed_at,
              # nostr_event_id
              nil
            }

            # Write executed trade
            :mnesia.write(executed_record)

            # Create trade execution data for Nostr event
            execution_data = %{
              trade_id: offer_id,
              buyer_pubkey: actual_buyer_pubkey,
              seller_pubkey: actual_seller_pubkey,
              card_id: card_id,
              price: price,
              quantity: quantity,
              total_value: total_value
            }

            {:ok, execution_data}
          else
            {:error, :offer_expired}
          end

        [] ->
          {:error, :offer_not_found}

        _ ->
          {:error, :invalid_offer}
      end
    end

    case :mnesia.transaction(transaction) do
      {:atomic, {:ok, execution_data}} ->
        Logger.info(
          "Trade executed: #{buyer_pubkey} bought #{execution_data.quantity} #{execution_data.card_id} from #{execution_data.seller_pubkey}"
        )

        {:ok, execution_data}

      {:atomic, {:error, reason}} ->
        {:error, reason}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  defp cancel_trade_offer(offer_id, user_pubkey) do
    Logger.info(
      "Attempting to cancel offer #{offer_id} for user #{User.short_pubkey(%{pubkey: user_pubkey})}"
    )

    transaction = fn ->
      records = :mnesia.read({:user_trades, offer_id})
      Logger.info("Found records for offer #{offer_id}: #{inspect(records)}")

      case records do
        # Regular trade offer (counterparty_pubkey is nil)
        [{_, ^offer_id, ^user_pubkey, _, _, _, _, _, nil, "open", _, nil, _}] ->
          Logger.info("Cancelling regular trade offer")
          :mnesia.delete({:user_trades, offer_id})
          :ok

        # Exchange offer (counterparty_pubkey contains JSON data)
        [
          {_, ^offer_id, ^user_pubkey, _, "exchange", _, _, _, _counterparty_data, "open", _, nil,
           _}
        ] ->
          Logger.info("Cancelling exchange offer")
          :mnesia.delete({:user_trades, offer_id})
          :ok

        # Any other trade offer owned by user that's open
        [{_, ^offer_id, ^user_pubkey, _, _, _, _, _, _, "open", _, _, _}] ->
          Logger.info("Cancelling generic open offer")
          :mnesia.delete({:user_trades, offer_id})
          :ok

        [] ->
          Logger.error("Offer not found: #{offer_id}")
          {:error, :not_found}

        other ->
          Logger.error("Unauthorized or invalid offer state: #{inspect(other)}")
          {:error, :unauthorized}
      end
    end

    case :mnesia.transaction(transaction) do
      {:atomic, :ok} ->
        {:ok, offer_id}

      {:atomic, {:error, reason}} ->
        {:error, reason}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  defp filter_offers(offers, "all"), do: offers
  defp filter_offers(offers, "buy"), do: Enum.filter(offers, &(&1.offer_type == "buy"))
  defp filter_offers(offers, "sell"), do: Enum.filter(offers, &(&1.offer_type == "sell"))

  defp sort_offers(offers, "newest"), do: Enum.sort_by(offers, & &1.created_at, :desc)
  defp sort_offers(offers, "price_low"), do: Enum.sort_by(offers, & &1.price, :asc)
  defp sort_offers(offers, "price_high"), do: Enum.sort_by(offers, & &1.price, :desc)

  defp generate_trade_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  # Exchange-specific helper functions

  defp load_user_portfolio_cards(user_pubkey) do
    try do
      transaction = fn ->
        :mnesia.match_object({:user_collections, :_, user_pubkey, :_, :_, :_, :_, :_})
      end

      case :mnesia.transaction(transaction) do
        {:atomic, collection_records} ->
          Logger.info("Found #{length(collection_records)} cards in user portfolio")

          collection_records
          |> Enum.map(fn {_, _id, _user_pubkey, card_id, _quantity, _acquired_at,
                          _acquisition_price, _notes} ->
            case Cards.get_card(card_id) do
              {:ok, card} -> card
              {:error, _} -> nil
            end
          end)
          |> Enum.filter(fn card -> card != nil end)

        {:aborted, reason} ->
          Logger.error("Failed to load user portfolio cards: #{inspect(reason)}")
          []
      end
    rescue
      e ->
        Logger.error("Error loading user portfolio cards: #{inspect(e)}")
        []
    end
  end

  defp load_exchange_offers(_user_pubkey) do
    # Load all exchange offers from all users (both user-created and market_maker)
    try do
      # Load user-created exchange offers
      user_transaction = fn ->
        # Get all exchange offers (we'll store them with trade_type = "exchange")
        :mnesia.match_object(
          {:user_trades, :_, :_, :_, "exchange", :_, :_, :_, :_, "open", :_, :_, :_}
        )
      end

      user_exchange_offers = case :mnesia.transaction(user_transaction) do
        {:atomic, trade_records} ->
          Logger.info("Found #{length(trade_records)} user exchange offers")

          trade_records
          |> Enum.map(&format_exchange_offer/1)
          |> Enum.filter(fn offer -> offer != nil end)

        {:aborted, reason} ->
          Logger.error("Failed to load user exchange offers: #{inspect(reason)}")
          []
      end

      # Load market_maker exchange offers
      market_maker_offers = load_market_maker_exchange_offers()

      # Combine both sources
      all_offers = user_exchange_offers ++ market_maker_offers
      Logger.info("Total exchange offers: #{length(all_offers)} (#{length(user_exchange_offers)} user + #{length(market_maker_offers)} market_maker)")

      all_offers
      |> Enum.sort_by(fn offer -> offer.created_at end, :desc)

    rescue
      e ->
        Logger.error("Error loading exchange offers: #{inspect(e)}")
        []
    end
  end

  defp load_market_maker_exchange_offers do
    # Load exchange offers from market_maker's dynamic_card_exchanges table
    try do
      dynamic_exchanges = :mnesia.dirty_match_object(
        {:dynamic_card_exchanges, :_, :_, :_, :_, :_, :_, "open", :_, :_}
      )

      dynamic_exchanges
      |> Enum.map(&format_market_maker_exchange/1)
      |> Enum.filter(fn offer -> offer != nil end)
    rescue
      e ->
        Logger.error("Error loading market_maker exchange offers: #{inspect(e)}")
        []
    end
  end

  defp format_market_maker_exchange(
         {:dynamic_card_exchanges, trade_id, trader_pubkey, wanted_card_id, offered_card_id, offer_type, quantity, "open", created_at, expires_at}
       ) do
    # Convert market_maker exchange format to TradingLive exchange format
    case offer_type do
      "offer" ->
        # This trader is offering wanted_card_id
        case Cards.get_card(wanted_card_id) do
          {:ok, offering_card} ->
            %{
              id: trade_id,
              user_pubkey: trader_pubkey,
              user_short: String.slice(trader_pubkey, 0, 12) <> "...",
              offering_card: offering_card,
              wanted_type: if(offered_card_id, do: "specific", else: "open"),
              wanted_cards: if(offered_card_id, do: get_cards_safe([offered_card_id]), else: []),
              offer_type: "exchange",
              quantity: quantity,
              created_at: created_at,
              expires_at: expires_at
            }
          {:error, _} -> nil
        end

      "want" ->
        # This trader wants wanted_card_id and is offering offered_card_id (or any card if nil)
        if offered_card_id do
          case Cards.get_card(offered_card_id) do
            {:ok, offering_card} ->
              %{
                id: trade_id,
                user_pubkey: trader_pubkey,
                user_short: String.slice(trader_pubkey, 0, 12) <> "...",
                offering_card: offering_card,
                wanted_type: "specific",
                wanted_cards: get_cards_safe([wanted_card_id]),
                offer_type: "exchange",
                quantity: quantity,
                created_at: created_at,
                expires_at: expires_at
              }
            {:error, _} -> nil
          end
        else
          # This is a "want any card for wanted_card_id" - we need the offering card
          case Cards.get_card(wanted_card_id) do
            {:ok, wanted_card} ->
              %{
                id: trade_id,
                user_pubkey: trader_pubkey,
                user_short: String.slice(trader_pubkey, 0, 12) <> "...",
                offering_card: wanted_card,  # This is a bit confusing in the data model
                wanted_type: "open",
                wanted_cards: [],
                offer_type: "exchange",
                quantity: quantity,
                created_at: created_at,
                expires_at: expires_at
              }
            {:error, _} -> nil
          end
        end

      _ -> nil
    end
  end

  defp get_cards_safe(card_ids) do
    card_ids
    |> Enum.map(&Cards.get_card/1)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, card} -> card end)
  end

  defp convert_exchange_to_active_offer(exchange_offer) do
    # Convert exchange offer to format expected by ActiveOffersTab
    # Exchange offers have no monetary price, so we set price to 0
    %{
      id: exchange_offer.id,
      user_pubkey: exchange_offer.user_pubkey,
      user_short: exchange_offer.user_short,
      card: exchange_offer.offering_card,
      offer_type: "exchange",
      price: 0,  # No monetary price for exchanges
      quantity: exchange_offer.quantity,
      created_at: exchange_offer.created_at,
      expires_at: exchange_offer.expires_at,
      total_value: 0,  # No monetary value for exchanges
      # Add exchange-specific fields for display
      wanted_type: exchange_offer.wanted_type,
      wanted_cards: exchange_offer.wanted_cards
    }
  end

  defp create_exchange_offer(
         user_pubkey,
         offering_card_id,
         wanted_type,
         wanted_card_ids,
         quantity,
         _event
       ) do
    trade_id = generate_trade_id()
    created_at = DateTime.utc_now()

    # Encode wanted card information as JSON in counterparty_pubkey field
    wanted_data = %{
      type: wanted_type,
      card_ids: wanted_card_ids
    }

    wanted_data_json = Jason.encode!(wanted_data)

    # Store hash for price field (exchanges have no monetary price)
    wanted_hash = :erlang.phash2({wanted_type, wanted_card_ids})

    record = {
      :user_trades,
      trade_id,
      user_pubkey,
      offering_card_id,
      "exchange",
      quantity,
      # Store hash in price field
      wanted_hash,
      # total_value = 0 for exchanges
      0,
      # Store wanted cards data as JSON
      wanted_data_json,
      "open",
      created_at,
      # completed_at
      nil,
      # nostr_event_id
      nil
    }

    transaction = fn ->
      :mnesia.write(record)
    end

    case :mnesia.transaction(transaction) do
      {:atomic, :ok} ->
        wanted_desc =
          case wanted_type do
            "open" -> "any card"
            "specific" -> "specific cards: #{Enum.join(wanted_card_ids, ", ")}"
          end

        Logger.info(
          "Created exchange offer: #{quantity} #{offering_card_id} for #{wanted_desc} by #{User.short_pubkey(%{pubkey: user_pubkey})}"
        )

        {:ok, trade_id}

      {:aborted, reason} ->
        Logger.error("Failed to create exchange offer: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp format_exchange_offer(
         {_, trade_id, user_pubkey, offering_card_id, "exchange", quantity, _wanted_hash, _,
          wanted_data_json, "open", created_at, _, _}
       ) do
    with {:ok, offering_card} <- Cards.get_card(offering_card_id),
         {:ok, wanted_data} <- Jason.decode(wanted_data_json) do
      wanted_type = wanted_data["type"]
      wanted_card_ids = wanted_data["card_ids"]

      # Get wanted cards info
      wanted_cards =
        case wanted_type do
          "open" ->
            []

          "specific" ->
            wanted_card_ids
            |> Enum.map(&Cards.get_card/1)
            |> Enum.filter(&match?({:ok, _}, &1))
            |> Enum.map(fn {:ok, card} -> card end)
        end

      expires_at = created_at |> DateTime.add(24 * 60 * 60)

      %{
        id: trade_id,
        user_pubkey: user_pubkey,
        user_short: User.short_pubkey(%{pubkey: user_pubkey}),
        offering_card: offering_card,
        wanted_type: wanted_type,
        wanted_cards: wanted_cards,
        offer_type: "exchange",
        quantity: quantity,
        created_at: created_at,
        expires_at: expires_at
      }
    else
      _ -> nil
    end
  end

  # Helper function to create sample offers for testing
  def create_sample_offers do
    # Sample trader pubkeys
    sample_traders = [
      "npub1seedorchris1234567890abcdef",
      "npub1fab1234567890abcdef123456",
      "npub1altan1234567890abcdef1234",
      "npub1sticker21m1234567890abcd",
      "npub1markus_turm1234567890abc"
    ]

    case Sammelkarten.Cards.list_cards() do
      {:ok, cards} ->
        sample_cards = Enum.take(cards, 5)

        Enum.zip(sample_traders, sample_cards)
        |> Enum.each(fn {trader_pubkey, card} ->
          # Create a buy offer
          offer_type = if :rand.uniform(2) == 1, do: "buy", else: "sell"
          # -10% to +10%
          price_variation = (:rand.uniform(20) - 10) / 100
          price = trunc(card.current_price * (1 + price_variation))
          quantity = :rand.uniform(3)

          create_trade_offer(trader_pubkey, card.id, offer_type, price, quantity, nil)
        end)

        Logger.info("Created sample trading offers for testing")

      {:error, _} ->
        Logger.error("Failed to load cards for sample offers")
    end
  end

  # View helper functions that match the current TradingLive implementation

  def format_price(price_cents) do
    Sammelkarten.Formatter.format_german_price(price_cents)
  end

  def format_datetime(datetime) do
    # Format datetime in UTC (no timezone shift to avoid dependency issues)
    datetime
    |> Calendar.strftime("%d.%m.%Y %H:%M UTC")
  end

  def time_ago(datetime) do
    diff_seconds = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff_seconds < 60 -> "vor #{diff_seconds}s"
      diff_seconds < 3600 -> "vor #{div(diff_seconds, 60)}m"
      diff_seconds < 86400 -> "vor #{div(diff_seconds, 3600)}h"
      true -> "vor #{div(diff_seconds, 86400)}d"
    end
  end

  def filter_and_sort_offers(offers, search_query, filter_type, sort_by) do
    offers
    |> filter_by_search(search_query)
    |> filter_by_type(filter_type)
    |> sort_offers(sort_by)
  end

  defp filter_by_search(offers, "") do
    offers
  end

  defp filter_by_search(offers, query) do
    query_lower = String.downcase(query)

    Enum.filter(offers, fn offer ->
      card_name = if Map.has_key?(offer, :card), do: String.downcase(offer.card.name), else: ""
      String.contains?(card_name, query_lower)
    end)
  end

  defp filter_by_type(offers, "all") do
    offers
  end

  defp filter_by_type(offers, filter_type) do
    Enum.filter(offers, fn offer -> offer.offer_type == filter_type end)
  end

  def rarity_color(rarity) do
    case String.downcase(rarity) do
      "common" -> "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200"
      "uncommon" -> "bg-green-100 text-green-800 dark:bg-green-700 dark:text-green-200"
      "rare" -> "bg-blue-100 text-blue-800 dark:bg-blue-700 dark:text-blue-200"
      "epic" -> "bg-purple-100 text-purple-800 dark:bg-purple-700 dark:text-purple-200"
      "legendary" -> "bg-yellow-100 text-yellow-800 dark:bg-yellow-700 dark:text-yellow-200"
      "mythic" -> "bg-red-100 text-red-800 dark:bg-red-700 dark:text-red-200"
      _ -> "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200"
    end
  end
end
