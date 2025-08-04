defmodule Sammelkarten.PriceEngine do
  @moduledoc """
  Price simulation engine for generating realistic card price movements.

  This module simulates market dynamics with:
  - Rarity-based price volatility
  - Market trend influences
  - Random walk price movements
  - Event-driven price spikes
  """

  alias Sammelkarten.Card
  alias Sammelkarten.Cards

  require Logger

  @doc """
  Update prices for all cards based on simulation rules.
  """
  def update_all_prices do
    Logger.info("Starting price update simulation...")

    case Cards.list_cards() do
      {:ok, cards} ->
        # Calculate market trend (affects all cards)
        market_trend = calculate_market_trend()

        # Update each card's price
        results =
          Enum.map(cards, fn card ->
            new_price = simulate_price_movement(card, market_trend)
            update_card_price(card, new_price)
          end)

        # Ensure Markus Turm always has the highest price
        ensure_markus_turm_highest_price()

        successes = Enum.count(results, &match?({:ok, _}, &1))
        Logger.info("Price update completed: #{successes}/#{length(cards)} cards updated")

        {:ok, successes}

      {:error, reason} ->
        Logger.error("Failed to fetch cards for price update: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Simulate price movement for a single card.
  """
  def simulate_price_movement(card, market_trend \\ 0.0) do
    base_volatility = get_rarity_volatility(card.rarity)

    # Combine multiple factors for price movement
    factors = [
      random_walk_factor(),
      market_trend,
      rarity_premium_factor(card.rarity),
      momentum_factor(card.price_change_percentage),
      event_factor()
    ]

    total_change_percentage = Enum.sum(factors) * base_volatility

    # Apply percentage change to current price
    price_change = trunc(card.current_price * total_change_percentage / 100)
    # Minimum price of 1 sat
    new_price = max(card.current_price + price_change, 1)

    new_price
  end

  defp update_card_price(card, new_price) do
    case Cards.update_card_price(card.id, new_price) do
      {:ok, updated_card} ->
        change_percentage = updated_card.price_change_percentage
        direction = if change_percentage >= 0, do: "↗", else: "↘"

        Logger.debug(
          "#{card.name}: #{Card.format_price(card.current_price)} → #{Card.format_price(new_price)} #{direction} #{Card.format_price_change(change_percentage)}"
        )

        {:ok, updated_card}

      {:error, reason} ->
        Logger.error("Failed to update price for #{card.name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Calculate overall market trend affecting all cards.
  """
  def calculate_market_trend do
    # Generate market trend between -2% and +2%
    # -2.0 to +2.0
    base_trend = (:rand.uniform(401) - 201) / 100

    # Add some persistence to trends (trends tend to continue)
    trend_persistence = get_trend_persistence()

    (base_trend + trend_persistence) / 2
  end

  defp get_trend_persistence do
    # Simple trend memory - could be enhanced with actual historical data
    case :rand.uniform(10) do
      # 40% chance of positive persistence
      n when n <= 4 -> 0.5
      # 40% chance of negative persistence
      n when n <= 8 -> -0.5
      # 20% chance of no persistence
      _ -> 0.0
    end
  end

  @doc """
  Generate random walk factor for price movement.
  """
  def random_walk_factor do
    # Random walk between -3% and +3%
    # -3.0 to +3.0
    (:rand.uniform(601) - 301) / 100
  end

  @doc """
  Get volatility multiplier based on card rarity.
  Higher rarity = higher volatility potential.
  """
  def get_rarity_volatility(rarity) do
    case rarity do
      # Lower volatility
      "common" -> 0.6
      "uncommon" -> 0.8
      # Base volatility
      "rare" -> 1.0
      "epic" -> 1.3
      # Higher volatility
      "legendary" -> 1.6
      _ -> 1.0
    end
  end

  @doc """
  Calculate rarity premium factor.
  Legendary cards get occasional premium boosts.
  """
  def rarity_premium_factor(rarity) do
    case rarity do
      "legendary" ->
        # 5% chance
        if :rand.uniform(100) <= 5 do
          # 0.0 to 3.0% bonus
          :rand.uniform(300) / 100
        else
          0.0
        end

      "epic" ->
        # 3% chance
        if :rand.uniform(100) <= 3 do
          # 0.0 to 2.0% bonus
          :rand.uniform(200) / 100
        else
          0.0
        end

      _ ->
        0.0
    end
  end

  @doc """
  Calculate momentum factor based on recent price change.
  """
  def momentum_factor(current_change_percentage) do
    # Momentum tends to continue but with diminishing returns
    cond do
      current_change_percentage > 5.0 ->
        # Strong positive momentum, slight continuation bias
        # 0.0 to 1.5%
        :rand.uniform(150) / 100

      current_change_percentage < -5.0 ->
        # Strong negative momentum, slight reversal bias
        # -1.0 to 0.0%
        -(:rand.uniform(100) / 100)

      true ->
        # Moderate momentum, random continuation
        # -0.5 to +0.5%
        (:rand.uniform(101) - 51) / 100
    end
  end

  @doc """
  Generate random event factor for special price movements.
  """
  def event_factor do
    random_value = :rand.uniform(1000)
    calculate_event_factor(random_value)
  end

  defp calculate_event_factor(random_value) do
    cond do
      # 0.2% chance of major positive event
      random_value <= 2 ->
        generate_major_positive_event()

      # 0.2% chance of major negative event
      random_value <= 4 ->
        generate_major_negative_event()

      # 1.6% chance of minor positive event
      random_value <= 20 ->
        generate_minor_positive_event()

      # 2.0% chance of minor negative event
      random_value <= 40 ->
        generate_minor_negative_event()

      # 96% chance of no special event
      true ->
        0.0
    end
  end

  defp generate_major_positive_event do
    # 0.0 to 10.0% boost
    :rand.uniform(1000) / 100
  end

  defp generate_major_negative_event do
    # -8.0 to 0.0% drop
    -(:rand.uniform(800) / 100)
  end

  defp generate_minor_positive_event do
    # 0.0 to 3.0% boost
    :rand.uniform(300) / 100
  end

  defp generate_minor_negative_event do
    # -3.0 to 0.0% drop
    -(:rand.uniform(300) / 100)
  end

  @doc """
  Simulate a market crash affecting all cards.
  """
  def simulate_market_crash(severity \\ :moderate) do
    Logger.warning("Simulating market crash (#{severity})...")
    crash_percentage = calculate_crash_percentage(severity)

    case Cards.list_cards() do
      {:ok, cards} ->
        apply_crash_to_cards(cards, crash_percentage)
        Logger.warning("Market crash simulation completed")
        {:ok, crash_percentage}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp calculate_crash_percentage(severity) do
    case severity do
      # -5% to -15%
      :minor -> -(:rand.uniform(1000) + 500) / 100
      # -10% to -25%
      :moderate -> -(:rand.uniform(1500) + 1000) / 100
      # -20% to -40%
      :major -> -(:rand.uniform(2000) + 2000) / 100
    end
  end

  defp apply_crash_to_cards(cards, crash_percentage) do
    Enum.each(cards, fn card ->
      new_price = calculate_crashed_price(card, crash_percentage)
      Cards.update_card_price(card.id, new_price)
    end)
  end

  defp calculate_crashed_price(card, crash_percentage) do
    # Each card is affected slightly differently (±3% variation)
    card_crash = crash_percentage + (:rand.uniform(600) - 300) / 100
    max(trunc(card.current_price * (1 + card_crash / 100)), 1)
  end

  @doc """
  Simulate a market boom affecting all cards.
  """
  def simulate_market_boom(strength \\ :moderate) do
    Logger.info("Simulating market boom (#{strength})...")
    boom_percentage = calculate_boom_percentage(strength)

    case Cards.list_cards() do
      {:ok, cards} ->
        apply_boom_to_cards(cards, boom_percentage)
        Logger.info("Market boom simulation completed")
        {:ok, boom_percentage}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp calculate_boom_percentage(strength) do
    case strength do
      # +5% to +15%
      :minor -> (:rand.uniform(1000) + 500) / 100
      # +10% to +25%
      :moderate -> (:rand.uniform(1500) + 1000) / 100
      # +20% to +40%
      :major -> (:rand.uniform(2000) + 2000) / 100
    end
  end

  defp apply_boom_to_cards(cards, boom_percentage) do
    Enum.each(cards, fn card ->
      new_price = calculate_boomed_price(card, boom_percentage)
      Cards.update_card_price(card.id, new_price)
    end)
  end

  defp calculate_boomed_price(card, boom_percentage) do
    # Each card is affected slightly differently (±3% variation)
    card_boom = boom_percentage + (:rand.uniform(600) - 300) / 100
    trunc(card.current_price * (1 + card_boom / 100))
  end

  # Ensure Markus Turm always has the highest price among all cards.
  defp ensure_markus_turm_highest_price do
    case Cards.list_cards() do
      {:ok, cards} ->
        adjust_markus_turm_price(cards)

      {:error, reason} ->
        Logger.error("Failed to fetch cards for Markus Turm price adjustment: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp adjust_markus_turm_price(cards) do
    markus_card = Enum.find(cards, fn card -> card.name == "Markus Turm" end)

    if markus_card do
      check_and_update_markus_price(markus_card, cards)
    else
      Logger.warning("Markus Turm card not found for price adjustment")
      {:error, :markus_turm_not_found}
    end
  end

  defp check_and_update_markus_price(markus_card, cards) do
    other_cards = Enum.reject(cards, fn card -> card.name == "Markus Turm" end)

    if Enum.any?(other_cards) do
      highest_other_price = Enum.max(Enum.map(other_cards, & &1.current_price))
      maybe_boost_markus_price(markus_card, highest_other_price)
    else
      # No other cards to compare against
      {:ok, markus_card}
    end
  end

  defp maybe_boost_markus_price(markus_card, highest_other_price) do
    if markus_card.current_price <= highest_other_price do
      boost_markus_price(markus_card, highest_other_price)
    else
      # Markus Turm already has the highest price
      {:ok, markus_card}
    end
  end

  defp boost_markus_price(markus_card, highest_other_price) do
    # Set Markus Turm's price to be 5-15% higher than the current highest
    price_boost_percentage = 5 + :rand.uniform(11)
    new_markus_price = trunc(highest_other_price * (1 + price_boost_percentage / 100))

    case Cards.update_card_price(markus_card.id, new_markus_price) do
      {:ok, updated_card} ->
        Logger.info(
          "Markus Turm price adjusted to maintain highest position: #{Card.format_price(markus_card.current_price)} → #{Card.format_price(new_markus_price)}"
        )

        {:ok, updated_card}

      {:error, reason} ->
        Logger.error("Failed to adjust Markus Turm price: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
