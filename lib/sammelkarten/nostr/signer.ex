defmodule Sammelkarten.Nostr.Signer do
  @moduledoc """
  Wrapper API around Sammelkarten.Nostr.Event signing & key utilities.
  """
  alias Sammelkarten.Nostr.Event

  @spec generate_keypair() :: {:ok, %{priv: String.t(), pub: String.t()}} | {:error, term}
  def generate_keypair do
    priv = Event.generate_private_key()

    with {:ok, pub} <- Event.private_key_to_public(priv) do
      {:ok, %{priv: priv, pub: pub}}
    end
  end

  @spec sign(Event.t(), String.t()) :: {:ok, Event.t()} | {:error, term}
  def sign(ev, priv_hex), do: Event.sign(ev, priv_hex)

  @spec verify(Event.t()) :: {:ok, boolean} | {:error, term}
  def verify(ev), do: Event.verify(ev)
end
