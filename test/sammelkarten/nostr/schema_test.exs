defmodule Sammelkarten.Nostr.SchemaTest do
  use ExUnit.Case, async: true
  alias Sammelkarten.Nostr.{Event, Schema}

  test "valid card definition" do
    ev =
      Event.new("pub", 32121, "{}", [
        ["d", "card:alpha-001"],
        ["name", "Alpha"],
        ["rarity", "rare"],
        ["set", "Base"]
      ])

    assert {:ok, _} = Schema.validate(ev)
  end

  test "invalid trade offer missing quantity" do
    ev =
      Event.new("pub", 32123, "{}", [["card", "alpha-001"], ["type", "sell"], ["price", "1000"]])

    assert {:error, issues} = Schema.validate(ev)
    assert {:quantity, :invalid} in issues or :quantity in issues
  end
end
