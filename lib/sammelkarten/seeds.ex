defmodule Sammelkarten.Seeds do
  @moduledoc """
  Seeds module for populating initial card data.

  This module creates initial cards based on the available images
  and populates the database with realistic starting data.
  """

  alias Sammelkarten.Cards
  alias Sammelkarten.Card

  require Logger

  @doc """
  Run all seed functions to populate the database.
  """
  def run do
    Logger.info("Starting database seeding...")

    seed_cards()

    Logger.info("Database seeding completed!")
  end

  @doc """
  Create initial cards from available images.
  """
  def seed_cards do
    Logger.info("Creating initial cards...")

    cards_data = [
      %{
        name: "Seed or Chris",
        image_path: "/images/cards/SEED_OR_CHRIS.jpg",
        # €210.00
        current_price: 21000,
        rarity: "rare",
        description:
          "Bitcoin security advocate emphasizing proper seed phrase management. A rare card promoting Bitcoin best practices."
      },
      %{
        name: "Bitcoin Hotel",
        image_path: "/images/cards/BITCOIN_HOTEL.jpg",
        # €150.00
        current_price: 15000,
        rarity: "legendary",
        description:
          "The world's first Bitcoin-native hotel experience. A legendary card representing the intersection of hospitality and cryptocurrency innovation."
      },
      %{
        name: "Blocktrainer",
        image_path: "/images/cards/BLOCKTRAINER.jpg",
        # €85.00
        current_price: 8500,
        rarity: "epic",
        description:
          "Educational pioneer in the Bitcoin space. An epic card honoring those who teach others about cryptocurrency fundamentals."
      },
      %{
        name: "Christian Decker",
        image_path: "/images/cards/CHRISTIAN_DECKER.jpg",
        # €120.00
        current_price: 12000,
        rarity: "legendary",
        description:
          "Bitcoin Core developer and Lightning Network researcher. A legendary card representing technical excellence in Bitcoin development."
      },
      %{
        name: "Jonas Nick",
        image_path: "/images/cards/JONAS_NICK.jpg",
        # €95.00
        current_price: 9500,
        rarity: "epic",
        description:
          "Cryptographer and Bitcoin protocol researcher. An epic card showcasing the mathematical foundations of Bitcoin security."
      },
      %{
        name: "Node Signal",
        image_path: "/images/cards/NODESIGNAL.jpg",
        # €60.00
        current_price: 6000,
        rarity: "rare",
        description:
          "Representing the Bitcoin node network infrastructure. A rare card symbolizing decentralized network participation."
      },
      %{
        name: "Pleb Rap",
        image_path: "/images/cards/PLEBRAP.jpg",
        # €45.00
        current_price: 4500,
        rarity: "uncommon",
        description:
          "Bitcoin culture meets music. An uncommon card celebrating the creative expression within the Bitcoin community."
      },
      %{
        name: "Toxic Booster",
        image_path: "/images/cards/TOXIC_BOOSTER.jpg",
        # €30.00
        current_price: 3000,
        rarity: "common",
        description:
          "The passionate Bitcoin maximalist energy. A common card representing the fierce dedication to Bitcoin principles."
      }
    ]

    # Create cards with some price variation
    Enum.each(cards_data, fn card_attrs ->
      # Add some random price variation (±10%)
      # -10 to +10
      price_variation = :rand.uniform(21) - 11
      varied_price = trunc(card_attrs.current_price * (1 + price_variation / 100))

      # Calculate initial price change (simulate previous 24h movement)
      # -500 to +500 cents
      initial_change_24h = :rand.uniform(1001) - 501

      initial_change_percentage =
        if varied_price > 0 do
          initial_change_24h / varied_price * 100.0
        else
          0.0
        end

      final_attrs =
        Map.merge(card_attrs, %{
          current_price: varied_price,
          price_change_24h: initial_change_24h,
          price_change_percentage: initial_change_percentage
        })

      case Cards.create_card(final_attrs) do
        {:ok, card} ->
          Logger.info(
            "Created card: #{card.name} (#{card.rarity}) - #{Card.format_price(card.current_price)}"
          )

        {:error, reason} ->
          Logger.error("Failed to create card #{card_attrs.name}: #{inspect(reason)}")
      end
    end)

    Logger.info("Initial cards creation completed!")
  end

  @doc """
  Clear all existing data and reseed.
  """
  def reset_and_seed do
    Logger.warning("Resetting database and reseeding...")

    # Reset tables
    Sammelkarten.Database.reset_tables()

    # Reseed data
    run()
  end

  @doc """
  Check if database needs seeding (no cards exist).
  """
  def needs_seeding? do
    case Cards.list_cards() do
      {:ok, []} -> true
      {:ok, _cards} -> false
      {:error, _} -> true
    end
  end

  @doc """
  Conditionally seed if database is empty.
  """
  def seed_if_empty do
    if needs_seeding?() do
      Logger.info("Database is empty, running initial seed...")
      run()
    else
      Logger.info("Database already contains cards, skipping seed")
    end
  end
end
