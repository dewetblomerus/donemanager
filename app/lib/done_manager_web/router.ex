defmodule DoneManagerWeb.Router do
  use DoneManagerWeb, :router

  import DoneManagerWeb.ApiAuth
  import DoneManagerWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DoneManagerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DoneManagerWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/auth", DoneManagerWeb do
    pipe_through :browser

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    delete "/logout", AuthController, :delete
  end

  scope "/", DoneManagerWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated,
      on_mount: [{DoneManagerWeb.UserAuth, :require_authenticated}] do
      live "/households", HouseholdLive.Index, :index
      live "/households/new", HouseholdLive.Form, :new
      live "/households/:id", HouseholdLive.Show, :show
      live "/invitations", InvitationLive.Index, :index
      live "/households/:id/tasks", TaskLive.Index, :index
      live "/households/:id/tasks/new", TaskLive.Form, :new
      live "/tasks/:id", TaskLive.Show, :show
    end
  end

  # Integration API. NFC tags bake in these paths — see architecture/api.md.
  scope "/v1", DoneManagerWeb do
    pipe_through [:api, :require_bearer_token]

    post "/tags/:external_id/scans", ScanController, :create
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:done_manager, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DoneManagerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
