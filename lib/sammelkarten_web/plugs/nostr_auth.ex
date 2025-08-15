defmodule SammelkartenWeb.Plugs.NostrAuth do
  @moduledoc """
  Plug for Nostr-based authentication and session management.

  This plug provides:
  - Session-based Nostr user authentication
  - User data storage and retrieval from sessions
  - Authentication helper functions for LiveViews
  """

  import Plug.Conn
  # import Phoenix.Controller

  alias Sammelkarten.Nostr.{User, Auth}
  require Logger

  @doc """
  Stores a Nostr user in the session after successful authentication.
  """
  def put_nostr_user(conn, user) do
    user_data = %{
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

    conn
    |> put_session(:nostr_user, user_data)
    |> put_session(:nostr_authenticated, true)
  end

  @doc """
  Retrieves a Nostr user from the session.
  """
  def get_nostr_user(conn) do
    if get_session(conn, :nostr_authenticated) do
      case get_session(conn, :nostr_user) do
        nil ->
          {:error, :no_user_data}

        user_data ->
          user = struct(User, user_data)
          {:ok, user}
      end
    else
      {:error, :not_authenticated}
    end
  end

  @doc """
  Clears Nostr user from session (logout).
  """
  def clear_nostr_user(conn) do
    conn
    |> delete_session(:nostr_user)
    |> delete_session(:nostr_authenticated)
  end

  @doc """
  Checks if the current connection has an authenticated Nostr user.
  """
  def nostr_authenticated?(conn) do
    get_session(conn, :nostr_authenticated) == true
  end

  @doc """
  Helper function for LiveViews to get Nostr user from socket.
  """
  def get_nostr_user_from_socket(socket) do
    # Extract session from socket and get user
    # This is used in LiveView mount/3 callbacks
    case Phoenix.LiveView.get_connect_info(socket, :session) do
      %{"nostr_authenticated" => true, "nostr_user" => user_data} when user_data != nil ->
        user = struct(User, user_data)
        {:ok, user}

      _ ->
        {:error, :not_authenticated}
    end
  end

  @doc """
  Helper function to get user from LiveView assigns (if set during mount).
  """
  def get_current_nostr_user(socket_or_assigns) do
    case socket_or_assigns do
      %Phoenix.LiveView.Socket{assigns: assigns} ->
        case assigns do
          %{current_nostr_user: user} -> {:ok, user}
          _ -> {:error, :not_set}
        end

      %{current_nostr_user: user} ->
        {:ok, user}

      _ ->
        {:error, :not_set}
    end
  end

  @doc """
  Updates the user's last seen timestamp in both session and database.
  """
  def update_last_seen(conn, user) do
    updated_user = User.update_last_seen(user)

    # Store updated user in database
    Auth.store_user(updated_user)

    # Update session with new user data
    put_nostr_user(conn, updated_user)
  end
end
