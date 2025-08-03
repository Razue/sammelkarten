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
        name: "Satoshi",
        image_path: "/images/cards/SATOSHI.jpg",
        # 500000 sats - Most valuable card
        current_price: 79_500,
        rarity: "mythic",
        description:
          "The legendary creator of Bitcoin. A mythic card representing the genesis of the cryptocurrency revolution."
      },
      %{
        name: "Seed or Chris",
        image_path: "/images/cards/SEED_OR_CHRIS.jpg",
        # 210 sats
        current_price: 21_000,
        rarity: "rare",
        description:
          "Bitcoin security advocate emphasizing proper seed phrase management. A rare card promoting Bitcoin best practices."
      },
      %{
        name: "Bitcoin Hotel",
        image_path: "/images/cards/BITCOIN_HOTEL.jpg",
        # 150 sats
        current_price: 36000,
        rarity: "legendary",
        description:
          "The world's first Bitcoin-native hotel experience. A legendary card representing the intersection of hospitality and cryptocurrency innovation."
      },
      %{
        name: "Christian Decker",
        image_path: "/images/cards/CHRISTIAN_DECKER.jpg",
        # 120 sats
        current_price: 21000,
        rarity: "legendary",
        description:
          "Bitcoin Core developer and Lightning Network researcher. A legendary card representing technical excellence in Bitcoin development."
      },
      %{
        name: "Der Gigi",
        image_path: "/images/cards/DER_GIGI.jpg",
        # 110 sats
        current_price: 78000,
        rarity: "legendary",
        description:
          "Bitcoin philosopher and author. A legendary card celebrating profound Bitcoin insights and educational content."
      },
      %{
        name: "Zitadelle",
        image_path: "/images/cards/ZITADELLE.jpg",
        # 100 sats
        current_price: 70000,
        rarity: "epic",
        description:
          "The Bitcoin citadel community. An epic card representing the sovereign Bitcoin lifestyle and community."
      },
      %{
        name: "Jonas Nick",
        image_path: "/images/cards/JONAS_NICK.jpg",
        # 95 sats
        current_price: 46000,
        rarity: "epic",
        description:
          "Cryptographer and Bitcoin protocol researcher. An epic card showcasing the mathematical foundations of Bitcoin security."
      },
      %{
        name: "Blocktrainer",
        image_path: "/images/cards/BLOCKTRAINER.jpg",
        # 85 sats
        current_price: 65000,
        rarity: "epic",
        description:
          "Educational pioneer in the Bitcoin space. An epic card honoring those who teach others about cryptocurrency fundamentals."
      },
      %{
        name: "Markus Turm",
        image_path: "/images/cards/MARKUS_TURM.jpg",
        # 80 sats
        current_price: 81000,
        rarity: "epic",
        description:
          "Bitcoin educator and podcast host. An epic card representing German Bitcoin education and community building."
      },
      %{
        name: "Niko Jilch",
        image_path: "/images/cards/NIKO_JILCH.jpg",
        # 75 sats
        current_price: 64000,
        rarity: "rare",
        description:
          "Austrian journalist and Bitcoin advocate. A rare card highlighting Bitcoin journalism and financial education."
      },
      %{
        name: "Einundzwanzig Magazin",
        image_path: "/images/cards/EINUNDZWANZIG_MAGAZIN.jpg",
        # 70 sats
        current_price: 62000,
        rarity: "rare",
        description:
          "German Bitcoin magazine promoting education. A rare card celebrating Bitcoin journalism and community media."
      },
      %{
        name: "Maurice Effekt",
        image_path: "/images/cards/MAURICE_EFFEKT.jpg",
        # 65 sats
        current_price: 54000,
        rarity: "rare",
        description:
          "Bitcoin content creator and educator. A rare card representing creative Bitcoin education and community engagement."
      },
      %{
        name: "Node Signal",
        image_path: "/images/cards/NODESIGNAL.jpg",
        # 60 sats
        current_price: 52000,
        rarity: "rare",
        description:
          "Representing the Bitcoin node network infrastructure. A rare card symbolizing decentralized network participation."
      },
      %{
        name: "Einundzwanzig Stammtisch",
        image_path: "/images/cards/EINUNDZWANZIG_STAMMTISCH.jpg",
        # 55 sats
        current_price: 51000,
        rarity: "rare",
        description:
          "Local Bitcoin meetup community. A rare card celebrating grassroots Bitcoin adoption and local communities."
      },
      %{
        name: "Der Pleb",
        image_path: "/images/cards/DER_PLEB.jpg",
        # 50 sats
        current_price: 48000,
        rarity: "uncommon",
        description:
          "The everyday Bitcoin enthusiast. An uncommon card representing the grassroots Bitcoin community spirit."
      },
      %{
        name: "Pleb Rap",
        image_path: "/images/cards/PLEBRAP.jpg",
        # 45 sats
        current_price: 45000,
        rarity: "uncommon",
        description:
          "Bitcoin culture meets music. An uncommon card celebrating the creative expression within the Bitcoin community."
      },
      %{
        name: "Pioniere Münzweg",
        image_path: "/images/cards/PIONIERE_MUENZWEG.jpg",
        # 42 sats
        current_price: 42000,
        rarity: "uncommon",
        description:
          "Bitcoin pioneers paving the way. An uncommon card honoring early adopters and Bitcoin pathway creators."
      },
      %{
        name: "FAB",
        image_path: "/images/cards/FAB.jpg",
        # 40 sats
        current_price: 40000,
        rarity: "uncommon",
        description:
          "Bitcoin community builder and advocate. An uncommon card representing dedication to Bitcoin adoption."
      },
      %{
        name: "Dennis",
        image_path: "/images/cards/DENNIS.jpg",
        # 38 sats
        current_price: 38000,
        rarity: "uncommon",
        description:
          "Bitcoin enthusiast and community member. An uncommon card celebrating individual Bitcoin journey stories."
      },
      %{
        name: "Paddepadde",
        image_path: "/images/cards/PADDEPADDE.jpg",
        # 35 sats
        current_price: 35000,
        rarity: "common",
        description:
          "Creative Bitcoin community contributor. A common card representing artistic expression in the Bitcoin space."
      },
      %{
        name: "Netdiver",
        image_path: "/images/cards/NETDIVER.jpg",
        # 32 sats
        current_price: 32000,
        rarity: "common",
        description:
          "Bitcoin technical enthusiast. A common card representing the technical exploration of Bitcoin."
      },
      %{
        name: "Toxic Booster",
        image_path: "/images/cards/TOXIC_BOOSTER.jpg",
        # 30 sats
        current_price: 30000,
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
      # -5 to +5 sats
      initial_change_24h = :rand.uniform(11) - 6

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
