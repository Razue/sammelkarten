defmodule SammelkartenWeb.NostrLive do
  use SammelkartenWeb, :live_view

  alias Sammelkarten.Nostr.{Indexer, Publisher}
  alias Sammelkarten.Cards

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to real-time Nostr events
      Phoenix.PubSub.subscribe(Sammelkarten.PubSub, "nostr_events")
    end

    socket =
      socket
      |> assign(:page_title, "Nostr Trading Hub")
      |> assign(:connection_status, :connected)
      |> assign(:selected_card, nil)
      |> assign(:offer_type, "buy")
      |> assign(:offer_price, "")
      |> assign(:offer_quantity, "1")
      |> assign(:form_errors, [])
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh_data", _, socket) do
    {:noreply, load_data(socket)}
  end

  def handle_event("select_card", %{"card_id" => card_id}, socket) do
    socket =
      socket
      |> assign(:selected_card, card_id)
      |> validate_form()

    {:noreply, socket}
  end

  def handle_event("set_offer_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, :offer_type, type)}
  end

  def handle_event("update_offer_price", %{"value" => price}, socket) do
    price = String.trim(price)

    socket =
      socket
      |> assign(:offer_price, price)
      |> validate_form()

    {:noreply, socket}
  end

  def handle_event("update_offer_quantity", %{"value" => quantity}, socket) do
    quantity = String.trim(quantity)

    socket =
      socket
      |> assign(:offer_quantity, quantity)
      |> validate_form()

    {:noreply, socket}
  end

  def handle_event("create_offer", params, socket) do
    # Use form parameters, not assigns
    price_str = params["price"] || ""
    qty_str = params["quantity"] || ""
    
    # Update assigns with form values
    socket = 
      socket
      |> assign(:offer_price, price_str)
      |> assign(:offer_quantity, qty_str)
      |> validate_form()

    case socket.assigns.form_errors do
      [] ->
        %{selected_card: card_id, offer_type: type} = socket.assigns

        with {:ok, price} <- parse_integer(price_str),
             {:ok, quantity} <- parse_integer(qty_str) do
          attrs = %{
            card_id: card_id,
            offer_type: String.to_existing_atom(type),
            price: price,
            quantity: quantity,
            # 24 hours
            expires_at: System.system_time(:second) + 86400
          }

          Logger.info("Trade offer created: #{inspect(attrs)}")

          case Publisher.publish_trade_offer(get_test_pubkey(), attrs, get_test_privkey()) do
            {:ok, event} ->
              Logger.info("Trade offer created - event: #{inspect(event)}")

              # Manually trigger indexing of the event
              Phoenix.PubSub.broadcast(Sammelkarten.PubSub, "nostr_events", {:nostr_event, event})

              socket =
                socket
                |> put_flash(:info, "Trade offer created successfully!")
                |> assign(:offer_price, "")
                |> assign(:offer_quantity, "1")
                |> assign(:form_errors, [])
                |> load_data()

              {:noreply, socket}

            {:error, reason} ->
              {:noreply, put_flash(socket, :error, "Failed to create offer: #{inspect(reason)}")}
          end
        else
          error ->
            Logger.error("error Trade offer created: #{inspect(error)}")

            {:noreply, put_flash(socket, :error, "Invalid price or quantity format")}
        end

      errors ->
        Logger.error("error Trade offer created: #{inspect(errors)}")

        {:noreply, socket}
    end
  end

  def handle_event("execute_offer", %{"offer_id" => offer_id}, socket) do
    case Indexer.fetch_offer(offer_id) do
      {:ok, offer} ->
        execution_attrs = %{
          offer_id: offer_id,
          buyer_pubkey: get_test_pubkey(),
          seller_pubkey: offer.creator_pubkey,
          card_id: offer.card_id,
          quantity: 1,
          price: offer.price
        }

        case Publisher.publish_trade_execution(
               get_test_pubkey(),
               execution_attrs,
               get_test_privkey()
             ) do
          {:ok, event} ->
            # Manually trigger indexing of the event
            Phoenix.PubSub.broadcast(Sammelkarten.PubSub, "nostr_events", {:nostr_event, event})
            {:noreply, put_flash(socket, :info, "Trade executed successfully!")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to execute trade: #{inspect(reason)}")}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Offer not found")}
    end
  end

  def handle_event("cancel_offer", %{"offer_id" => offer_id}, socket) do
    case Publisher.publish_trade_cancel(get_test_pubkey(), offer_id, get_test_privkey()) do
      {:ok, event} ->
        # Manually trigger indexing of the event
        Phoenix.PubSub.broadcast(Sammelkarten.PubSub, "nostr_events", {:nostr_event, event})
        {:noreply, put_flash(socket, :info, "Offer cancelled successfully!")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel offer: #{inspect(reason)}")}
    end
  end

  # Handle real-time PubSub events
  @impl true
  def handle_info({:nostr_event, _event}, socket) do
    {:noreply, load_data(socket)}
  end

  def handle_info({:phoenix, :live_reload, :file_changed, _}, socket) do
    {:noreply, socket}
  end

  # Private functions
  defp load_data(socket) do
    cards =
      case Cards.list_cards() do
        {:ok, card_list} -> card_list
        _ -> []
      end

    offers = Indexer.list_offers_by_status("open") || []
    executions = Indexer.list_executions() |> List.wrap() |> Enum.take(20)

    socket
    |> assign(:cards, cards)
    |> assign(:offers, offers)
    |> assign(:executions, executions)
  end

  defp parse_integer(str) do
    case Integer.parse(str) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_integer}
    end
  end

  defp get_test_pubkey do
    System.get_env("NOSTR_TEST_PUBKEY") ||
      "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
  end

  defp get_test_privkey do
    System.get_env("NOSTR_TEST_PRIVKEY") ||
      "0000000000000000000000000000000000000000000000000000000000000001"
  end

  defp format_price(price_cents) do
    Sammelkarten.Formatter.format_german_price(price_cents)
  end

  defp format_time_ago(timestamp) do
    now = System.system_time(:second)
    diff = now - timestamp

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  defp get_card_name(cards, card_id) do
    case Enum.find(cards, fn card -> card.id == card_id end) do
      nil -> card_id
      card -> card.name
    end
  end

  defp validate_form(socket) do
    %{selected_card: card_id, offer_price: price_str, offer_quantity: qty_str} = socket.assigns

    errors = []

    errors =
      if is_nil(card_id) do
        ["Please select a card" | errors]
      else
        errors
      end

    errors =
      if price_str == "" or is_nil(price_str) do
        errors
      else
        case parse_integer(price_str) do
          {:ok, price} when price <= 0 -> ["Price must be greater than 0" | errors]
          {:error, _} -> ["Price must be a valid number" | errors]
          _ -> errors
        end
      end

    errors =
      if qty_str == "" or is_nil(qty_str) do
        ["Quantity is required" | errors]
      else
        case parse_integer(qty_str) do
          {:ok, qty} when qty <= 0 -> ["Quantity must be greater than 0" | errors]
          {:error, _} -> ["Quantity must be a valid number" | errors]
          _ -> errors
        end
      end

    assign(socket, :form_errors, Enum.reverse(errors))
  end
end
