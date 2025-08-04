defmodule Sammelkarten.Theme do
  @moduledoc """
  Theme management for the Sammelkarten application.
  Handles light/dark theme state and persistence.
  """

  @default_theme "light"
  @valid_themes ["light", "dark"]

  @doc """
  Returns the default theme.
  """
  def default_theme, do: @default_theme

  @doc """
  Returns all valid themes.
  """
  def valid_themes, do: @valid_themes

  @doc """
  Validates if a theme is valid.
  """
  def valid_theme?(theme) when theme in @valid_themes, do: true
  def valid_theme?(_theme), do: false

  @doc """
  Normalizes a theme string, returning default if invalid.
  """
  def normalize_theme(theme) when theme in @valid_themes, do: theme
  def normalize_theme(_theme), do: @default_theme

  @doc """
  Toggles between light and dark theme.
  """
  def toggle_theme("light"), do: "dark"
  def toggle_theme("dark"), do: "light"
  def toggle_theme(_), do: @default_theme

  @doc """
  Returns CSS classes for the given theme.
  """
  def theme_classes("dark"), do: "dark"
  def theme_classes(_), do: ""

  @doc """
  Returns theme-specific color configurations.
  """
  def theme_config("light") do
    %{
      primary_bg: "bg-white",
      secondary_bg: "bg-gray-50",
      tertiary_bg: "bg-gray-100",
      card_bg: "bg-white",
      text_primary: "text-gray-900",
      text_secondary: "text-gray-700",
      text_muted: "text-gray-500",
      border: "border-gray-200",
      border_light: "border-gray-100",
      gradient_from: "from-blue-600",
      gradient_to: "to-purple-600",
      shadow: "shadow-lg",
      ring: "ring-gray-200"
    }
  end

  def theme_config("dark") do
    %{
      primary_bg: "bg-gray-900",
      secondary_bg: "bg-gray-800",
      tertiary_bg: "bg-gray-700",
      card_bg: "bg-gray-800",
      text_primary: "text-white",
      text_secondary: "text-gray-200",
      text_muted: "text-gray-400",
      border: "border-gray-700",
      border_light: "border-gray-600",
      gradient_from: "from-blue-500",
      gradient_to: "to-purple-500",
      shadow: "shadow-xl",
      ring: "ring-gray-600"
    }
  end

  def theme_config(_), do: theme_config(@default_theme)
end