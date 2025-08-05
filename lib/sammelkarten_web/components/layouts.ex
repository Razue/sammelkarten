defmodule SammelkartenWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use SammelkartenWeb, :controller` and
  `use SammelkartenWeb, :live_view`.
  """
  use SammelkartenWeb, :html

  alias SammelkartenWeb.Theme

  embed_templates "layouts/*"

  @doc """
  Gets the theme CSS class for the HTML element.
  """
  def get_theme_class(_assigns) do
    Theme.get_theme_class()
  end
end
