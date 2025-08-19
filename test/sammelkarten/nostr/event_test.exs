defmodule Sammelkarten.Nostr.EventTest do
  use ExUnit.Case, async: true
  alias Sammelkarten.Nostr.{Event, Signer}

  test "build, sign, verify roundtrip" do
    {:ok, %{priv: priv, pub: pub}} = Signer.generate_keypair()

    ev = Event.new(pub, 32121, ~s({"demo":true}), [["d", "card:demo"], ["name", "Demo"]])

    {:ok, signed} = Signer.sign(ev, priv)
    assert signed.id
    assert {:ok, true} = Signer.verify(signed)
    assert Event.valid?(signed)
  end

  describe "event builders" do
    setup do
      {:ok, %{priv: priv, pub: pub}} = Signer.generate_keypair()
      {:ok, %{priv: priv, pub: pub}}
    end

    test "card_definition creates valid event", %{pub: pub} do
      card_map = %{
        card_id: "test-card-123",
        name: "Test Card",
        description: "A test collectible card",
        rarity: "common"
      }

      event = Event.card_definition(pub, card_map)
      event_id = Event.calculate_id(event)
      event_with_id = %{event | id: event_id}
      
      assert event_with_id.kind == 32121
      assert event_with_id.pubkey == pub
      assert Enum.any?(event_with_id.tags, fn [tag, value] -> tag == "d" and value == "card:test-card-123" end)
      assert event_with_id.id != nil
    end

    test "trade_offer creates valid event", %{pub: pub} do
      offer_data = %{
        card_id: "test-card-123",
        offer_type: :buy,
        price: 1000,
        quantity: 1,
        expires_at: System.system_time(:second) + 86400
      }

      event = Event.trade_offer(pub, offer_data)
      event_id = Event.calculate_id(event)
      event_with_id = %{event | id: event_id}

      assert event_with_id.kind == 32123
      assert event_with_id.pubkey == pub
      assert Enum.any?(event_with_id.tags, fn [tag, value] -> tag == "card" and value == "test-card-123" end)
      assert Enum.any?(event_with_id.tags, fn [tag, value] -> tag == "type" and value == "buy" end)
      assert event_with_id.id != nil
    end

    test "trade_execution creates valid event", %{pub: pub} do
      execution_data = %{
        offer_id: "abc123",
        buyer_pubkey: "buyer123",
        seller_pubkey: "seller123",
        card_id: "card123",
        quantity: 1,
        price: 1000
      }

      event = Event.trade_execution(pub, execution_data)
      event_id = Event.calculate_id(event)
      event_with_id = %{event | id: event_id}

      assert event_with_id.kind == 32124
      assert event_with_id.pubkey == pub
      assert Enum.any?(event_with_id.tags, fn [tag, _value, _marker] -> tag == "e" end)
      assert event_with_id.id != nil
    end

    test "user_collection creates valid event", %{pub: pub} do
      collection_data = %{
        "card1" => 5,
        "card2" => 3,
        "card3" => 1
      }

      event = Event.user_collection(pub, collection_data)
      event_id = Event.calculate_id(event)
      event_with_id = %{event | id: event_id}

      assert event_with_id.kind == 32122
      assert event_with_id.pubkey == pub
      assert Enum.any?(event_with_id.tags, fn [tag, _value] -> tag == "d" end)
      assert event_with_id.id != nil
    end

    test "portfolio_snapshot creates valid event", %{pub: pub} do
      portfolio_data = %{
        total_value: 50000,
        total_cards: 10,
        total_pnl: 5000,
        card_values: %{"card1" => 25000, "card2" => 25000}
      }

      event = Event.portfolio_snapshot(pub, portfolio_data)
      event_id = Event.calculate_id(event)
      event_with_id = %{event | id: event_id}

      assert event_with_id.kind == 32126
      assert event_with_id.pubkey == pub
      assert Enum.any?(event_with_id.tags, fn [tag, _value] -> tag == "d" end)
      assert event_with_id.id != nil
    end
  end

  describe "signing and verification" do
    test "consistent event IDs for same content" do
      {:ok, %{pub: pub}} = Signer.generate_keypair()
      
      card_map = %{card_id: "test", name: "Test", description: "Test", rarity: "common"}
      
      event1 = Event.card_definition(pub, card_map)
      event2 = Event.card_definition(pub, card_map)
      
      # Force same timestamp
      event2 = %{event2 | created_at: event1.created_at}
      
      assert event1.id == event2.id
    end

    test "different content produces different IDs" do
      {:ok, %{pub: pub}} = Signer.generate_keypair()
      
      card1 = %{card_id: "card1", name: "Card 1", description: "First", rarity: "common"}
      card2 = %{card_id: "card2", name: "Card 2", description: "Second", rarity: "rare"}
      
      event1 = Event.card_definition(pub, card1)
      event1_id = Event.calculate_id(event1)
      event1 = %{event1 | id: event1_id}
      
      event2 = Event.card_definition(pub, card2)
      event2_id = Event.calculate_id(event2) 
      event2 = %{event2 | id: event2_id}
      
      assert event1.id != nil
      assert event2.id != nil
      assert event1.id != event2.id
    end

    test "sign and verify cycle" do
      {:ok, %{priv: priv, pub: pub}} = Signer.generate_keypair()
      
      card_map = %{card_id: "test", name: "Test", description: "Test", rarity: "common"}
      event = Event.card_definition(pub, card_map)
      
      {:ok, signed_event} = Signer.sign(event, priv)
      
      assert signed_event.sig != nil
      assert byte_size(signed_event.sig) > 0
      assert {:ok, true} = Signer.verify(signed_event)
    end
  end

  describe "JSON serialization" do
    test "roundtrip preserves event structure" do
      {:ok, %{pub: pub}} = Signer.generate_keypair()
      
      card_map = %{card_id: "test", name: "Test", description: "Test", rarity: "common"}
      original = Event.card_definition(pub, card_map)
      
      json = Jason.encode!(original)
      {:ok, decoded} = Jason.decode(json, keys: :atoms)
      reconstructed = struct(Event, decoded)
      
      assert original.id == reconstructed.id
      assert original.pubkey == reconstructed.pubkey
      assert original.kind == reconstructed.kind
      assert original.content == reconstructed.content
      assert original.tags == reconstructed.tags
    end
  end
end
