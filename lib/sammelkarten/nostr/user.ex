defmodule Sammelkarten.Nostr.User do
  @moduledoc """
  Nostr user data structure and utilities for the Sammelkarten application.

  This module handles:
  - User data management and storage
  - User metadata handling
  - User profile management
  - User preferences and settings
  """

  @type t :: %__MODULE__{
          pubkey: String.t(),
          npub: String.t() | nil,
          name: String.t() | nil,
          display_name: String.t() | nil,
          about: String.t() | nil,
          picture: String.t() | nil,
          nip05: String.t() | nil,
          lud16: String.t() | nil,
          metadata_updated_at: DateTime.t() | nil,
          created_at: DateTime.t(),
          last_seen: DateTime.t() | nil
        }

  defstruct [
    :pubkey,
    :npub,
    :name,
    :display_name,
    :about,
    :picture,
    :nip05,
    :lud16,
    :metadata_updated_at,
    :created_at,
    :last_seen
  ]

  alias Sammelkarten.Nostr.{Event, NIP05}

  @doc """
  Create a new user from a public key.
  """
  def new(pubkey) do
    case Event.pubkey_to_npub(pubkey) do
      {:ok, npub} ->
        %__MODULE__{
          pubkey: pubkey,
          npub: npub,
          created_at: DateTime.utc_now()
        }

      {:error, _reason} ->
        {:error, :invalid_pubkey}
    end
  end

  @doc """
  Create a user from an npub (bech32 public key).
  """
  def from_npub(npub) do
    case Event.npub_to_pubkey(npub) do
      {:ok, pubkey} ->
        case new(pubkey) do
          %__MODULE__{} = user -> {:ok, user}
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Update user metadata from a Nostr metadata event (kind 0).
  """
  def update_metadata(user, metadata_event) do
    if metadata_event.kind == 0 && metadata_event.pubkey == user.pubkey do
      case Jason.decode(metadata_event.content) do
        {:ok, metadata} ->
          {:ok,
           %{
             user
             | name: Map.get(metadata, "name"),
               display_name: Map.get(metadata, "display_name"),
               about: Map.get(metadata, "about"),
               picture: Map.get(metadata, "picture"),
               nip05: Map.get(metadata, "nip05"),
               lud16: Map.get(metadata, "lud16"),
               metadata_updated_at: DateTime.from_unix!(metadata_event.created_at)
           }}

        {:error, _} ->
          {:error, :invalid_metadata}
      end
    else
      {:error, :invalid_event}
    end
  end

  @doc """
  Get the display name for a user (prefers display_name, falls back to name, then nip05, then npub).
  """
  def display_name(user) do
    user.display_name || user.name || format_nip05(user.nip05) || format_npub(user.npub)
  end

  @doc """
  Get a short version of the public key for display.
  """
  def short_pubkey(user) do
    case user.pubkey do
      nil ->
        "unknown"

      pubkey when byte_size(pubkey) >= 16 ->
        prefix = String.slice(pubkey, 0, 8)
        suffix = String.slice(pubkey, -8, 8)
        "#{prefix}...#{suffix}"

      pubkey ->
        pubkey
    end
  end

  @doc """
  Get a short version of the npub for display.
  """
  def short_npub(user) do
    case user.npub do
      nil ->
        "unknown"

      npub when byte_size(npub) >= 16 ->
        # "npub1" + 8 chars
        prefix = String.slice(npub, 0, 12)
        suffix = String.slice(npub, -8, 8)
        "#{prefix}...#{suffix}"

      npub ->
        npub
    end
  end

  @doc """
  Check if the user has complete metadata.
  """
  def has_metadata?(user) do
    user.name != nil || user.display_name != nil
  end

  @doc """
  Update the user's last seen timestamp.
  """
  def update_last_seen(user) do
    %{user | last_seen: DateTime.utc_now()}
  end

  @doc """
  Convert user to map for storage/serialization.
  """
  def to_map(user) do
    %{
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
  end

  @doc """
  Create user from map.
  """
  def from_map(map) when is_map(map) do
    %__MODULE__{
      pubkey: Map.get(map, :pubkey) || Map.get(map, "pubkey"),
      npub: Map.get(map, :npub) || Map.get(map, "npub"),
      name: Map.get(map, :name) || Map.get(map, "name"),
      display_name: Map.get(map, :display_name) || Map.get(map, "display_name"),
      about: Map.get(map, :about) || Map.get(map, "about"),
      picture: Map.get(map, :picture) || Map.get(map, "picture"),
      nip05: Map.get(map, :nip05) || Map.get(map, "nip05"),
      lud16: Map.get(map, :lud16) || Map.get(map, "lud16"),
      metadata_updated_at:
        parse_datetime(Map.get(map, :metadata_updated_at) || Map.get(map, "metadata_updated_at")),
      created_at: parse_datetime(Map.get(map, :created_at) || Map.get(map, "created_at")),
      last_seen: parse_datetime(Map.get(map, :last_seen) || Map.get(map, "last_seen"))
    }
  end

  @doc """
  Create a metadata event for the user.
  """
  def create_metadata_event(user, private_key) do
    metadata =
      %{
        name: user.name,
        display_name: user.display_name,
        about: user.about,
        picture: user.picture,
        nip05: user.nip05,
        lud16: user.lud16
      }
      |> Enum.filter(fn {_k, v} -> v != nil end)
      |> Map.new()

    content = Jason.encode!(metadata)

    Event.new(user.pubkey, 0, content, [])
    |> Event.sign(private_key)
  end

  @doc """
  Validate that a pubkey is properly formatted.
  """
  def valid_pubkey?(pubkey) when is_binary(pubkey) do
    case Base.decode16(pubkey, case: :lower) do
      {:ok, decoded} when byte_size(decoded) == 32 -> true
      _ -> false
    end
  end

  def valid_pubkey?(_), do: false

  @doc """
  Validate that an npub is properly formatted.
  """
  def valid_npub?(npub) when is_binary(npub) do
    case Event.npub_to_pubkey(npub) do
      {:ok, _pubkey} -> true
      _ -> false
    end
  end

  def valid_npub?(_), do: false

  @doc """
  Verify the user's NIP-05 identifier against their public key.
  Returns {:ok, true} if verified, {:error, reason} otherwise.
  """
  def verify_nip05(user) do
    case user.nip05 do
      nil -> {:error, :no_nip05}
      nip05 -> NIP05.verify(nip05, user.pubkey)
    end
  end

  @doc """
  Resolve a NIP-05 identifier to find the associated public key.
  Returns {:ok, pubkey} if successful.
  """
  def resolve_nip05(nip05_identifier) do
    NIP05.resolve(nip05_identifier)
  end

  @doc """
  Check if the user has a verified NIP-05 identifier.
  This performs an actual verification check, not just presence.
  """
  def has_verified_nip05?(user) do
    case verify_nip05(user) do
      {:ok, true} -> true
      _ -> false
    end
  end

  @doc """
  Get a display-friendly version of the NIP-05 identifier.
  Returns just the local part for known verified domains, or full identifier for others.
  """
  def format_nip05_display(user) do
    case user.nip05 do
      nil -> nil
      nip05 -> 
        case NIP05.parse_identifier(nip05) do
          {:ok, local_part, domain} ->
            # For well-known Nostr domains, show just the local part
            if trusted_nip05_domain?(domain) do
              "@#{local_part}"
            else
              "@#{local_part}@#{domain}"
            end
          _ -> 
            nip05
        end
    end
  end

  # Private helper functions

  # Check if a domain is trusted/well-known in the Nostr ecosystem
  defp trusted_nip05_domain?(domain) do
    trusted_domains = [
      "getalby.com",
      "coinos.io", 
      "nostrid.io",
      "zbd.gg",
      "current.fyi",
      "iris.to",
      "primal.net"
    ]
    String.downcase(domain) in trusted_domains
  end

  defp format_npub(nil), do: "unknown"
  defp format_npub(npub), do: short_npub(%{npub: npub})

  defp format_nip05(nil), do: nil
  defp format_nip05(nip05) do
    case NIP05.parse_identifier(nip05) do
      {:ok, local_part, domain} ->
        if trusted_nip05_domain?(domain) do
          "@#{local_part}"
        else
          "@#{local_part}@#{domain}"
        end
      _ -> 
        nip05
    end
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(unix_timestamp) when is_integer(unix_timestamp) do
    DateTime.from_unix!(unix_timestamp)
  end

  defp parse_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil
end
