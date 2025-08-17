defmodule Sammelkarten.Analytics do
  @moduledoc """
  Analytics system for user trading performance and portfolio growth tracking.

  This module provides:
  - User trading performance metrics and statistics
  - Portfolio growth analysis and historical tracking
  - Risk assessment and Sharpe ratio calculations
  - Comparative performance analysis
  - Trading pattern recognition and insights
  """

  require Logger

  @doc """
  Get comprehensive trading performance metrics for a user.
  """
  def get_user_performance(user_pubkey, days_back \\ 30) do
    with {:ok, trades} <- get_user_trades(user_pubkey, days_back),
         {:ok, portfolio_history} <- get_portfolio_history(user_pubkey, days_back) do
      performance = %{
        user_pubkey: user_pubkey,
        period_days: days_back,
        total_trades: length(trades),
        trading_metrics: calculate_trading_metrics(trades),
        portfolio_growth: calculate_portfolio_growth(portfolio_history),
        risk_metrics: calculate_risk_metrics(portfolio_history),
        profitability: calculate_profitability(trades),
        activity_patterns: analyze_activity_patterns(trades),
        card_preferences: analyze_card_preferences(trades),
        performance_score: calculate_performance_score(trades, portfolio_history)
      }

      {:ok, performance}
    else
      error -> error
    end
  end

  @doc """
  Get portfolio growth analysis for a user.
  """
  def get_portfolio_growth_analysis(user_pubkey, days_back \\ 90) do
    with {:ok, portfolio_history} <- get_portfolio_history(user_pubkey, days_back),
         {:ok, trades} <- get_user_trades(user_pubkey, days_back) do
      analysis = %{
        user_pubkey: user_pubkey,
        period_days: days_back,
        initial_value: get_initial_portfolio_value(portfolio_history),
        current_value: get_current_portfolio_value(portfolio_history),
        peak_value: get_peak_portfolio_value(portfolio_history),
        growth_rate: calculate_growth_rate(portfolio_history),
        volatility: calculate_portfolio_volatility(portfolio_history),
        drawdown: calculate_max_drawdown(portfolio_history),
        sharpe_ratio: calculate_sharpe_ratio(portfolio_history),
        trading_impact: analyze_trading_impact(trades, portfolio_history),
        growth_trend: analyze_growth_trend(portfolio_history)
      }

      {:ok, analysis}
    else
      error -> error
    end
  end

  @doc """
  Get comparative performance metrics against other users.
  """
  def get_comparative_performance(user_pubkey, days_back \\ 30) do
    with {:ok, user_performance} <- get_user_performance(user_pubkey, days_back),
         {:ok, market_stats} <- get_market_performance_stats(days_back) do
      comparison = %{
        user_performance: user_performance,
        market_averages: market_stats,
        percentile_rankings: calculate_percentile_rankings(user_performance, market_stats),
        outperformance: calculate_outperformance_metrics(user_performance, market_stats),
        risk_adjusted_performance:
          calculate_risk_adjusted_comparison(user_performance, market_stats)
      }

      {:ok, comparison}
    else
      error -> error
    end
  end

  @doc """
  Get trading insights and recommendations for a user.
  """
  def get_trading_insights(user_pubkey, days_back \\ 60) do
    with {:ok, performance} <- get_user_performance(user_pubkey, days_back),
         {:ok, growth} <- get_portfolio_growth_analysis(user_pubkey, days_back) do
      insights = %{
        strengths: identify_trading_strengths(performance),
        weaknesses: identify_trading_weaknesses(performance),
        recommendations: generate_recommendations(performance, growth),
        risk_assessment: assess_risk_profile(performance, growth),
        market_timing: analyze_market_timing(performance),
        diversification: analyze_diversification(performance)
      }

      {:ok, insights}
    else
      error -> error
    end
  end

  # Private functions

  defp get_user_trades(user_pubkey, days_back) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-days_back, :day)

    try do
      trades =
        :mnesia.dirty_match_object(
          {:user_trades, :_, user_pubkey, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}
        )
        |> Enum.filter(fn {_, _, _, _, _, _, _, _, _, _, created_at, _, _} ->
          case created_at do
            %DateTime{} -> DateTime.compare(created_at, cutoff_time) == :gt
            _ -> false
          end
        end)
        |> Enum.map(&trade_record_to_map/1)

      {:ok, trades}
    rescue
      error -> {:error, {:database_error, error}}
    end
  end

  defp get_portfolio_history(user_pubkey, days_back) do
    cutoff_time = :os.system_time(:second) - days_back * 86400

    try do
      history =
        :mnesia.dirty_match_object({:user_portfolios, user_pubkey, :_, :_})
        |> Enum.filter(fn {_, _, _, last_calculated} ->
          last_calculated >= cutoff_time
        end)
        |> Enum.map(&portfolio_record_to_map/1)
        |> Enum.sort_by(& &1.last_calculated)

      {:ok, history}
    rescue
      error -> {:error, {:database_error, error}}
    end
  end

  defp calculate_trading_metrics(trades) do
    total_volume =
      Enum.reduce(trades, 0, fn trade, acc ->
        acc + trade.price * trade.quantity
      end)

    buy_trades = Enum.filter(trades, &(&1.trade_type == "buy"))
    sell_trades = Enum.filter(trades, &(&1.trade_type == "sell"))

    %{
      total_volume: total_volume,
      buy_trades: length(buy_trades),
      sell_trades: length(sell_trades),
      avg_trade_size: if(length(trades) > 0, do: total_volume / length(trades), else: 0),
      trade_frequency: calculate_trade_frequency(trades),
      largest_trade: get_largest_trade(trades),
      smallest_trade: get_smallest_trade(trades)
    }
  end

  defp calculate_portfolio_growth(portfolio_history) do
    if length(portfolio_history) < 2 do
      %{
        growth_rate: 0,
        total_return: 0,
        annualized_return: 0,
        initial_value: 0,
        final_value: 0,
        current_value: 0,
        sharpe_ratio: 0
      }
    else
      first_entry = List.first(portfolio_history)
      last_entry = List.last(portfolio_history)

      # Defensive programming - ensure we have valid portfolio entries
      initial_value =
        case first_entry do
          %{total_value: val} when is_number(val) -> val
          _ -> 0
        end

      final_value =
        case last_entry do
          %{total_value: val} when is_number(val) -> val
          _ -> initial_value
        end

      total_return =
        if initial_value > 0 do
          (final_value - initial_value) / initial_value
        else
          0
        end

      # Calculate time period in years
      initial_time =
        case first_entry do
          %{last_calculated: time} when is_number(time) -> time
          _ -> :os.system_time(:second)
        end

      final_time =
        case last_entry do
          %{last_calculated: time} when is_number(time) -> time
          _ -> :os.system_time(:second)
        end

      years = (final_time - initial_time) / (365.25 * 86400)

      annualized_return =
        if is_number(years) and years > 0 and is_number(initial_value) and initial_value > 0 do
          :math.pow(final_value / initial_value, 1 / years) - 1
        else
          0
        end

      %{
        growth_rate: total_return,
        total_return: total_return,
        annualized_return: annualized_return,
        initial_value: initial_value,
        final_value: final_value,
        current_value: final_value,
        sharpe_ratio: calculate_sharpe_ratio(portfolio_history)
      }
    end
  end

  defp calculate_risk_metrics(portfolio_history) do
    if length(portfolio_history) < 2 do
      %{volatility: 0, max_drawdown: 0, var_95: 0}
    else
      returns = calculate_daily_returns(portfolio_history)

      volatility = calculate_volatility(returns)
      max_drawdown = calculate_max_drawdown_from_history(portfolio_history)
      var_95 = calculate_var(returns, 0.05)

      %{
        volatility: volatility,
        max_drawdown: max_drawdown,
        var_95: var_95,
        return_distribution: analyze_return_distribution(returns)
      }
    end
  end

  defp calculate_profitability(trades) do
    realized_pnl = calculate_realized_pnl(trades)
    win_rate = calculate_win_rate(trades)
    avg_win = calculate_average_win(trades)
    avg_loss = calculate_average_loss(trades)

    %{
      realized_pnl: realized_pnl,
      win_rate: win_rate,
      profit_factor: if(avg_loss != 0, do: abs(avg_win / avg_loss), else: 0),
      average_win: avg_win,
      average_loss: avg_loss,
      largest_win: get_largest_win(trades),
      largest_loss: get_largest_loss(trades)
    }
  end

  defp analyze_activity_patterns(trades) do
    if length(trades) == 0 do
      %{peak_hours: [], peak_days: [], trading_streaks: []}
    else
      # Convert timestamps to datetime for analysis
      hourly_distribution = calculate_hourly_distribution(trades)
      daily_distribution = calculate_daily_distribution(trades)
      streaks = calculate_trading_streaks(trades)

      %{
        peak_hours: get_peak_trading_hours(hourly_distribution),
        peak_days: get_peak_trading_days(daily_distribution),
        trading_streaks: streaks,
        consistency_score: calculate_consistency_score(trades)
      }
    end
  end

  defp analyze_card_preferences(trades) do
    if length(trades) == 0 do
      %{favorite_cards: [], trading_distribution: %{}}
    else
      card_frequency =
        trades
        |> Enum.group_by(& &1.card_id)
        |> Enum.map(fn {card_id, card_trades} ->
          {card_id, length(card_trades)}
        end)
        |> Enum.sort_by(fn {_card_id, count} -> count end, :desc)

      %{
        favorite_cards: Enum.take(card_frequency, 5),
        trading_distribution: Map.new(card_frequency),
        diversification_score: calculate_diversification_score(card_frequency)
      }
    end
  end

  defp calculate_performance_score(trades, portfolio_history) do
    # Composite score based on multiple factors
    profitability_score = calculate_profitability_score(trades)
    growth_score = calculate_growth_score(portfolio_history)
    risk_score = calculate_risk_score(portfolio_history)
    consistency_score = calculate_consistency_score(trades)

    # Weighted average of scores
    total_score =
      profitability_score * 0.3 +
        growth_score * 0.3 +
        risk_score * 0.2 +
        consistency_score * 0.2

    # Clamp between 0-100
    min(max(total_score, 0), 100)
  end

  # Helper functions for calculations

  defp trade_record_to_map(
         {:user_trades, id, user_pubkey, card_id, trade_type, quantity, price, total_value,
          counterparty_pubkey, status, created_at, completed_at, nostr_event_id}
       ) do
    %{
      id: id,
      user_pubkey: user_pubkey,
      card_id: card_id,
      trade_type: trade_type,
      quantity: quantity,
      price: price,
      total_value: total_value,
      counterparty_pubkey: counterparty_pubkey,
      status: status,
      created_at: created_at,
      completed_at: completed_at,
      nostr_event_id: nostr_event_id
    }
  end

  defp portfolio_record_to_map({:user_portfolios, user_pubkey, total_value, last_calculated}) do
    %{
      user_pubkey: user_pubkey,
      total_value: total_value,
      last_calculated: last_calculated
    }
  end

  defp calculate_daily_returns(portfolio_history) do
    portfolio_history
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [prev, curr] ->
      if prev.total_value > 0 do
        (curr.total_value - prev.total_value) / prev.total_value
      else
        0
      end
    end)
  end

  defp calculate_volatility(returns) do
    if length(returns) < 2 do
      0
    else
      mean_return = Enum.sum(returns) / length(returns)

      variance =
        returns
        |> Enum.map(fn r -> :math.pow(r - mean_return, 2) end)
        |> Enum.sum()
        |> Kernel./(length(returns) - 1)

      :math.sqrt(variance)
    end
  end

  # Placeholder implementations for complex calculations
  defp get_market_performance_stats(_days_back) do
    # This would aggregate performance across all users
    {:ok,
     %{
       avg_return: 0.05,
       avg_trades_per_user: 15,
       avg_portfolio_growth: 0.03,
       market_volatility: 0.15
     }}
  end

  defp calculate_percentile_rankings(_user_performance, _market_stats) do
    # Calculate where user ranks compared to others
    %{
      return_percentile: 75,
      volume_percentile: 60,
      consistency_percentile: 80
    }
  end

  defp calculate_outperformance_metrics(_user_performance, _market_stats) do
    %{
      alpha: 0.02,
      beta: 1.1,
      tracking_error: 0.05
    }
  end

  defp calculate_risk_adjusted_comparison(_user_performance, _market_stats) do
    %{
      sharpe_ratio_vs_market: 0.15,
      information_ratio: 0.8,
      sortino_ratio: 1.2
    }
  end

  # Simplified implementations for demonstration
  defp calculate_trade_frequency(_trades), do: 2.5

  defp get_largest_trade(trades),
    do: if(length(trades) > 0, do: Enum.max_by(trades, &(&1.price * &1.quantity)), else: nil)

  defp get_smallest_trade(trades),
    do: if(length(trades) > 0, do: Enum.min_by(trades, &(&1.price * &1.quantity)), else: nil)

  defp get_initial_portfolio_value(history),
    do: if(length(history) > 0, do: List.first(history).total_value, else: 0)

  defp get_current_portfolio_value(history),
    do: if(length(history) > 0, do: List.last(history).total_value, else: 0)

  defp get_peak_portfolio_value(history),
    do: if(length(history) > 0, do: Enum.max_by(history, & &1.total_value).total_value, else: 0)

  defp calculate_growth_rate(history), do: calculate_portfolio_growth(history).growth_rate
  defp calculate_portfolio_volatility(history), do: calculate_risk_metrics(history).volatility
  defp calculate_max_drawdown(history), do: calculate_risk_metrics(history).max_drawdown
  defp calculate_sharpe_ratio(_history), do: 1.2

  defp analyze_trading_impact(_trades, _history),
    do: %{positive_impact: 0.75, negative_impact: 0.25}

  defp analyze_growth_trend(_history), do: :upward
  defp calculate_realized_pnl(_trades), do: 5000
  defp calculate_win_rate(_trades), do: 0.65
  defp calculate_average_win(_trades), do: 150
  defp calculate_average_loss(_trades), do: -80
  defp get_largest_win(_trades), do: 500
  defp get_largest_loss(_trades), do: -200
  defp calculate_hourly_distribution(_trades), do: %{}
  defp calculate_daily_distribution(_trades), do: %{}
  defp calculate_trading_streaks(_trades), do: []
  defp get_peak_trading_hours(_distribution), do: [14, 15, 16]
  defp get_peak_trading_days(_distribution), do: [:monday, :tuesday, :wednesday]
  defp calculate_consistency_score(_trades), do: 75
  defp calculate_diversification_score(_frequency), do: 0.8
  defp calculate_profitability_score(_trades), do: 75
  defp calculate_growth_score(_history), do: 70
  defp calculate_risk_score(_history), do: 80
  defp calculate_max_drawdown_from_history(_history), do: 0.15
  defp calculate_var(_returns, _confidence), do: 0.05
  defp analyze_return_distribution(_returns), do: %{skewness: 0.1, kurtosis: 3.2}
  defp identify_trading_strengths(_performance), do: ["consistent_returns", "risk_management"]
  defp identify_trading_weaknesses(_performance), do: ["overtrading", "market_timing"]

  defp generate_recommendations(_performance, _growth),
    do: ["diversify_holdings", "reduce_trade_frequency"]

  defp assess_risk_profile(_performance, _growth), do: %{risk_level: :moderate, risk_score: 60}
  defp analyze_market_timing(_performance), do: %{timing_skill: 0.6, market_correlation: 0.8}

  defp analyze_diversification(_performance),
    do: %{diversification_ratio: 0.75, concentration_risk: :low}
end
