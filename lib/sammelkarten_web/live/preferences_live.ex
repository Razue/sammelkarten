defmodule SammelkartenWeb.PreferencesLive do
  use SammelkartenWeb, :live_view

  alias Sammelkarten.Preferences

  @impl true
  def mount(_params, session, socket) do
    # Get user ID (for now, use a default user)
    user_id = "default_user"

    # Load user preferences
    {:ok, user_preferences} = Preferences.get_user_preferences(user_id)

    # Build nostr status from session (preferred) or preferences fallback
    nostr_status = build_nostr_status(session, user_preferences)

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:user_preferences, user_preferences)
      |> assign(:form_data, Map.from_struct(user_preferences))
      |> assign(:has_changes, false)
      |> assign(:loading, false)
      |> assign(:saved, false)
      |> assign(:error_message, nil)
      |> assign(:raw_session, session)
      |> assign(:nostr_status, nostr_status)
      |> put_effective_flags()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    case Preferences.get_user_preferences(socket.assigns.user_id) do
      {:ok, latest_prefs} ->
        socket =
          if socket.assigns.has_changes do
            socket
          else
            assign(socket, :form_data, Map.from_struct(latest_prefs))
          end

        # Use stored raw_session (contains nostr auth set on /auth page)
        nostr_status = build_nostr_status(socket.assigns.raw_session, latest_prefs)

        {:noreply,
         socket
         |> assign(:user_preferences, latest_prefs)
         |> assign(:nostr_status, nostr_status)
         |> put_effective_flags()}

      {:error, _} ->
        {:noreply, socket}
    end
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
      |> put_effective_flags()

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
          |> put_effective_flags()

        # If theme changed, broadcast theme update to all clients
        socket =
          if Map.has_key?(cleaned_changes, :theme) do
            # Push theme change event to client-side JavaScript
            push_event(socket, "theme-changed", %{theme: updated_preferences.theme})
          else
            socket
          end

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
          |> put_effective_flags()

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
  def handle_event("disconnect_nostr", _params, socket) do
    prefs = socket.assigns.user_preferences

    cleaned = %{
      Map.from_struct(prefs)
      | nostr_enabled: false,
        nostr_pubkey: "",
        updated_at: DateTime.utc_now()
    }

    _ = Preferences.update_user_preferences(socket.assigns.user_id, cleaned)

    cleared_session =
      case socket.assigns[:raw_session] do
        %{} = sess -> Map.drop(sess, ["nostr_authenticated", "nostr_user", "nostr_extension"])
        _ -> %{}
      end

    {:noreply,
     socket
     |> assign(:user_preferences, struct(prefs.__struct__, cleaned))
     |> assign(:form_data, cleaned)
     |> assign(:raw_session, cleared_session)
     |> assign(:nostr_status, %{connected: false, pubkey: nil, extension: nil})
     |> assign(:has_changes, false)
     |> put_effective_flags()
     |> push_event("nostr-disconnected", %{})}
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
      key when key in ["refresh_rate"] ->
        {String.to_atom(key), String.to_integer(value)}

      key
      when key in [
             "theme",
             "default_sort",
             "default_sort_direction",
             "nostr_pubkey",
             "nostr_relays"
           ] ->
        {String.to_atom(key), value}

      key
      when key in [
             "auto_refresh",
             "notifications_enabled",
             "sound_enabled",
             "show_ticker",
             "nostr_enabled",
             "nostr_auto_connect",
             "nostr_show_profile"
           ] ->
        {String.to_atom(key), value == "true"}

      _ ->
        nil
    end
  end

  # Helper functions for Nostr integration

  # Build status using session first, then user preference fallback.
  defp build_nostr_status(session, user_prefs) do
    cond do
      user_prefs.nostr_enabled and
          match?(%{"nostr_authenticated" => true, "nostr_user" => u} when is_map(u), session) ->
        user = session["nostr_user"]

        %{
          connected: true,
          pubkey: user[:pubkey] || user["pubkey"],
          extension: session["nostr_extension"] || "Browser Extension"
        }

      user_prefs.nostr_enabled and user_prefs.nostr_pubkey not in [nil, ""] ->
        %{
          connected: true,
          pubkey: user_prefs.nostr_pubkey,
          extension: "Saved Preferences"
        }

      true ->
        %{connected: false, pubkey: nil, extension: nil}
    end
  end

  # Derive effective flags used by checkboxes so templates remain simple
  defp put_effective_flags(socket) do
    fd = socket.assigns.form_data
    prefs = socket.assigns.user_preferences

    assign(socket,
      effective_auto_refresh: Map.get(fd, :auto_refresh, prefs.auto_refresh),
      effective_show_ticker: Map.get(fd, :show_ticker, prefs.show_ticker),
      effective_notifications_enabled:
        Map.get(fd, :notifications_enabled, prefs.notifications_enabled),
      effective_sound_enabled: Map.get(fd, :sound_enabled, prefs.sound_enabled)
    )
  end

  defp submit_button_classes(has_changes) do
    base =
      "px-4 py-2 text-sm font-medium border border-transparent rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 transition-colors"

    if has_changes do
      base <> " text-white bg-blue-600 hover:bg-blue-700 focus:ring-blue-500"
    else
      base <> " text-gray-400 dark:text-gray-500 bg-gray-200 dark:bg-gray-700 cursor-not-allowed"
    end
  end
end
