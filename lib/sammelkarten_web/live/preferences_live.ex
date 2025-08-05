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

        # Update auto_refresh setting in PriceUpdater if it changed
        if Map.has_key?(cleaned_changes, :auto_refresh) do
          Sammelkarten.PriceUpdater.set_auto_refresh(updated_preferences.auto_refresh)
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
        # Update refresh rate and auto_refresh in PriceUpdater
        Sammelkarten.PriceUpdater.set_interval(default_preferences.refresh_rate)
        Sammelkarten.PriceUpdater.set_auto_refresh(default_preferences.auto_refresh)

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
    |> Enum.reduce(%{}, &convert_preference_field/2)
    |> Map.merge(%{updated_at: DateTime.utc_now()})
  end

  defp convert_preference_field({key, value}, acc) do
    case convert_field_value(key, value) do
      {atom_key, converted_value} -> Map.put(acc, atom_key, converted_value)
      nil -> acc
    end
  end

  defp convert_field_value(key, value) do
    case key do
      key when key in ["refresh_rate", "cards_per_page", "ticker_speed"] ->
        {String.to_atom(key), String.to_integer(value)}

      key when key in ["theme", "default_sort", "default_sort_direction", "chart_style"] ->
        {String.to_atom(key), value}

      key when key in ["auto_refresh", "notifications_enabled", "sound_enabled", "show_ticker"] ->
        {String.to_atom(key), value == "true"}

      _ ->
        nil
    end
  end
end