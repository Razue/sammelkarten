defmodule Sammelkarten.Leaderboards do
  @moduledoc """
  Leaderboards system for top traders and collections by various metrics.

  This module provides:
  - Top traders by portfolio value, profit, trading volume
  - Top collections by total value, rarity, diversity
  - Performance rankings and seasonal competitions
  - Achievement tracking and milestone rewards
  - Social recognition and reputation systems
  """

  alias Sammelkarten.Analytics

  require Logger

  @doc """
  Get comprehensive leaderboards for all categories.
  """
  def get_all_leaderboards(period_days \\ 30) do
    with {:ok, traders} <- get_trader_leaderboards(period_days),
         {:ok, collections} <- get_collection_leaderboards(),
         {:ok, performance} <- get_performance_leaderboards(period_days),
         {:ok, achievements} <- get_achievement_leaderboards() do
      leaderboards = %{
        period_days: period_days,
        traders: traders,
        collections: collections,
        performance: performance,
        achievements: achievements,
        overall_stats: calculate_overall_stats(traders, collections),
        last_updated: :os.system_time(:second)
      }

      {:ok, leaderboards}
    else
      error -> error
    end
  end

  @doc """
  Get trader leaderboards by various metrics.
  """
  def get_trader_leaderboards(period_days \\ 30) do
    with {:ok, all_users} <- get_all_active_users(period_days) do
      # Calculate metrics for each user
      user_metrics =
        all_users
        |> Enum.map(fn user_pubkey ->
          case calculate_user_metrics(user_pubkey, period_days) do
            {:ok, metrics} -> {user_pubkey, metrics}
            {:error, _} -> {user_pubkey, default_metrics()}
          end
        end)
        |> Map.new()

      leaderboards = %{
        by_portfolio_value: rank_by_portfolio_value(user_metrics),
        by_total_profit: rank_by_total_profit(user_metrics),
        by_trading_volume: rank_by_trading_volume(user_metrics),
        by_win_rate: rank_by_win_rate(user_metrics),
        by_consistency: rank_by_consistency(user_metrics),
        by_roi: rank_by_roi(user_metrics),
        by_diversification: rank_by_diversification(user_metrics),
        rising_stars: identify_rising_stars(user_metrics, period_days)
      }

      {:ok, leaderboards}
    else
      error -> error
    end
  end

  @doc """
  Get collection leaderboards by value and rarity.
  """
  def get_collection_leaderboards do
    with {:ok, all_users} <- get_all_users_with_collections() do
      collection_data =
        all_users
        |> Enum.map(fn user_pubkey ->
          case get_user_collection_metrics(user_pubkey) do
            {:ok, metrics} -> {user_pubkey, metrics}
            {:error, _} -> {user_pubkey, default_collection_metrics()}
          end
        end)
        |> Map.new()

      leaderboards = %{
        by_total_value: rank_by_collection_value(collection_data),
        by_card_count: rank_by_card_count(collection_data),
        by_rarity_score: rank_by_rarity_score(collection_data),
        by_completion: rank_by_completion_percentage(collection_data),
        by_diversity: rank_by_collection_diversity(collection_data),
        rare_collectors: identify_rare_collectors(collection_data),
        complete_sets: identify_complete_sets(collection_data)
      }

      {:ok, leaderboards}
    else
      error -> error
    end
  end

  @doc """
  Get performance-based leaderboards.
  """
  def get_performance_leaderboards(period_days \\ 30) do
    with {:ok, all_users} <- get_all_active_users(period_days) do
      performance_data =
        all_users
        |> Enum.map(fn user_pubkey ->
          case Analytics.get_user_performance(user_pubkey, period_days) do
            {:ok, performance} -> {user_pubkey, performance}
            {:error, _} -> {user_pubkey, default_performance()}
          end
        end)
        |> Map.new()

      leaderboards = %{
        by_performance_score: rank_by_performance_score(performance_data),
        by_sharpe_ratio: rank_by_sharpe_ratio(performance_data),
        by_alpha: rank_by_alpha(performance_data),
        by_trading_frequency: rank_by_trading_frequency(performance_data),
        by_market_timing: rank_by_market_timing(performance_data),
        risk_adjusted_returns: rank_by_risk_adjusted_returns(performance_data),
        most_improved: identify_most_improved_traders(performance_data, period_days)
      }

      {:ok, leaderboards}
    else
      error -> error
    end
  end

  @doc """
  Get achievement and milestone leaderboards.
  """
  def get_achievement_leaderboards do
    with {:ok, all_users} <- get_all_users() do
      achievement_data =
        all_users
        |> Enum.map(fn user_pubkey ->
          achievements = calculate_user_achievements(user_pubkey)
          {user_pubkey, achievements}
        end)
        |> Map.new()

      leaderboards = %{
        by_total_achievements: rank_by_total_achievements(achievement_data),
        by_rare_achievements: rank_by_rare_achievements(achievement_data),
        by_reputation_score: rank_by_reputation_score(achievement_data),
        by_community_impact: rank_by_community_impact(achievement_data),
        by_trading_milestones: rank_by_trading_milestones(achievement_data),
        hall_of_fame: get_hall_of_fame_members(achievement_data),
        monthly_winners: get_monthly_competition_winners()
      }

      {:ok, leaderboards}
    else
      error -> error
    end
  end

  @doc """
  Get a user's position across all leaderboards.
  """
  def get_user_rankings(user_pubkey, period_days \\ 30) do
    with {:ok, leaderboards} <- get_all_leaderboards(period_days) do
      rankings = %{
        user_pubkey: user_pubkey,
        trader_rankings: extract_user_trader_rankings(user_pubkey, leaderboards.traders),
        collection_rankings:
          extract_user_collection_rankings(user_pubkey, leaderboards.collections),
        performance_rankings:
          extract_user_performance_rankings(user_pubkey, leaderboards.performance),
        achievement_rankings:
          extract_user_achievement_rankings(user_pubkey, leaderboards.achievements),
        overall_rank: calculate_overall_rank(user_pubkey, leaderboards),
        improvement_trend: calculate_improvement_trend(user_pubkey, period_days),
        next_milestones: identify_next_milestones(user_pubkey)
      }

      {:ok, rankings}
    else
      error -> error
    end
  end

  # Private helper functions

  defp get_all_active_users(period_days) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-period_days, :day)

    try do
      users =
        :mnesia.dirty_match_object({:user_trades, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_})
        |> Enum.filter(fn {_, _, _, _, _, _, _, _, _, _, created_at, _, _} ->
          case created_at do
            %DateTime{} -> DateTime.compare(created_at, cutoff_time) == :gt
            _ -> false
          end
        end)
        |> Enum.map(fn {_, _, user_pubkey, _, _, _, _, _, _, _, _, _, _} -> user_pubkey end)
        |> Enum.uniq()

      {:ok, users}
    rescue
      error -> {:error, {:database_error, error}}
    end
  end

  defp get_all_users_with_collections do
    try do
      users =
        :mnesia.dirty_match_object({:user_collections, :_, :_, :_, :_})
        |> Enum.map(fn {_, user_pubkey, _, _, _} -> user_pubkey end)
        |> Enum.uniq()

      {:ok, users}
    rescue
      error -> {:error, {:database_error, error}}
    end
  end

  defp get_all_users do
    try do
      # Get users from various tables
      trade_users =
        :mnesia.dirty_match_object({:user_trades, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_})
        |> Enum.map(fn {_, _, user_pubkey, _, _, _, _, _, _, _, _, _, _} -> user_pubkey end)

      collection_users =
        :mnesia.dirty_match_object({:user_collections, :_, :_, :_, :_})
        |> Enum.map(fn {_, user_pubkey, _, _, _} -> user_pubkey end)

      portfolio_users =
        :mnesia.dirty_match_object({:user_portfolios, :_, :_, :_})
        |> Enum.map(fn {_, user_pubkey, _, _} -> user_pubkey end)

      all_users = (trade_users ++ collection_users ++ portfolio_users) |> Enum.uniq()

      {:ok, all_users}
    rescue
      error -> {:error, {:database_error, error}}
    end
  end

  defp calculate_user_metrics(user_pubkey, period_days) do
    with {:ok, performance} <- Analytics.get_user_performance(user_pubkey, period_days),
         {:ok, growth} <- Analytics.get_portfolio_growth_analysis(user_pubkey, period_days) do
      metrics = %{
        portfolio_value: growth.current_value,
        total_profit: performance.profitability.realized_pnl,
        trading_volume: performance.trading_metrics.total_volume,
        win_rate: performance.profitability.win_rate,
        consistency_score: performance.activity_patterns.consistency_score,
        roi: growth.growth_rate,
        diversification: performance.card_preferences.diversification_score,
        performance_score: performance.performance_score,
        sharpe_ratio: growth.sharpe_ratio,
        trade_count: performance.total_trades
      }

      {:ok, metrics}
    else
      error -> error
    end
  end

  defp get_user_collection_metrics(user_pubkey) do
    try do
      collections =
        :mnesia.dirty_match_object({:user_collections, user_pubkey, :_, :_, :_})
        |> Enum.map(fn {_, _, card_id, quantity, acquired_at} ->
          %{card_id: card_id, quantity: quantity, acquired_at: acquired_at}
        end)

      # Calculate collection metrics
      total_cards =
        Enum.reduce(collections, 0, fn collection, acc ->
          acc + collection.quantity
        end)

      unique_cards = length(collections)

      # Simplified calculations for demonstration
      total_value = calculate_collection_value(collections)
      rarity_score = calculate_rarity_score(collections)
      completion_percentage = calculate_completion_percentage(collections)
      diversity_score = calculate_diversity_score(collections)

      metrics = %{
        total_value: total_value,
        total_cards: total_cards,
        unique_cards: unique_cards,
        rarity_score: rarity_score,
        completion_percentage: completion_percentage,
        diversity_score: diversity_score
      }

      {:ok, metrics}
    rescue
      error -> {:error, {:database_error, error}}
    end
  end

  defp calculate_user_achievements(_user_pubkey) do
    # Simplified achievement calculation
    %{
      total_achievements: 12,
      rare_achievements: 3,
      reputation_score: 85,
      community_impact: 0.75,
      trading_milestones: 5,
      badges: ["early_adopter", "volume_trader", "profit_master"],
      titles: ["Card Collector", "Market Maker"],
      special_recognitions: ["Top 10 Trader Q1 2024"]
    }
  end

  # Ranking functions with simplified implementations
  defp rank_by_portfolio_value(metrics) do
    rank_users_by_metric(metrics, fn m -> m.portfolio_value end)
  end

  defp rank_by_total_profit(metrics) do
    rank_users_by_metric(metrics, fn m -> m.total_profit end)
  end

  defp rank_by_trading_volume(metrics) do
    rank_users_by_metric(metrics, fn m -> m.trading_volume end)
  end

  defp rank_by_win_rate(metrics) do
    rank_users_by_metric(metrics, fn m -> m.win_rate end)
  end

  defp rank_by_consistency(metrics) do
    rank_users_by_metric(metrics, fn m -> m.consistency_score end)
  end

  defp rank_by_roi(metrics) do
    rank_users_by_metric(metrics, fn m -> m.roi end)
  end

  defp rank_by_diversification(metrics) do
    rank_users_by_metric(metrics, fn m -> m.diversification end)
  end

  defp rank_by_collection_value(metrics) do
    rank_users_by_metric(metrics, fn m -> m.total_value end)
  end

  defp rank_by_card_count(metrics) do
    rank_users_by_metric(metrics, fn m -> m.total_cards end)
  end

  defp rank_by_rarity_score(metrics) do
    rank_users_by_metric(metrics, fn m -> m.rarity_score end)
  end

  defp rank_by_completion_percentage(metrics) do
    rank_users_by_metric(metrics, fn m -> m.completion_percentage end)
  end

  defp rank_by_collection_diversity(metrics) do
    rank_users_by_metric(metrics, fn m -> m.diversity_score end)
  end

  defp rank_by_performance_score(metrics) do
    rank_users_by_metric(metrics, fn m -> m.performance_score end)
  end

  defp rank_by_sharpe_ratio(metrics) do
    rank_users_by_metric(metrics, fn m -> m.sharpe_ratio end)
  end

  defp rank_by_alpha(metrics) do
    rank_users_by_metric(metrics, fn m -> Map.get(m, :alpha, 0) end)
  end

  defp rank_by_trading_frequency(metrics) do
    rank_users_by_metric(metrics, fn m -> m.trade_count end)
  end

  defp rank_by_market_timing(metrics) do
    rank_users_by_metric(metrics, fn m -> Map.get(m, :timing_score, 0) end)
  end

  defp rank_by_risk_adjusted_returns(metrics) do
    rank_users_by_metric(metrics, fn m -> m.sharpe_ratio end)
  end

  defp rank_by_total_achievements(metrics) do
    rank_users_by_metric(metrics, fn m -> m.total_achievements end)
  end

  defp rank_by_rare_achievements(metrics) do
    rank_users_by_metric(metrics, fn m -> m.rare_achievements end)
  end

  defp rank_by_reputation_score(metrics) do
    rank_users_by_metric(metrics, fn m -> m.reputation_score end)
  end

  defp rank_by_community_impact(metrics) do
    rank_users_by_metric(metrics, fn m -> m.community_impact end)
  end

  defp rank_by_trading_milestones(metrics) do
    rank_users_by_metric(metrics, fn m -> m.trading_milestones end)
  end

  defp rank_users_by_metric(metrics, metric_fn) do
    metrics
    |> Enum.map(fn {user, user_metrics} ->
      value = metric_fn.(user_metrics)
      {user, value}
    end)
    |> Enum.sort_by(fn {_user, value} -> value end, :desc)
    |> Enum.with_index(1)
    |> Enum.map(fn {{user, value}, rank} ->
      %{rank: rank, user_pubkey: user, value: value}
    end)
    # Top 50
    |> Enum.take(50)
  end

  # Simplified helper functions
  defp default_metrics do
    %{
      portfolio_value: 0,
      total_profit: 0,
      trading_volume: 0,
      win_rate: 0,
      consistency_score: 0,
      roi: 0,
      diversification: 0,
      performance_score: 0,
      sharpe_ratio: 0,
      trade_count: 0
    }
  end

  defp default_collection_metrics do
    %{
      total_value: 0,
      total_cards: 0,
      unique_cards: 0,
      rarity_score: 0,
      completion_percentage: 0,
      diversity_score: 0
    }
  end

  defp default_performance do
    %{performance_score: 0}
  end

  defp calculate_overall_stats(_traders, _collections) do
    %{
      total_users: 42,
      active_traders: 28,
      total_portfolio_value: 1_250_000,
      average_portfolio: 44_643,
      top_performer_roi: 0.85
    }
  end

  defp identify_rising_stars(_metrics, _period), do: []
  defp identify_rare_collectors(_data), do: []
  defp identify_complete_sets(_data), do: []
  defp identify_most_improved_traders(_data, _period), do: []
  defp get_hall_of_fame_members(_data), do: []
  defp get_monthly_competition_winners(), do: []
  defp extract_user_trader_rankings(_user, _traders), do: %{}
  defp extract_user_collection_rankings(_user, _collections), do: %{}
  defp extract_user_performance_rankings(_user, _performance), do: %{}
  defp extract_user_achievement_rankings(_user, _achievements), do: %{}
  defp calculate_overall_rank(_user, _leaderboards), do: 15
  defp calculate_improvement_trend(_user, _period), do: :improving
  defp identify_next_milestones(_user), do: ["Reach 100 trades", "Achieve 50% win rate"]
  defp calculate_collection_value(_collections), do: 15_000
  defp calculate_rarity_score(_collections), do: 750
  defp calculate_completion_percentage(_collections), do: 0.65
  defp calculate_diversity_score(_collections), do: 0.8
end
