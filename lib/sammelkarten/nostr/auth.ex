defmodule Sammelkarten.Nostr.Auth do
  @moduledoc """
  Nostr authentication module for the Sammelkarten application.

  This module handles:
  - User authentication via Nostr events
  - Challenge/response authentication
  - Session management
  - NIP-07 browser extension integration
  """

  require Phoenix.LiveView
  alias Sammelkarten.Nostr.{Event, User}
  require Logger

  # NIP-42 authentication event kind
  @auth_challenge_kind 22242
  # 5 minutes
  @auth_timeout 300

  @doc """
  Generate an authentication challenge for a user.
  """
  def generate_challenge do
    challenge = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
    expires_at = DateTime.utc_now() |> DateTime.add(@auth_timeout, :second)

    %{
      challenge: challenge,
      expires_at: expires_at
    }
  end

  @doc """
  Create an authentication event that needs to be signed by the user.
  """
  def create_auth_event(pubkey, challenge, relay_url \\ nil) do
    tags = [
      ["challenge", challenge]
    ]

    # Add relay tag if provided (NIP-42)
    tags =
      if relay_url do
        tags ++ [["relay", relay_url]]
      else
        tags
      end

    Event.new(pubkey, @auth_challenge_kind, "", tags)
  end

  @doc """
  Verify an authentication event against a challenge.
  """
  def verify_auth_event(auth_event, challenge, relay_url \\ nil) do
    with :ok <- validate_auth_event_structure(auth_event),
         :ok <- validate_challenge(auth_event, challenge),
         :ok <- validate_relay(auth_event, relay_url),
         :ok <- validate_timestamp(auth_event),
         {:ok, true} <- Event.verify(auth_event) do
      {:ok, auth_event.pubkey}
    else
      {:ok, false} -> {:error, :invalid_signature}
      error -> error
    end
  end

  @doc """
  Authenticate a user session with a signed auth event.
  """
  def authenticate_session(socket, auth_event, challenge) do
    case verify_auth_event(auth_event, challenge) do
      {:ok, pubkey} ->
        case User.new(pubkey) do
          %User{} = user ->
            user = User.update_last_seen(user)

            socket =
              socket
              # |> Phoenix.LiveView.put_flash(:info, "Successfully authenticated with Nostr!")
              |> Phoenix.LiveView.assign_async(:current_user, user)
              |> Phoenix.LiveView.assign_async(:authenticated, true)

            # Store user in database
            store_user(user)

            Logger.info("User authenticated successfully: #{User.short_pubkey(user)}")
            {:ok, socket}

          {:error, _reason} ->
            socket =
              socket
              |> Phoenix.LiveView.put_flash(:error, "Invalid public key format")

            {:error, socket}
        end

      {:error, reason} ->
        Logger.warning("Authentication failed: #{inspect(reason)}")

        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, "Authentication failed: #{format_error(reason)}")
          |> Phoenix.LiveView.assign_async(:authenticated, false)

        {:error, socket}
    end
  end

  @doc """
  Logout a user by clearing their session.
  """
  def logout_session(socket) do
    socket
    |> Phoenix.LiveView.assign_async(:current_user, nil)
    |> Phoenix.LiveView.assign_async(:authenticated, false)

    # |> Phoenix.LiveView.put_flash(:info, "Successfully logged out")
  end

  @doc """
  Check if a user is authenticated in the current session.
  """
  def authenticated?(socket) do
    Phoenix.LiveView.connected?(socket) &&
      socket.assigns[:authenticated] == true &&
      socket.assigns[:current_user] != nil
  end

  @doc """
  Get the current authenticated user from the socket.
  """
  def current_user(socket) do
    socket.assigns[:current_user]
  end

  @doc """
  Require authentication for a LiveView action.
  """
  def require_auth(socket, success_fun) do
    if authenticated?(socket) do
      success_fun.(socket)
    else
      socket
      |> Phoenix.LiveView.put_flash(:error, "Authentication required")
      |> Phoenix.LiveView.redirect(to: "/auth")
    end
  end

  @doc """
  Generate a NIP-07 authentication request for browser extensions.
  """
  def create_nip07_auth_request(challenge, relay_url \\ nil) do
    %{
      type: "signEvent",
      event: %{
        kind: @auth_challenge_kind,
        tags:
          [
            ["challenge", challenge],
            if(relay_url, do: ["relay", relay_url], else: nil)
          ]
          |> Enum.filter(& &1),
        content: "",
        created_at: DateTime.utc_now() |> DateTime.to_unix()
      }
    }
  end

  @doc """
  Validate a NIP-07 authentication response.
  """
  def validate_nip07_response(response, challenge) do
    case response do
      %{"event" => event_data} ->
        auth_event = Event.from_map(event_data)
        verify_auth_event(auth_event, challenge)

      %{"error" => error} ->
        {:error, {:nip07_error, error}}

      _ ->
        {:error, :invalid_response}
    end
  end

  @doc """
  Create authentication filters for subscribing to user metadata.
  """
  def metadata_filters(pubkey) do
    [
      %{
        "authors" => [pubkey],
        # Metadata events
        "kinds" => [0],
        "limit" => 1
      }
    ]
  end

  @doc """
  Store or update user information in the database.
  """
  def store_user(user) do
    case :mnesia.transaction(fn ->
           # Convert user to Mnesia record format
           user_record = {
             :nostr_users,
             user.pubkey,
             user.npub,
             user.name,
             user.display_name,
             user.about,
             user.picture,
             user.nip05,
             user.lud16,
             user.metadata_updated_at,
             user.created_at,
             user.last_seen
           }

           :mnesia.write(user_record)
         end) do
      {:atomic, :ok} ->
        Logger.debug("User stored successfully: #{User.short_pubkey(user)}")
        :ok

      {:aborted, reason} ->
        Logger.error("Failed to store user: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Load user information from the database.
  """
  def load_user(pubkey) do
    case :mnesia.transaction(fn ->
           :mnesia.read(:nostr_users, pubkey)
         end) do
      {:atomic, [user_record]} ->
        user = mnesia_record_to_user(user_record)
        {:ok, user}

      {:atomic, []} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp validate_auth_event_structure(auth_event) do
    if auth_event.kind == @auth_challenge_kind do
      :ok
    else
      {:error, :invalid_event_kind}
    end
  end

  defp validate_challenge(auth_event, expected_challenge) do
    actual_challenge = Event.get_tag_value(auth_event, "challenge")

    if actual_challenge == expected_challenge do
      :ok
    else
      {:error, :invalid_challenge}
    end
  end

  defp validate_relay(auth_event, expected_relay) do
    if expected_relay do
      actual_relay = Event.get_tag_value(auth_event, "relay")

      if actual_relay == expected_relay do
        :ok
      else
        {:error, :invalid_relay}
      end
    else
      :ok
    end
  end

  defp validate_timestamp(auth_event) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    event_time = auth_event.created_at

    # Allow events from 10 minutes ago to 1 minute in the future
    if event_time >= now - 600 && event_time <= now + 60 do
      :ok
    else
      {:error, :invalid_timestamp}
    end
  end

  defp format_error(:invalid_signature), do: "Invalid signature"
  defp format_error(:invalid_challenge), do: "Invalid challenge"
  defp format_error(:invalid_relay), do: "Invalid relay"
  defp format_error(:invalid_timestamp), do: "Invalid timestamp"
  defp format_error(:invalid_event_kind), do: "Invalid event kind"
  defp format_error({:nip07_error, error}), do: "Browser extension error: #{error}"
  defp format_error(reason), do: "Authentication error: #{inspect(reason)}"

  defp mnesia_record_to_user(
         {:nostr_users, pubkey, npub, name, display_name, about, picture, nip05, lud16,
          metadata_updated_at, created_at, last_seen}
       ) do
    %User{
      pubkey: pubkey,
      npub: npub,
      name: name,
      display_name: display_name,
      about: about,
      picture: picture,
      nip05: nip05,
      lud16: lud16,
      metadata_updated_at: metadata_updated_at,
      created_at: created_at,
      last_seen: last_seen
    }
  end
end
