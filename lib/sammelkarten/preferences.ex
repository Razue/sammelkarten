defmodule Sammelkarten.Preferences do
  @moduledoc """
  Context module for managing user preferences.

  This module provides functions for creating, reading, updating, and deleting
  user preferences stored in Mnesia.
  """

  alias Sammelkarten.UserPreferences

  require Logger

  @doc """
  Get user preferences by user ID.

  If no preferences exist for the user, returns default preferences.
  """
  def get_user_preferences(user_id) when is_binary(user_id) do
    case :mnesia.transaction(fn ->
           :mnesia.read(:user_preferences, user_id)
         end) do
      {:atomic, []} ->
        # No preferences found, return defaults
        default_prefs = UserPreferences.defaults(user_id)
        {:ok, default_prefs}

      {:atomic, [preferences_record]} ->
        # Convert Mnesia record back to UserPreferences struct
        preferences = mnesia_record_to_struct(preferences_record)
        {:ok, preferences}

      {:aborted, reason} ->
        Logger.error("Failed to read user preferences for #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Create or update user preferences.
  """
  def save_user_preferences(%UserPreferences{} = preferences) do
    case UserPreferences.validate(preferences) do
      {:ok, validated_preferences} ->
        record = struct_to_mnesia_record(validated_preferences)
        write_preferences_to_mnesia(record, validated_preferences)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Update specific preference fields for a user.
  """
  def update_user_preferences(user_id, changes) when is_binary(user_id) and is_map(changes) do
    case get_user_preferences(user_id) do
      {:ok, current_preferences} ->
        {:ok, updated_preferences} = UserPreferences.update(current_preferences, changes)
        save_user_preferences(updated_preferences)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Delete user preferences.
  """
  def delete_user_preferences(user_id) when is_binary(user_id) do
    case :mnesia.transaction(fn ->
           :mnesia.delete(:user_preferences, user_id, :write)
         end) do
      {:atomic, :ok} ->
        Logger.info("User preferences deleted for user #{user_id}")
        :ok

      {:aborted, reason} ->
        Logger.error("Failed to delete user preferences for #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  List all user preferences (for admin purposes).
  """
  def list_all_preferences do
    case :mnesia.transaction(fn ->
           :mnesia.select(:user_preferences, [
             {{:user_preferences, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6", :"$7", :"$8", :"$9",
               :"$10", :"$11", :"$12", :"$13", :"$14", :"$15"}, [], [:"$$"]}
           ])
         end) do
      {:atomic, records} ->
        preferences_list = Enum.map(records, &mnesia_record_to_struct/1)
        {:ok, preferences_list}

      {:aborted, reason} ->
        Logger.error("Failed to list all user preferences: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get the refresh rate preference for a user.
  """
  def get_refresh_rate(user_id) when is_binary(user_id) do
    case get_user_preferences(user_id) do
      {:ok, preferences} -> {:ok, preferences.refresh_rate}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Update just the refresh rate for a user.
  """
  def update_refresh_rate(user_id, refresh_rate)
      when is_binary(user_id) and is_integer(refresh_rate) do
    update_user_preferences(user_id, %{refresh_rate: refresh_rate})
  end

  @doc """
  Get theme preference for a user.
  """
  def get_theme(user_id) when is_binary(user_id) do
    case get_user_preferences(user_id) do
      {:ok, preferences} -> {:ok, preferences.theme}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Update just the theme for a user.
  """
  def update_theme(user_id, theme) when is_binary(user_id) and is_binary(theme) do
    update_user_preferences(user_id, %{theme: theme})
  end

  @doc """
  Reset user preferences to defaults.
  """
  def reset_to_defaults(user_id) when is_binary(user_id) do
    default_preferences = UserPreferences.defaults(user_id)
    save_user_preferences(default_preferences)
  end

  @doc """
  Check if user has auto-refresh enabled.
  """
  def auto_refresh_enabled?(user_id) when is_binary(user_id) do
    case get_user_preferences(user_id) do
      {:ok, preferences} -> preferences.auto_refresh
      # Default to enabled if error
      {:error, _reason} -> true
    end
  end

  @doc """
  Get preferences as a map for easy serialization.
  """
  def get_preferences_map(user_id) when is_binary(user_id) do
    case get_user_preferences(user_id) do
      {:ok, preferences} -> {:ok, UserPreferences.to_map(preferences)}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Private helper functions

  # Convert UserPreferences struct to Mnesia record tuple
  defp struct_to_mnesia_record(%UserPreferences{} = prefs) do
    {
      :user_preferences,
      prefs.user_id,
      prefs.refresh_rate,
      prefs.theme,
      prefs.notifications_enabled,
      prefs.sound_enabled,
      prefs.auto_refresh,
      prefs.cards_per_page,
      prefs.default_sort,
      prefs.default_sort_direction,
      prefs.show_ticker,
      prefs.ticker_speed,
      prefs.chart_style,
      prefs.price_alerts,
      prefs.created_at,
      prefs.updated_at
    }
  end

  defp write_preferences_to_mnesia(record, validated_preferences) do
    case :mnesia.transaction(fn ->
           :mnesia.write(:user_preferences, record, :write)
         end) do
      {:atomic, :ok} ->
        Logger.info("User preferences saved for user #{validated_preferences.user_id}")
        {:ok, validated_preferences}

      {:aborted, reason} ->
        Logger.error(
          "Failed to save user preferences for #{validated_preferences.user_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  # Convert Mnesia record tuple back to UserPreferences struct
  defp mnesia_record_to_struct(
         {:user_preferences, user_id, refresh_rate, theme, notifications_enabled, sound_enabled,
          auto_refresh, cards_per_page, default_sort, default_sort_direction, show_ticker,
          ticker_speed, chart_style, price_alerts, created_at, updated_at}
       ) do
    %UserPreferences{
      user_id: user_id,
      refresh_rate: refresh_rate,
      theme: theme,
      notifications_enabled: notifications_enabled,
      sound_enabled: sound_enabled,
      auto_refresh: auto_refresh,
      cards_per_page: cards_per_page,
      default_sort: default_sort,
      default_sort_direction: default_sort_direction,
      show_ticker: show_ticker,
      ticker_speed: ticker_speed,
      chart_style: chart_style,
      price_alerts: price_alerts,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  # Handle list records for list_all_preferences
  defp mnesia_record_to_struct([
         user_id,
         refresh_rate,
         theme,
         notifications_enabled,
         sound_enabled,
         auto_refresh,
         cards_per_page,
         default_sort,
         default_sort_direction,
         show_ticker,
         ticker_speed,
         chart_style,
         price_alerts,
         created_at,
         updated_at
       ]) do
    %UserPreferences{
      user_id: user_id,
      refresh_rate: refresh_rate,
      theme: theme,
      notifications_enabled: notifications_enabled,
      sound_enabled: sound_enabled,
      auto_refresh: auto_refresh,
      cards_per_page: cards_per_page,
      default_sort: default_sort,
      default_sort_direction: default_sort_direction,
      show_ticker: show_ticker,
      ticker_speed: ticker_speed,
      chart_style: chart_style,
      price_alerts: price_alerts,
      created_at: created_at,
      updated_at: updated_at
    }
  end
end
