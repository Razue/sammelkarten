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

    Enum.each(card_seed_data(), fn card_attrs ->
      {varied_price, initial_change_24h, initial_change_percentage} =
        price_variation(card_attrs.current_price)

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

  defp card_seed_data do
    path = Path.join([:code.priv_dir(:sammelkarten), "data", "zitadelle_2025_card_data.json"])

    case File.read(path) do
      {:ok, json} ->
        case Jason.decode(json, keys: :atoms) do
          {:ok, data} -> data
          {:error, _} -> []
        end

      {:error, _} ->
        []
    end
  end

  defp price_variation(base_price) do
    price_variation = :rand.uniform(21) - 11
    varied_price = trunc(base_price * (1 + price_variation / 100))
    initial_change_24h = :rand.uniform(11) - 6

    initial_change_percentage =
      if varied_price > 0 do
        initial_change_24h / varied_price * 100.0
      else
        0.0
      end

    {varied_price, initial_change_24h, initial_change_percentage}
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
