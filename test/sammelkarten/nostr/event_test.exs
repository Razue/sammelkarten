defmodule Sammelkarten.Nostr.EventTest do
  use ExUnit.Case, async: true
  alias Sammelkarten.Nostr.Event
  alias Sammelkarten.Nostr.Signer

  test "build, sign, verify roundtrip" do
    {:ok, %{priv: priv, pub: pub}} = Signer.generate_keypair()

    ev = Event.new(pub, 32121, ~s({"demo":true}), [["d", "card:demo"], ["name", "Demo"]])

    {:ok, signed} = Signer.sign(ev, priv)
    assert signed.id
    assert {:ok, true} = Signer.verify(signed)
    assert Event.valid?(signed)
  end
end
