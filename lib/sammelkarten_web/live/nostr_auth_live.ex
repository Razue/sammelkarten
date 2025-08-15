defmodule SammelkartenWeb.NostrAuthLive do
  @moduledoc """
  LiveView for Nostr authentication and user management.

  This page handles:
  - User authentication via Nostr browser extensions
  - User profile management
  - Session management
  - NIP-07 integration
  """

  use SammelkartenWeb, :live_view

  alias Sammelkarten.Nostr.{Auth, User, Event}
  # alias SammelkartenWeb.Plugs.NostrAuth
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Nostr Authentication")
      |> assign(:nostr_supported, false)
      |> assign(:extensions, [])
      |> assign(:current_user, nil)
      |> assign(:authenticated, false)
      |> assign(:challenge, nil)
      |> assign(:auth_step, :check_support)
      |> assign(:error_message, nil)
      |> assign(:loading, false)

    {:ok, socket}
  end

  @impl true
  def handle_event(
        "nostr_support_status",
        %{"supported" => supported, "extensions" => extensions},
        socket
      ) do
    Logger.info("Nostr support status: #{supported}, Extensions: #{inspect(extensions)}")

    socket =
      socket
      |> assign(:nostr_supported, supported)
      |> assign(:extensions, extensions)
      |> assign(:auth_step, if(supported, do: :ready_to_auth, else: :no_support))

    {:noreply, socket}
  end

  @impl true
  def handle_event("start_login", _params, socket) do
    if socket.assigns.nostr_supported do
      # Generate authentication challenge
      challenge_data = Auth.generate_challenge()

      socket =
        socket
        |> assign(:challenge, challenge_data.challenge)
        |> assign(:auth_step, :waiting_for_signature)
        |> assign(:loading, true)
        |> assign(:error_message, nil)

      # Send challenge to JavaScript hook
      socket =
        push_event(socket, "nostr_login", %{
          challenge: challenge_data.challenge,
          # Could add relay URL here if needed
          relay_url: nil
        })

      {:noreply, socket}
    else
      socket = assign(socket, :error_message, "Nostr extension not detected")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "nostr_auth_signed",
        %{"signed_event" => signed_event, "challenge" => challenge},
        socket
      ) do
    Logger.info("Received signed auth event: #{inspect(signed_event)}")

    # Parse the signed event
    auth_event = Event.from_map(signed_event)

    # Verify the authentication
    case Auth.verify_auth_event(auth_event, challenge) do
      {:ok, pubkey} ->
        # Authentication successful
        case User.new(pubkey) do
          %User{} = user ->
            user = User.update_last_seen(user)

            # Store user in database
            Auth.store_user(user)

            # Subscribe to user metadata updates
            subscribe_to_user_metadata(pubkey)

            # Send user data to JavaScript to create session via POST request
            socket =
              push_event(socket, "create_nostr_session", %{
                user: %{
                  pubkey: user.pubkey,
                  npub: user.npub,
                  name: user.name,
                  display_name: user.display_name,
                  about: user.about,
                  picture: user.picture,
                  nip05: user.nip05,
                  lud16: user.lud16,
                  metadata_updated_at: user.metadata_updated_at,
                  created_at: user.created_at,
                  last_seen: user.last_seen
                }
              })

            socket =
              socket
              |> assign(:current_user, user)
              |> assign(:authenticated, true)
              |> assign(:auth_step, :authenticated)
              |> assign(:loading, false)
              |> assign(:error_message, nil)
              |> put_flash(:info, "Creating session...")

            Logger.info("User authenticated: #{User.short_pubkey(user)}")

            {:noreply, socket}

          {:error, _reason} ->
            socket =
              socket
              |> assign(:loading, false)
              |> assign(:error_message, "Invalid public key format")
              |> assign(:auth_step, :error)

            {:noreply, socket}
        end

      {:error, reason} ->
        Logger.warning("Authentication failed: #{inspect(reason)}")

        socket =
          socket
          |> assign(:loading, false)
          |> assign(:auth_step, :ready_to_auth)
          |> assign(:error_message, format_auth_error(reason))
          |> put_flash(:error, "Authentication failed")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("nostr_pubkey_received", %{"pubkey" => pubkey}, socket) do
    Logger.info("Received pubkey: #{pubkey}")

    # Try to load existing user data
    case Auth.load_user(pubkey) do
      {:ok, user} ->
        updated_user = User.update_last_seen(user)
        Auth.store_user(updated_user)

        socket = assign(socket, :current_user, updated_user)
        {:noreply, socket}

      {:error, :not_found} ->
        # New user
        case User.new(pubkey) do
          %User{} = user ->
            socket = assign(socket, :current_user, user)
            {:noreply, socket}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Invalid public key format")}
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("nostr_error", %{"error" => error, "details" => details}, socket) do
    Logger.error("Nostr error: #{error} - #{details}")

    socket =
      socket
      |> assign(:loading, false)
      |> assign(:error_message, error)
      |> put_flash(:error, "Nostr error: #{error}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("logout", _params, socket) do
    socket =
      socket
      |> assign(:current_user, nil)
      |> assign(:authenticated, false)
      |> assign(:auth_step, :ready_to_auth)
      |> assign(:challenge, nil)
      |> assign(:error_message, nil)
      |> put_flash(:info, "Logged out successfully")

    # Clear browser extension session
    socket = push_event(socket, "nostr_logout", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_profile", %{"profile" => profile_params}, socket) do
    if socket.assigns.authenticated do
      user = socket.assigns.current_user

      # Update user with new profile data
      updated_user = %{
        user
        | name: Map.get(profile_params, "name"),
          display_name: Map.get(profile_params, "display_name"),
          about: Map.get(profile_params, "about"),
          picture: Map.get(profile_params, "picture"),
          nip05: Map.get(profile_params, "nip05"),
          lud16: Map.get(profile_params, "lud16")
      }

      # Store updated user
      Auth.store_user(updated_user)

      # Send to JavaScript to create and sign metadata event
      socket = push_event(socket, "update_profile", profile_params)

      socket =
        socket
        |> assign(:current_user, updated_user)
        |> put_flash(:info, "Profile updated successfully")

      {:noreply, socket}
    else
      socket = put_flash(socket, :error, "Authentication required")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("profile_updated", %{"signed_event" => signed_event}, socket) do
    Logger.info("Profile metadata event signed: #{inspect(signed_event)}")

    # Publish the metadata event to Nostr relays
    # metadata_event = Event.from_map(signed_event)

    # Here you would publish to Nostr relays using the Client
    # For now, just log it
    Logger.info("Would publish metadata event to Nostr relays")

    {:noreply, socket}
  end

  @impl true
  def handle_event("go_to_portfolio", _params, socket) do
    if socket.assigns.authenticated do
      {:noreply, push_navigate(socket, to: "/portfolio")}
    else
      socket = put_flash(socket, :error, "Authentication required")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("go_to_trading", _params, socket) do
    if socket.assigns.authenticated do
      {:noreply, push_navigate(socket, to: "/trading")}
    else
      socket = put_flash(socket, :error, "Authentication required")
      {:noreply, socket}
    end
  end

  # Private helper functions

  defp subscribe_to_user_metadata(pubkey) do
    # Subscribe to metadata events for this user
    # filters = Auth.metadata_filters(pubkey)

    # This would use the Nostr.Client to subscribe
    # For now, just log the intention
    Logger.info("Would subscribe to metadata for user: #{pubkey}")
  end

  defp format_auth_error(:invalid_signature), do: "Invalid signature"
  defp format_auth_error(:invalid_challenge), do: "Invalid challenge"
  defp format_auth_error(:invalid_timestamp), do: "Invalid timestamp"
  defp format_auth_error(reason), do: "Authentication error: #{inspect(reason)}"
end
