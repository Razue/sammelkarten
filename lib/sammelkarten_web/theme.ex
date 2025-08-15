defmodule SammelkartenWeb.Theme do
  @moduledoc """
  Theme management functionality for the application.

  Provides utilities for managing light/dark themes across the application.
  """

  alias Sammelkarten.Preferences

  @doc """
  Gets the current theme for a user.
  Returns "light" or "dark". Defaults to "light" if not found.
  """
  def get_current_theme(user_id \\ "default_user") do
    case Preferences.get_user_preferences(user_id) do
      {:ok, preferences} -> preferences.theme
      {:error, _} -> "light"
    end
  end

  @doc """
  Gets the CSS class for the current theme.
  Returns "dark" if dark theme is enabled, empty string otherwise.
  """
  def get_theme_class do
    theme = get_current_theme()
    if theme == "dark", do: "dark", else: ""
  end

  @doc """
  Checks if dark theme is currently enabled.
  """
  def dark_theme?(user_id \\ "default_user") do
    get_current_theme(user_id) == "dark"
  end

  @doc """
  Gets theme-aware CSS classes for common UI elements.
  """
  def theme_classes(user_id \\ "default_user") do
    if dark_theme?(user_id) do
      %{
        bg_primary: "bg-gray-900",
        bg_secondary: "bg-gray-800",
        bg_tertiary: "bg-gray-700",
        text_primary: "text-white",
        text_secondary: "text-gray-300",
        text_muted: "text-gray-400",
        border: "border-gray-700",
        hover_bg: "hover:bg-gray-700"
      }
    else
      %{
        bg_primary: "bg-white",
        bg_secondary: "bg-gray-50",
        bg_tertiary: "bg-gray-100",
        text_primary: "text-gray-900",
        text_secondary: "text-gray-700",
        text_muted: "text-gray-500",
        border: "border-gray-200",
        hover_bg: "hover:bg-gray-50"
      }
    end
  end
end
