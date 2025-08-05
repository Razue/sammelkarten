defmodule Sammelkarten.CardsTest do
  use ExUnit.Case, async: true

  alias Sammelkarten.Cards

  setup do
    # Stop Mnesia and delete schema for a clean state
    :mnesia.stop()
    :mnesia.delete_schema([node()])
    {:ok, _} = Application.ensure_all_started(:mnesia)
    :mnesia.create_schema([node()])
    :mnesia.start()

    :mnesia.create_table(:cards,
      attributes: [
        :id,
        :name,
        :slug,
        :image_path,
        :current_price,
        :price_change_24h,
        :price_change_percentage,
        :rarity,
        :description,
        :last_updated
      ]
    )

    :mnesia.create_table(:price_history, attributes: [:id, :card_id, :price, :timestamp, :volume])
    :ok
  end

  test "create_card/1 and get_card/1" do
    attrs = %{
      name: "Test Card",
      image_path: "/images/test.jpg",
      current_price: 100,
      rarity: "rare",
      description: "A test card",
      last_updated: DateTime.utc_now()
    }

    {:ok, card} = Cards.create_card(attrs)
    assert card.name == "Test Card"
    assert card.current_price == 100
    assert card.rarity == "rare"

    {:ok, found} = Cards.get_card(card.id)
    assert found.id == card.id
    assert found.name == card.name
    assert found.slug == "test"
  end

  test "list_cards/0 returns all cards" do
    {:ok, card1} =
      Cards.create_card(%{
        name: "Card 1",
        image_path: "/images/1.jpg",
        current_price: 10,
        rarity: "common",
        description: "",
        last_updated: DateTime.utc_now()
      })

    {:ok, card2} =
      Cards.create_card(%{
        name: "Card 2",
        image_path: "/images/2.jpg",
        current_price: 20,
        rarity: "rare",
        description: "",
        last_updated: DateTime.utc_now()
      })

    {:ok, cards} = Cards.list_cards()
    ids = Enum.map(cards, & &1.id)
    assert card1.id in ids
    assert card2.id in ids
  end

  test "update_card_price/2 updates price and creates price history" do
    {:ok, card} =
      Cards.create_card(%{
        name: "Card",
        image_path: "/images/1.jpg",
        current_price: 50,
        rarity: "common",
        description: "",
        last_updated: DateTime.utc_now()
      })

    {:ok, updated} = Cards.update_card_price(card.id, 75)
    assert updated.current_price == 75
    assert updated.price_change_24h == 25
    assert updated.price_change_percentage == 50.0
    {:ok, history} = Cards.get_price_history(card.id)
    assert Enum.any?(history, &(&1.price == 75))
  end

  test "get_card_by_slug/1 finds card by slug" do
    attrs = %{
      name: "Jonas Nick", 
      image_path: "/images/cards/JONAS_NICK.jpg",
      current_price: 100,
      rarity: "rare",
      description: "A test card",
      last_updated: DateTime.utc_now()
    }

    {:ok, card} = Cards.create_card(attrs)
    assert card.slug == "jonas_nick"
    
    {:ok, found} = Cards.get_card_by_slug("jonas_nick")
    assert found.id == card.id
    assert found.name == card.name
    assert found.slug == "jonas_nick"
    
    # Test not found
    assert {:error, :not_found} = Cards.get_card_by_slug("nonexistent")
  end
  
  test "slug generation from image path" do
    test_cases = [
      {"/images/cards/JONAS_NICK.jpg", "jonas_nick"},
      {"/images/cards/TOXIC_BOOSTER.jpg", "toxic_booster"},
      {"/images/cards/BitcoinHotel_Holo.jpg", "bitcoinhotel_holo"}
    ]
    
    for {image_path, expected_slug} <- test_cases do
      {:ok, card} = Cards.create_card(%{
        name: "Test Card",
        image_path: image_path,
        current_price: 100,
        rarity: "common"
      })
      
      assert card.slug == expected_slug
    end
  end

  test "delete_card/1 removes card and price history" do
    {:ok, card} =
      Cards.create_card(%{
        name: "Card",
        image_path: "/images/1.jpg",
        current_price: 50,
        rarity: "common",
        description: "",
        last_updated: DateTime.utc_now()
      })

    {:ok, _} = Cards.update_card_price(card.id, 60)
    assert :ok = Cards.delete_card(card.id)
    assert {:error, :not_found} = Cards.get_card(card.id)
    {:ok, history} = Cards.get_price_history(card.id)
    assert history == []
  end
end
