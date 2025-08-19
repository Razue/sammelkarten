defmodule SammelkartenWeb.Admin.NostrLive do
  @moduledoc """
  Admin interface for managing Nostr publishing operations.
  Allows publishing card definitions and monitoring indexer status.
  """

  use SammelkartenWeb, :live_view
  alias Sammelkarten.{Cards, UserCollection}
  alias Sammelkarten.Nostr.{Publisher, Indexer, Event, PriceAlertWatcher}

  @impl true
  def mount(_params, session, socket) do
    if is_admin?(session) do
      socket =
        socket
        |> assign(:page_title, "Nostr Publishing")
        |> assign(:cards, list_cards())
        |> assign(:indexer_state, get_indexer_state())
        |> assign(:publishing, false)
        |> assign(:publish_result, nil)
        |> assign(:collection_result, nil)
        |> assign(:trade_result, nil)
        |> assign(:portfolio_result, nil)
        |> assign(:test_pubkey, "")
        |> assign(:test_offer, default_test_offer())
        |> assign(:alerts, list_alerts())
        |> assign(:alert_result, nil)

      {:ok, socket}
    else
      {:ok, redirect(socket, to: "/admin")}
    end
  end

  @impl true
  def handle_event("register_alert", %{"pubkey" => pubkey, "card_id" => card_id, "direction" => direction, "threshold" => threshold}, socket) do
    direction_atom = String.to_atom(direction)
    threshold_int = String.to_integer(threshold)
    
    case PriceAlertWatcher.register_alert(pubkey, card_id, direction_atom, threshold_int) do
      :ok ->
        socket =
          socket
          |> assign(:alert_result, {:success, "Alert registered successfully"})
          |> assign(:alerts, list_alerts())
        {:noreply, socket}
      
      {:error, reason} ->
        socket = assign(socket, :alert_result, {:error, "Failed to register alert: #{inspect(reason)}"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_alert", %{"pubkey" => pubkey, "card_id" => card_id, "direction" => direction}, socket) do
    direction_atom = String.to_atom(direction)
    
    case PriceAlertWatcher.remove_alert(pubkey, card_id, direction_atom) do
      :ok ->
        socket =
          socket
          |> assign(:alert_result, {:success, "Alert removed successfully"})
          |> assign(:alerts, list_alerts())
        {:noreply, socket}
      
      {:error, reason} ->
        socket = assign(socket, :alert_result, {:error, "Failed to remove alert: #{inspect(reason)}"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("publish_card", %{"card_id" => card_id}, socket) do
    case Cards.get_card(card_id) do
      {:ok, card} ->
        socket = assign(socket, :publishing, true)
        
        # Convert Card struct to map format expected by Event.card_definition
        card_map = %{
          card_id: card.id,
          name: card.name,
          rarity: card.rarity,
          slug: card.slug,
          image: card.image_path,
          description: card.description
        }

        case Publisher.publish_card_definition(card_map) do
          {:ok, event} ->
            socket =
              socket
              |> assign(:publishing, false)
              |> assign(:publish_result, {:success, "Published card #{card.name} as event #{event.id}"})
              |> push_event("show_flash", %{type: "info", message: "Card published successfully"})

            {:noreply, socket}

          {:error, reason} ->
            socket =
              socket
              |> assign(:publishing, false)
              |> assign(:publish_result, {:error, "Failed to publish card: #{inspect(reason)}"})
              |> push_event("show_flash", %{type: "error", message: "Failed to publish card"})

            {:noreply, socket}
        end

      {:error, :not_found} ->
        socket =
          socket
          |> assign(:publish_result, {:error, "Card not found: #{card_id}"})
          |> push_event("show_flash", %{type: "error", message: "Card not found"})

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("publish_all_cards", _params, socket) do
    socket = assign(socket, :publishing, true)

    cards = 
      socket.assigns.cards
      |> Enum.map(fn card ->
        %{
          card_id: card.id,
          name: card.name,
          rarity: card.rarity,
          slug: card.slug,
          image: card.image_path,
          description: card.description
        }
      end)

    case Publisher.publish_card_definitions(cards) do
      {:ok, events} ->
        socket =
          socket
          |> assign(:publishing, false)
          |> assign(:publish_result, {:success, "Published #{length(events)} cards successfully"})
          |> push_event("show_flash", %{type: "info", message: "All cards published successfully"})

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:publishing, false)
          |> assign(:publish_result, {:error, "Failed to publish cards: #{inspect(reason)}"})
          |> push_event("show_flash", %{type: "error", message: "Failed to publish cards"})

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("rebuild_index", _params, socket) do
    case Indexer.rebuild() do
      :ok ->
        socket =
          socket
          |> assign(:indexer_state, get_indexer_state())
          |> push_event("show_flash", %{type: "info", message: "Index rebuilt successfully"})

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> push_event("show_flash", %{type: "error", message: "Failed to rebuild index: #{inspect(reason)}"})

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("test_collection_snapshot", %{"pubkey" => pubkey}, socket) do
    case UserCollection.create_collection_snapshot(pubkey) do
      {:ok, snapshot} ->
        socket =
          socket
          |> assign(:collection_result, {:success, "Collection snapshot created: #{inspect(snapshot)}"})
          |> push_event("show_flash", %{type: "info", message: "Collection snapshot created successfully"})

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:collection_result, {:error, "Failed to create collection snapshot: #{inspect(reason)}"})
          |> push_event("show_flash", %{type: "error", message: "Failed to create collection snapshot"})

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("test_collection_validation", %{"pubkey" => pubkey, "json" => json}, socket) do
    case UserCollection.validate_collection_snapshot(pubkey, json) do
      {:ok, :consistent} ->
        socket =
          socket
          |> assign(:collection_result, {:success, "Collection snapshot is consistent with current state"})
          |> push_event("show_flash", %{type: "info", message: "Collection validation passed"})

        {:noreply, socket}

      {:error, {:inconsistent_collections, current, snapshot}} ->
        socket =
          socket
          |> assign(:collection_result, {:error, "Collections are inconsistent. Current: #{inspect(current)}, Snapshot: #{inspect(snapshot)}"})
          |> push_event("show_flash", %{type: "warning", message: "Collection validation failed: inconsistent data"})

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:collection_result, {:error, "Validation failed: #{inspect(reason)}"})
          |> push_event("show_flash", %{type: "error", message: "Collection validation error"})

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_test_pubkey", %{"pubkey" => pubkey}, socket) do
    {:noreply, assign(socket, :test_pubkey, pubkey)}
  end

  @impl true
  def handle_event("test_portfolio_snapshot", %{"pubkey" => pubkey}, socket) do
    try do
      case Publisher.publish_portfolio_snapshot(pubkey) do
        {:ok, event} ->
          # Wait a moment for indexing
          Process.sleep(100)
          
          # Verify indexing worked
          case Indexer.get_portfolio(event.pubkey) do
            {:ok, portfolio_data} ->
              message = """
              ✅ Portfolio snapshot published successfully!
              • Event ID: #{String.slice(event.id, 0, 16)}...
              • Pubkey: #{String.slice(event.pubkey, 0, 16)}...
              • Data indexed: #{inspect(portfolio_data.data)}
              """
              
              socket =
                socket
                |> assign(:portfolio_result, {:success, message})
                |> push_event("show_flash", %{type: "info", message: "Portfolio snapshot test completed successfully"})
              
              {:noreply, socket}
            
            {:error, :not_found} ->
              message = """
              ⚠️ Portfolio snapshot published but not indexed yet
              • Event ID: #{String.slice(event.id, 0, 16)}...
              • Try checking indexer status
              """
              
              socket =
                socket
                |> assign(:portfolio_result, {:warning, message})
                |> push_event("show_flash", %{type: "warning", message: "Portfolio published but not indexed"})
              
              {:noreply, socket}
          end
        
        {:error, reason} ->
          socket =
            socket
            |> assign(:portfolio_result, {:error, "Failed to publish: #{inspect(reason)}"})
            |> push_event("show_flash", %{type: "error", message: "Portfolio snapshot test failed"})
          
          {:noreply, socket}
      end
    rescue
      error ->
        socket =
          socket
          |> assign(:portfolio_result, {:error, "Test failed: #{Exception.message(error)}"})
          |> push_event("show_flash", %{type: "error", message: "Portfolio snapshot test failed"})
        
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("test_trade_offer", params, socket) do
    # Generate test keys
    seller_privkey = Event.generate_private_key()
    {:ok, seller_pubkey} = Event.private_key_to_public(seller_privkey)
    buyer_privkey = Event.generate_private_key()
    {:ok, buyer_pubkey} = Event.private_key_to_public(buyer_privkey)

    # Get offer data from form
    offer_data = %{
      card_id: Map.get(params, "card_id", "BITCOIN_HOTEL"),
      offer_type: Map.get(params, "offer_type", "sell"),
      price: String.to_integer(Map.get(params, "price", "150000")),
      quantity: String.to_integer(Map.get(params, "quantity", "1")),
      expires_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.to_unix()
    }

    try do
      # Step 1: Create and publish offer
      case Publisher.publish_trade_offer(seller_pubkey, offer_data, seller_privkey) do
        {:ok, offer_event} ->
          # Step 2: Create execution
          execution_data = %{
            offer_id: offer_event.id,
            buyer_pubkey: buyer_pubkey,
            seller_pubkey: seller_pubkey,
            card_id: offer_data.card_id,
            quantity: offer_data.quantity,
            price: offer_data.price
          }

          case Publisher.publish_trade_execution(buyer_pubkey, execution_data, buyer_privkey) do
            {:ok, execution_event} ->
              # Check final status
              case Indexer.fetch_offer(offer_event.id) do
                {:ok, final_offer} ->
                  message = """
                  ✅ Complete trade lifecycle test passed:
                  • Offer created (ID: #{String.slice(offer_event.id, 0, 16)}...)
                  • Execution created (ID: #{String.slice(execution_event.id, 0, 16)}...)
                  • Final offer status: #{final_offer.status}
                  """
                  
                  socket =
                    socket
                    |> assign(:trade_result, {:success, message})
                    |> push_event("show_flash", %{type: "info", message: "Trade offer lifecycle test completed successfully"})

                  {:noreply, socket}

                {:error, reason} ->
                  raise "Failed to fetch final offer: #{inspect(reason)}"
              end

            {:error, reason} ->
              raise "Failed to publish execution: #{inspect(reason)}"
          end

        {:error, reason} ->
          raise "Failed to publish offer: #{inspect(reason)}"
      end
    rescue
      error ->
        socket =
          socket
          |> assign(:trade_result, {:error, "Trade test failed: #{Exception.message(error)}"})
          |> push_event("show_flash", %{type: "error", message: "Trade test failed"})

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("test_trade_cancel", params, socket) do
    # Generate test keys
    seller_privkey = Event.generate_private_key()
    {:ok, seller_pubkey} = Event.private_key_to_public(seller_privkey)

    # Get offer data from form
    offer_data = %{
      card_id: Map.get(params, "card_id", "BITCOIN_HOTEL"),
      offer_type: "sell",
      price: 150000,
      quantity: 1,
      expires_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.to_unix()
    }

    try do
      # Step 1: Create offer
      case Publisher.publish_trade_offer(seller_pubkey, offer_data, seller_privkey) do
        {:ok, offer_event} ->
          # Step 2: Cancel the offer
          case Publisher.publish_trade_cancel(seller_pubkey, offer_event.id, seller_privkey) do
            {:ok, cancel_event} ->
              # Check final status
              case Indexer.fetch_offer(offer_event.id) do
                {:ok, final_offer} ->
                  message = """
                  ✅ Trade cancellation test passed:
                  • Offer created (ID: #{String.slice(offer_event.id, 0, 16)}...)
                  • Cancel event created (ID: #{String.slice(cancel_event.id, 0, 16)}...)
                  • Final offer status: #{final_offer.status}
                  """
                  
                  socket =
                    socket
                    |> assign(:trade_result, {:success, message})
                    |> push_event("show_flash", %{type: "info", message: "Trade cancellation test completed successfully"})

                  {:noreply, socket}

                {:error, reason} ->
                  raise "Failed to fetch cancelled offer: #{inspect(reason)}"
              end

            {:error, reason} ->
              raise "Failed to publish cancel: #{inspect(reason)}"
          end

        {:error, reason} ->
          raise "Failed to publish offer: #{inspect(reason)}"
      end
    rescue
      error ->
        socket =
          socket
          |> assign(:trade_result, {:error, "Cancel test failed: #{Exception.message(error)}"})
          |> push_event("show_flash", %{type: "error", message: "Cancel test failed"})

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("list_open_offers", _params, socket) do
    try do
      offers = Indexer.list_open_offers()
      message = """
      📋 Current open offers (#{length(offers)}):
      #{Enum.map_join(offers, "\n", fn offer ->
        "• #{offer.card_id} #{offer.offer_type} #{offer.quantity}x at €#{div(offer.price, 100)}.#{rem(offer.price, 100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
      end)}
      """
      
      socket =
        socket
        |> assign(:trade_result, {:success, message})
        |> push_event("show_flash", %{type: "info", message: "Listed #{length(offers)} open offers"})

      {:noreply, socket}
    rescue
      error ->
        socket =
          socket
          |> assign(:trade_result, {:error, "Failed to list offers: #{Exception.message(error)}"})
          |> push_event("show_flash", %{type: "error", message: "Failed to list offers"})

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    socket =
      socket
      |> assign(:cards, list_cards())
      |> assign(:indexer_state, get_indexer_state())
      |> assign(:publish_result, nil)
      |> assign(:collection_result, nil)
      |> assign(:trade_result, nil)

    {:noreply, socket}
  end

  # Private functions

  defp is_admin?(session) do
    session["admin_authenticated"] == true
  end

  defp list_cards do
    case Cards.list_cards() do
      {:ok, cards} -> cards
      {:error, _} -> []
    end
  end

  defp get_indexer_state do
    try do
      Indexer.state()
    rescue
      _ -> %{error: "Indexer not available"}
    end
  end

  defp format_timestamp(timestamp) when is_integer(timestamp) do
    DateTime.from_unix!(timestamp)
    |> DateTime.to_string()
  end

  defp format_timestamp(_), do: "Unknown"

  defp default_test_offer do
    %{
      card_id: "BITCOIN_HOTEL",
      offer_type: "sell",
      price: "150000",
      quantity: "1"
    }
  end

  defp list_alerts do
    try do
      PriceAlertWatcher.list_alerts()
    rescue
      _ -> []
    end
  end
end