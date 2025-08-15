defmodule SammelkartenWeb.NostrSessionController do
  @moduledoc """
  Controller for managing Nostr user sessions.

  This controller handles:
  - Creating Nostr user sessions after authentication
  - Destroying Nostr user sessions (logout)
  - Session validation and updates
  """

  use SammelkartenWeb, :controller

  alias Sammelkarten.Nostr.{Auth, User}
  alias SammelkartenWeb.Plugs.NostrAuth
  require Logger

  @doc """
  Creates a new Nostr user session after successful authentication.
  Expected to receive user data and store it in session.
  """
  def create(conn, %{"user" => user_params}) do
    case create_user_from_params(user_params) do
      {:ok, user} ->
        # Store user in session
        conn = NostrAuth.put_nostr_user(conn, user)

        # Store user in database
        Auth.store_user(user)

        Logger.info("Nostr session created for user: #{User.short_pubkey(user)}")

        conn
        |> put_flash(:info, "Successfully authenticated with Nostr!")
        |> redirect(to: "/portfolio")

      {:error, reason} ->
        Logger.error("Failed to create Nostr session: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Authentication failed")
        |> redirect(to: "/auth")
    end
  end

  @doc """
  Destroys the current Nostr user session (logout).
  """
  def delete(conn, _params) do
    conn = NostrAuth.clear_nostr_user(conn)

    conn
    |> put_flash(:info, "Logged out successfully")
    |> redirect(to: "/")
  end

  # Private helper functions

  defp create_user_from_params(user_params) do
    try do
      user = %User{
        pubkey: Map.get(user_params, "pubkey"),
        npub: Map.get(user_params, "npub"),
        name: Map.get(user_params, "name"),
        display_name: Map.get(user_params, "display_name"),
        about: Map.get(user_params, "about"),
        picture: Map.get(user_params, "picture"),
        nip05: Map.get(user_params, "nip05"),
        lud16: Map.get(user_params, "lud16"),
        metadata_updated_at: parse_datetime(Map.get(user_params, "metadata_updated_at")),
        created_at: parse_datetime(Map.get(user_params, "created_at")) || DateTime.utc_now(),
        last_seen: parse_datetime(Map.get(user_params, "last_seen")) || DateTime.utc_now()
      }

      {:ok, user}
    rescue
      e ->
        {:error, e}
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(%DateTime{} = datetime), do: datetime
  defp parse_datetime(_), do: nil
end
