defmodule Sammelkarten.Nostr.IntegrationTest do
  use ExUnit.Case, async: false
  # alias Sammelkarten.Nostr.Publisher
  alias Sammelkarten.Nostr.Indexer
  alias Sammelkarten.Nostr.Event
  alias Sammelkarten.Nostr.Signer

  setup_all do
    # Start the indexer for integration tests
    if !GenServer.whereis(Indexer) do
      {:ok, _pid} = Indexer.start_link()
    end

    :ok
  end

  setup do
    # Clear ETS tables before each test if they exist
    try do
      :ets.delete_all_objects(:nostr_cards)
      :ets.delete_all_objects(:nostr_offers)
      :ets.delete_all_objects(:nostr_executions)
      :ets.delete_all_objects(:nostr_collections)
      :ets.delete_all_objects(:nostr_portfolios)
    rescue
      # Tables might not exist yet
      ArgumentError -> :ok
    end

    :ok
  end

  describe "publish → relay → indexer flow" do
    test "card definition publish and index" do
      {:ok, %{priv: priv, pub: pub}} = Signer.generate_keypair()

      card_map = %{
        card_id: "integration-test-card",
        name: "Integration Test Card",
        description: "Test card for integration testing",
        rarity: "legendary"
      }

      # Test card definition publishing
      event = Event.card_definition(pub, card_map)
      {:ok, signed_event} = Signer.sign(event, priv)

      # Simulate indexer processing via PubSub
      # Phoenix.PubSub.broadcast(Sammelkarten.PubSub, "nostr_events", {:nostr_event, signed_event})
      Indexer.index_event(signed_event)

      # Allow processing time
      Process.sleep(50)

      # Verify card was indexed
      {:ok, indexed_card} = Indexer.fetch_card("integration-test-card")
      assert indexed_card.card_id == "integration-test-card"
      assert indexed_card.name == "Integration Test Card"
    end

    # test "trade offer lifecycle" do
    #   {:ok, %{priv: priv, pub: pub}} = Signer.generate_keypair()

    #   # First create a card
    #   card_map = %{
    #     card_id: "test-card-123",
    #     name: "Test Card",
    #     description: "Test",
    #     rarity: "common"
    #   }

    #   card_event = Event.card_definition(pub, card_map)
    #   {:ok, signed_card} = Signer.sign(card_event, priv)
    #   Phoenix.PubSub.broadcast(Sammelkarten.PubSub, "nostr_events", {:nostr_event, signed_card})

    #   # Create trade offer
    #   offer_data = %{
    #     card_id: "test-card-123",
    #     offer_type: :buy,
    #     price: 1000,
    #     quantity: 1,
    #     expires_at: System.system_time(:second) + 86400
    #   }

    #   offer_event = Event.trade_offer(pub, offer_data)
    #   {:ok, signed_offer} = Signer.sign(offer_event, priv)
    #   Phoenix.PubSub.broadcast(Sammelkarten.PubSub, "nostr_events", {:nostr_event, signed_offer})

    #   Process.sleep(50)

    #   # Verify offer was indexed
    #   open_offers = Indexer.list_open_offers()
    #   assert length(open_offers) == 1
    #   assert hd(open_offers).card_id == "test-card-123"
    #   assert hd(open_offers).price == 1000

    #   # Execute the offer
    #   execution_data = %{
    #     offer_id: signed_offer.id,
    #     buyer_pubkey: pub,
    #     seller_pubkey: pub,
    #     card_id: "test-card-123",
    #     quantity: 1,
    #     price: 1000
    #   }

    #   execution_event = Event.trade_execution(pub, execution_data)
    #   {:ok, signed_execution} = Signer.sign(execution_event, priv)

    #   Phoenix.PubSub.broadcast(
    #     Sammelkarten.PubSub,
    #     "nostr_events",
    #     {:nostr_event, signed_execution}
    #   )

    #   Process.sleep(50)

    #   # Verify execution was indexed
    #   executions = Indexer.list_executions()
    #   assert length(executions) == 1
    #   assert hd(executions).offer_id == signed_offer.id
    # end

    # test "user collection snapshot" do
    #   {:ok, %{priv: priv, pub: pub}} = Signer.generate_keypair()

    #   collection_data = %{
    #     "card1" => 5,
    #     "card2" => 3,
    #     "rare-card" => 1
    #   }

    #   collection_event = Event.user_collection(pub, collection_data)
    #   {:ok, signed_collection} = Signer.sign(collection_event, priv)

    #   Phoenix.PubSub.broadcast(
    #     Sammelkarten.PubSub,
    #     "nostr_events",
    #     {:nostr_event, signed_collection}
    #   )

    #   Process.sleep(50)

    #   # Verify collection was indexed
    #   collections = Indexer.list_user_collections()
    #   assert length(collections) == 1
    #   collection = hd(collections)
    #   assert collection.pubkey == pub
    #   assert collection.cards["card1"] == 5
    #   assert collection.cards["rare-card"] == 1
    # end

    # test "portfolio snapshot" do
    #   {:ok, %{priv: priv, pub: pub}} = Signer.generate_keypair()

    #   portfolio_data = %{
    #     total_value: 75000,
    #     total_cards: 15,
    #     total_pnl: 12000,
    #     card_values: %{
    #       "bitcoin-card" => 50000,
    #       "ethereum-card" => 25000
    #     }
    #   }

    #   portfolio_event = Event.portfolio_snapshot(pub, portfolio_data)
    #   {:ok, signed_portfolio} = Signer.sign(portfolio_event, priv)

    #   Phoenix.PubSub.broadcast(
    #     Sammelkarten.PubSub,
    #     "nostr_events",
    #     {:nostr_event, signed_portfolio}
    #   )

    #   Process.sleep(50)

    #   # Verify portfolio was indexed
    #   portfolios = Indexer.list_portfolios()
    #   assert length(portfolios) == 1
    #   portfolio = hd(portfolios)
    #   assert portfolio.total_value == 75000
    #   assert portfolio.total_cards == 15
    #   assert portfolio.card_values["bitcoin-card"] == 50000
    # end
  end

  describe "error handling" do
    test "invalid event rejected by indexer" do
      # Create malformed event
      invalid_event = %Event{
        id: "invalid-id",
        pubkey: "invalid-pubkey",
        created_at: System.system_time(:second),
        # Trade offer
        kind: 32123,
        # Missing required tags
        tags: [],
        content: "{}",
        sig: "invalid-signature"
      }

      Phoenix.PubSub.broadcast(Sammelkarten.PubSub, "nostr_events", {:nostr_event, invalid_event})
      Process.sleep(50)

      # Should not be indexed
      offers = Indexer.list_open_offers()
      assert length(offers) == 0
    end

    test "duplicate events handled gracefully" do
      {:ok, %{priv: priv, pub: pub}} = Signer.generate_keypair()

      card_map = %{
        card_id: "duplicate-test",
        name: "Duplicate Test",
        description: "Test",
        rarity: "common"
      }

      event = Event.card_definition(pub, card_map)
      {:ok, signed_event} = Signer.sign(event, priv)

      # Process same event twice
      # Phoenix.PubSub.broadcast(Sammelkarten.PubSub, "nostr_events", {:nostr_event, signed_event})
      # Phoenix.PubSub.broadcast(Sammelkarten.PubSub, "nostr_events", {:nostr_event, signed_event})
      Indexer.index_event(signed_event)
      Indexer.index_event(signed_event)

      Process.sleep(50)

      # Should only have one card indexed
      cards = Indexer.list_cards()
      duplicate_cards = Enum.filter(cards, fn card -> card.card_id == "duplicate-test" end)
      assert length(duplicate_cards) == 1
    end
  end

  describe "performance benchmarks" do
    test "event processing latency" do
      {:ok, %{priv: priv, pub: pub}} = Signer.generate_keypair()

      card_map = %{
        card_id: "perf-test",
        name: "Performance Test",
        description: "Test",
        rarity: "common"
      }

      event = Event.card_definition(pub, card_map)

      # Measure signing time
      {sign_time, {:ok, signed_event}} = :timer.tc(fn -> Signer.sign(event, priv) end)
      # < 50ms
      assert sign_time < 50_000

      # Measure indexing time
      {index_time, :ok} =
        :timer.tc(fn ->
          # Phoenix.PubSub.broadcast(Sammelkarten.PubSub, "nostr_events", {:nostr_event, signed_event})
          Indexer.index_event(signed_event)
          # Wait for processing
          Process.sleep(10)
        end)

      # < 100ms
      assert index_time < 100_000

      # Verify indexing worked
      {:ok, indexed_card} = Indexer.fetch_card("perf-test")
      assert indexed_card.card_id == "perf-test"
    end
  end
end
