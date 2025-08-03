defmodule SammelkartenWeb.PreferencesLive do
  use SammelkartenWeb, :live_view

  alias Sammelkarten.Preferences

  @impl true
  def mount(_params, _session, socket) do
    # Get user ID (for now, use a default user)
    user_id = "default_user"

    # Load user preferences
    {:ok, user_preferences} = Preferences.get_user_preferences(user_id)

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:user_preferences, user_preferences)
      |> assign(:form_data, Map.from_struct(user_preferences))
      |> assign(:has_changes, false)
      |> assign(:loading, false)
      |> assign(:saved, false)
      |> assign(:error_message, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("form_change", %{"preferences" => preference_changes}, socket) do
    # Convert form data to appropriate types for comparison
    cleaned_changes = clean_preference_changes(preference_changes)
    current_prefs = Map.from_struct(socket.assigns.user_preferences)
    
    # Remove timestamps and user_id for comparison
    current_prefs_clean = Map.drop(current_prefs, [:created_at, :updated_at, :user_id])
    cleaned_changes_clean = Map.drop(cleaned_changes, [:created_at, :updated_at, :user_id])
    
    # Check if there are actual changes by comparing relevant fields
    has_changes = Map.merge(current_prefs_clean, cleaned_changes_clean) != current_prefs_clean
    
    socket =
      socket
      |> assign(:form_data, cleaned_changes)
      |> assign(:has_changes, has_changes)
      |> assign(:saved, false)
      |> assign(:error_message, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_preferences", %{"preferences" => _preference_changes}, socket) do
    # Use the tracked form data instead of the raw form changes
    cleaned_changes = socket.assigns.form_data

    case Preferences.update_user_preferences(socket.assigns.user_id, cleaned_changes) do
      {:ok, updated_preferences} ->
        # Update refresh rate in PriceUpdater if it changed
        if Map.has_key?(cleaned_changes, :refresh_rate) do
          Sammelkarten.PriceUpdater.set_interval(updated_preferences.refresh_rate)
        end

        socket =
          socket
          |> assign(:user_preferences, updated_preferences)
          |> assign(:form_data, Map.from_struct(updated_preferences))
          |> assign(:has_changes, false)
          |> assign(:saved, true)
          |> assign(:error_message, nil)

        # Clear the saved message after 3 seconds
        Process.send_after(self(), :clear_saved_message, 3000)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:saved, false)
          |> assign(:error_message, "Failed to save preferences: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reset_preferences", _params, socket) do
    case Preferences.reset_to_defaults(socket.assigns.user_id) do
      {:ok, default_preferences} ->
        # Update refresh rate in PriceUpdater
        Sammelkarten.PriceUpdater.set_interval(default_preferences.refresh_rate)

        socket =
          socket
          |> assign(:user_preferences, default_preferences)
          |> assign(:form_data, Map.from_struct(default_preferences))
          |> assign(:has_changes, false)
          |> assign(:saved, true)
          |> assign(:error_message, nil)

        # Clear the saved message after 3 seconds
        Process.send_after(self(), :clear_saved_message, 3000)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:saved, false)
          |> assign(:error_message, "Failed to reset preferences: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:clear_saved_message, socket) do
    {:noreply, assign(socket, :saved, false)}
  end

  # Helper function to clean and convert form data to appropriate types
  defp clean_preference_changes(changes) do
    changes
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case key do
        "refresh_rate" -> Map.put(acc, :refresh_rate, String.to_integer(value))
        "cards_per_page" -> Map.put(acc, :cards_per_page, String.to_integer(value))
        "ticker_speed" -> Map.put(acc, :ticker_speed, String.to_integer(value))
        "theme" -> Map.put(acc, :theme, value)
        "default_sort" -> Map.put(acc, :default_sort, value)
        "default_sort_direction" -> Map.put(acc, :default_sort_direction, value)
        "chart_style" -> Map.put(acc, :chart_style, value)
        "auto_refresh" -> Map.put(acc, :auto_refresh, value == "true")
        "notifications_enabled" -> Map.put(acc, :notifications_enabled, value == "true")
        "sound_enabled" -> Map.put(acc, :sound_enabled, value == "true")
        "show_ticker" -> Map.put(acc, :show_ticker, value == "true")
        _ -> acc
      end
    end)
    |> Map.merge(%{updated_at: DateTime.utc_now()})
  end
end