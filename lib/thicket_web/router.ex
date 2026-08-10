defmodule ThicketWeb.Router do
  use ThicketWeb, :router

  import ThicketWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ThicketWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :federation do
    plug :put_secure_browser_headers
  end

  scope "/", ThicketWeb do
    pipe_through :federation

    get "/.well-known/webfinger", FederationController, :webfinger
    get "/ap/channels/:handle", FederationController, :actor
    get "/ap/channels/:handle/outbox", FederationController, :outbox
    get "/ap/channels/:handle/followers", FederationController, :followers
    get "/ap/channels/:handle/following", FederationController, :following
    post "/ap/channels/:handle/inbox", FederationController, :inbox
    post "/ap/inbox", FederationController, :inbox
    get "/ap/posts/:id", FederationController, :object
  end

  scope "/", ThicketWeb do
    pipe_through :browser

    get "/", PageController, :home

    live_session :public, on_mount: [{ThicketWeb.UserAuth, :mount_current_scope}] do
      live "/discover", TimelineLive, :discovery
      live "/tags/:tag", TimelineLive, :tag
      live "/channels/:handle", ChannelLive.Show, :show
      live "/posts/:id", PostLive.Show, :show
    end
  end

  scope "/health", ThicketWeb do
    pipe_through :api
    get "/live", HealthController, :live
    get "/ready", HealthController, :ready
  end

  # Other scopes may use custom stacks.
  # scope "/api", ThicketWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:thicket, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ThicketWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", ThicketWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{ThicketWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/home", TimelineLive, :home
      live "/compose", PostLive.Form, :new
      live "/posts/:id/edit", PostLive.Form, :edit
      live "/channels", ChannelLive.Index, :index
      live "/channels/:handle/settings", ChannelLive.Settings, :edit
      live "/notifications", NotificationLive, :index
      live "/following/remote", RemoteFollowLive, :index
      live "/admin/invitations", Admin.InvitationLive, :index
      live "/admin/moderation", Admin.ModerationLive, :index
      live "/admin/federation", Admin.FederationLive, :index
    end

    post "/users/update-password", UserSessionController, :update_password
    post "/channels/switch", ChannelSessionController, :create
  end

  scope "/", ThicketWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{ThicketWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
