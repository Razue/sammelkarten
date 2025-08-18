defmodule Sammelkarten.Nostr.TestUsers do
  @moduledoc """
  Test users with NIP-05 identifiers for demonstration purposes.

  This module provides realistic test users with NIP-05 identifiers
  that can be used in the exchange interface to demonstrate the functionality.
  """

  alias Sammelkarten.Nostr.User

  @doc """
  Get a list of test users with NIP-05 identifiers.
  """
  def test_users do
    [
      %User{
        pubkey: "014ab632dc75ca31f0db26e9b2a4ee4ef94173d03f45d3358dc6f0241472a867",
        npub: "npub1q99tvvkuwh9rruxmym5m9f8wfmu5zu7s8azaxdvdcmczg9rj4pnsq8mjtn",
        name: "Ralph",
        display_name: "Ralph21",
        nip05: "Ralph21@primal.net",
        about: "Bitcoin enthusiast and card collector",
        created_at: DateTime.utc_now()
      },
      %User{
        pubkey: "7d7b8c9a1f2e3d4c5b6a9f8e7d6c5b4a3f2e1d9c8b7a6f5e4d3c2b1a9f8e7d6c",
        npub: "npub1049ae0gln03dck0d482w0kktvjjh9cr6epxh5e84j6xuvn5x74kqm8r7z2",
        name: "Fab",
        display_name: "Fab",
        nip05: "fab@getalby.com",
        about: "Lightning Network developer",
        created_at: DateTime.utc_now()
      },
      %User{
        pubkey: "a1b2c3d4e5f6789012345678901234567890123456789012345678901234567890",
        npub: "npub1583v84855mqjqy3536ej5q8g2eepqg34d6qjqy3536ej5q8g2eukqm2p45",
        name: "Altan",
        display_name: "Altan",
        nip05: "altan@iris.to",
        about: "Nostr protocol contributor",
        created_at: DateTime.utc_now()
      },
      %User{
        pubkey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        npub: "npub1zg696ey5404lzg35v6u309dlme3g5an5jzk6lhe35v6u309dlmhuq7jk98",
        name: "Sticker21M",
        display_name: "Sticker21M",
        nip05: "sticker21m@current.fyi",
        about: "Digital artist and sticker creator",
        created_at: DateTime.utc_now()
      },
      %User{
        pubkey: "fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321",
        npub: "npub1lmkt5zvfv4ptyl7mhtyf034x5x0mh6yf034x5x0mh6yf034x5xhqx8m4n7",
        name: "Markus Turm",
        display_name: "Markus_Turm",
        nip05: "markus@primal.net",
        about: "Bitcoin educator and podcaster",
        created_at: DateTime.utc_now()
      },
      %User{
        pubkey: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        npub: "npub1409az33546u5pttlme35v6u509dlme35v6u509dlme35v6u509dlmqr2x78",
        name: "Maulwurf",
        display_name: "Maulwurf",
        nip05: "maulwurf@coinos.io",
        about: "Privacy advocate and educator",
        created_at: DateTime.utc_now()
      },
      %User{
        pubkey: "567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234",
        npub: "npub126uy5ttlme35p26uy5ttlme35p26uy5ttlme35p26uy5ttlme35p2kqh9m2",
        name: "Seedorchris",
        display_name: "Seed or Chris",
        nip05: "seedorchris@nostrid.io",
        about: "Bitcoin seed phrase specialist",
        created_at: DateTime.utc_now()
      }
    ]
  end

  @doc """
  Get a test user by their pubkey.
  """
  def get_user_by_pubkey(pubkey) do
    Enum.find(test_users(), fn user -> user.pubkey == pubkey end)
  end

  @doc """
  Get a test user by their NIP-05 identifier.
  """
  def get_user_by_nip05(nip05) do
    Enum.find(test_users(), fn user -> user.nip05 == nip05 end)
  end

  @doc """
  Get a random test user.
  """
  def random_user do
    test_users() |> Enum.random()
  end

  @doc """
  Get a list of pubkeys for all test users.
  """
  def test_user_pubkeys do
    Enum.map(test_users(), & &1.pubkey)
  end

  @doc """
  Check if a pubkey belongs to a test user with NIP-05.
  """
  def has_nip05?(pubkey) do
    case get_user_by_pubkey(pubkey) do
      %User{nip05: nip05} when is_binary(nip05) -> true
      _ -> false
    end
  end

  @doc """
  Get display name for a pubkey, preferring NIP-05 format.
  """
  def display_name_for_pubkey(pubkey) do
    case get_user_by_pubkey(pubkey) do
      %User{} = user -> User.display_name(user)
      nil -> User.short_pubkey(%{pubkey: pubkey})
    end
  end

  @doc """
  Get NIP-05 display format for a pubkey.
  """
  def nip05_display_for_pubkey(pubkey) do
    case get_user_by_pubkey(pubkey) do
      %User{} = user -> User.format_nip05_display(user)
      nil -> nil
    end
  end
end
