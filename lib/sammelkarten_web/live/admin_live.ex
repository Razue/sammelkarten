defmodule SammelkartenWeb.AdminLive do
  use SammelkartenWeb, :live_view

  alias Sammelkarten.{Cards, Database}
  alias Sammelkarten.Formatter

  @impl true
  def mount(_params, session, socket) do
    # Check authentication
    unless session["admin_authenticated"] do
      {:ok, push_navigate(socket, to: ~p"/admin/login")}
    else
      cards = case Cards.list_cards() do
        {:ok, cards_list} -> cards_list
        {:error, _} -> []
      end
      
      socket =
        socket
        |> assign(
          cards: cards,
          selected_card: nil,
          form_data: %{},
          show_add_form: false,
          show_edit_form: false,
          error_message: nil,
          success_message: nil
        )

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("show_add_form", _params, socket) do
    {:noreply, assign(socket, show_add_form: true, show_edit_form: false)}
  end

  @impl true
  def handle_event("hide_forms", _params, socket) do
    {:noreply, assign(socket, show_add_form: false, show_edit_form: false, selected_card: nil)}
  end

  @impl true
  def handle_event("edit_card", %{"id" => id}, socket) do
    case Cards.get_card(id) do
      {:ok, card} ->
        form_data = %{
          "id" => card.id,
          "name" => card.name,
          "image_path" => card.image_path,
          "current_price" => format_price_for_form(card.current_price),
          "rarity" => card.rarity,
          "description" => card.description
        }
        
        {:noreply, assign(socket, 
          show_edit_form: true, 
          show_add_form: false,
          selected_card: card,
          form_data: form_data
        )}
      {:error, _} ->
        {:noreply, assign(socket, error_message: "Card not found")}
    end
  end


  @impl true
  def handle_event("delete_card", %{"id" => id}, socket) do
    case Cards.delete_card(id) do
      :ok ->
        cards = case Cards.list_cards() do
          {:ok, cards_list} -> cards_list
          {:error, _} -> []
        end
        {:noreply, assign(socket, 
          cards: cards, 
          success_message: "Card deleted successfully",
          error_message: nil
        )}
      {:error, reason} ->
        {:noreply, assign(socket, error_message: "Failed to delete card: #{reason}")}
    end
  end

  @impl true
  def handle_event("save_card", %{"card" => params}, socket) do
    case create_or_update_card(params, socket.assigns.selected_card) do
      {:ok, _card} ->
        cards = case Cards.list_cards() do
          {:ok, cards_list} -> cards_list
          {:error, _} -> []
        end
        {:noreply, assign(socket, 
          cards: cards,
          show_add_form: false,
          show_edit_form: false,
          selected_card: nil,
          success_message: "Card saved successfully",
          error_message: nil
        )}
      {:error, reason} ->
        {:noreply, assign(socket, error_message: "Failed to save card: #{reason}")}
    end
  end


  @impl true
  def handle_event("clear_messages", _params, socket) do
    {:noreply, assign(socket, error_message: nil, success_message: nil)}
  end

  @impl true
  def handle_event("reset_database", _params, socket) do
    try do
      Database.reset_tables()
      Sammelkarten.Seeds.run()
      cards = case Cards.list_cards() do
        {:ok, cards_list} -> cards_list
        {:error, _} -> []
      end
      
      {:noreply, assign(socket, 
        cards: cards,
        success_message: "Database reset and reseeded successfully",
        error_message: nil
      )}
    rescue
      e ->
        {:noreply, assign(socket, error_message: "Failed to reset database: #{Exception.message(e)}")}
    end
  end

  defp create_or_update_card(params, nil) do
    # Create new card
    with {:ok, price} <- parse_price(params["current_price"] || "0") do
      card_attrs = %{
        id: params["id"] || generate_id(params["name"]),
        name: params["name"],
        image_path: params["image_path"],
        current_price: price,
        rarity: params["rarity"] || "common",
        description: params["description"] || "",
        last_updated: DateTime.utc_now()
      }
      
      Cards.create_card(card_attrs)
    else
      :error -> {:error, "Invalid price format"}
    end
  end

  defp create_or_update_card(params, card) do
    # Update existing card
    with {:ok, price} <- parse_price(params["current_price"] || "0") do
      update_attrs = %{
        name: params["name"],
        image_path: params["image_path"],
        current_price: price,
        rarity: params["rarity"],
        description: params["description"],
        last_updated: DateTime.utc_now()
      }
      
      # Since no update_card/2 exists, we recreate the card
      Cards.delete_card(card.id)
      Cards.create_card(Map.put(update_attrs, :id, card.id))
    else
      :error -> {:error, "Invalid price format"}
    end
  end

  defp generate_id(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]/, "_")
    |> String.replace(~r/_+/, "_")
    |> String.trim_trailing("_")
  end

  defp parse_price(price_str) when is_binary(price_str) do
    case Integer.parse(price_str) do
      {price, ""} -> {:ok, price}
      _ -> :error
    end
  end

  defp parse_price(_), do: :error

  defp format_price(price) do
    Formatter.format_german_price(price)
  end

  defp format_price_for_form(price) when is_integer(price) do
    # Keep as sats (integer) for form display
    Integer.to_string(price)
  end

  defp rarity_color(rarity) do
    case rarity do
      "common" -> "bg-gray-100 text-gray-800"
      "uncommon" -> "bg-green-100 text-green-800"
      "rare" -> "bg-blue-100 text-blue-800"
      "epic" -> "bg-purple-100 text-purple-800"
      "legendary" -> "bg-yellow-100 text-yellow-800"
      "mythic" -> "bg-red-100 text-red-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%d.%m.%Y %H:%M")
  end
end