defmodule SammelkartenWeb.PageController do
  use SammelkartenWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def cards(conn, _params) do
    render(conn, :cards, page_title: "Cards")
  end

  def market(conn, _params) do
    render(conn, :market, page_title: "Market")
  end
end
