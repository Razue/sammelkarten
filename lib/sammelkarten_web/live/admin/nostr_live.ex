defmodule SammelkartenWeb.Admin.NostrLive do
  @moduledoc """
  Admin interface for managing Nostr publishing operations.
  Allows publishing card definitions and monitoring indexer status.
  """

  use SammelkartenWeb, :live_view
  alias Sammelkarten.{Cards, Card}
  alias Sammelkarten.Nostr.{Publisher, Indexer}

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

      {:ok, socket}
    else
      {:ok, redirect(socket, to: "/admin")}
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
  def handle_event("refresh", _params, socket) do
    socket =
      socket
      |> assign(:cards, list_cards())
      |> assign(:indexer_state, get_indexer_state())
      |> assign(:publish_result, nil)

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
end