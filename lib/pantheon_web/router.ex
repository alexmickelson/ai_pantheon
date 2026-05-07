defmodule PantheonWeb.Router do
  use PantheonWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PantheonWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_authenticated do
    plug :require_authenticated_user
  end

  scope "/", PantheonWeb do
    pipe_through [:browser, PantheonWeb.Plugs.RefreshToken]

    get "/", PageController, :home
  end

  scope "/", PantheonWeb do
    pipe_through [:browser, :require_authenticated, PantheonWeb.Plugs.RefreshToken]

    # Add authenticated routes here
  end

  scope "/auth", PantheonWeb do
    pipe_through :browser

    get "/login", AuthController, :authorize
    get "/callback", AuthController, :callback
    get "/logout", AuthController, :logout
    post "/refresh", AuthController, :refresh
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:pantheon, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PantheonWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  defp require_authenticated_user(conn, _opts) do
    if get_session(conn, "current_user_id") do
      conn
    else
      conn
      |> Phoenix.Controller.put_flash(:error, "You must be logged in to access this page.")
      |> Phoenix.Controller.redirect(to: "/auth/login?return_to=#{conn.request_path}")
      |> halt()
    end
  end
end
