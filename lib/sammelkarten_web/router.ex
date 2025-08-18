defmodule SammelkartenWeb.Router do
  use SammelkartenWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SammelkartenWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :admin_auth do
    plug :ensure_admin_authenticated
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SammelkartenWeb do
    pipe_through :browser

    live "/", DashboardExchangeLive, :index
    live "/cards", DashboardLive, :index
    live "/cards/:slug", CardDetailLive, :show
    live "/preferences", PreferencesLive, :index
    live "/market", MarketLive, :index
    live "/donation", DonationLive, :index
    live "/auth", NostrAuthLive, :index
    live "/portfolio", PortfolioLive, :index
    live "/analytics", AnalyticsLive, :index
    live "/insights", MarketInsightsLive, :index
    live "/leaderboards", LeaderboardsLive, :index
    live "/trading", TradingLive, :index

    # Nostr authentication routes
    post "/nostr/session", NostrSessionController, :create
    delete "/nostr/session", NostrSessionController, :delete

    # Admin authentication routes
    live "/admin/login", AdminLoginLive, :index
    post "/admin/session", AdminSessionController, :create
    delete "/admin/session", AdminSessionController, :delete
  end

  scope "/admin", SammelkartenWeb do
    pipe_through [:browser, :admin_auth]

    live "/", AdminLive, :index
    live "/relays", RelayAdminLive, :index
  end

  scope "/", SammelkartenWeb do
    pipe_through :browser

    # Catch-all route for exchange cards - must be last
    live "/:slug", CardDetailExchangeLive, :show
  end

  # Admin authentication helper
  defp ensure_admin_authenticated(conn, _opts) do
    if get_session(conn, :admin_authenticated) do
      conn
    else
      conn
      |> Phoenix.Controller.put_flash(:error, "Admin access required")
      |> Phoenix.Controller.redirect(to: "/admin/login")
      |> halt()
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", SammelkartenWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:sammelkarten, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SammelkartenWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
