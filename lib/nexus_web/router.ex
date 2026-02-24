defmodule NexusWeb.Router do
  use NexusWeb, :router

  import Oban.Web.Router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {NexusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]

    plug AshAuthentication.Strategy.ApiKey.Plug,
      resource: Nexus.Accounts.User,
      # if you want to require an api key to be supplied, set `required?` to true
      required?: false

    plug :load_from_bearer
    plug :set_actor, :user
  end

  pipeline :public_api do
    plug :accepts, ["json"]
    plug NexusWeb.Plugs.ProjectApiKeyAuth
  end

  # Public media proxy — no auth required
  scope "/media", NexusWeb do
    pipe_through []
    get "/*path", MediaController, :show
  end

  scope "/", NexusWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes do
      live "/admin", ProjectLive.Index, :index
      live "/admin/new", ProjectLive.Index, :new
      live "/admin/:slug", ProjectLive.Show, :show
      live "/admin/:slug/settings", ProjectLive.Settings, :edit
      live "/admin/:slug/members", MembershipLive.Index, :index
      live "/admin/:slug/api-keys", ProjectApiKeyLive.Index, :index
      live "/admin/:slug/pages/new", PageLive.New, :new
      live "/admin/:slug/pages/:id/edit", PageLive.Edit, :edit
      live "/admin/:slug/media", MediaLive.Index, :index
      live "/admin/:slug/pages/:id/versions", PageLive.Versions, :index
    end
  end

  scope "/", NexusWeb do
    pipe_through :browser

    get "/", PageController, :home
    auth_routes AuthController, Nexus.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Remove these if you'd like to use your own authentication views
    sign_in_route reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{NexusWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    NexusWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  NexusWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

    # Remove this if you do not use the confirmation strategy
    confirm_route Nexus.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [NexusWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(Nexus.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [NexusWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]
    )
  end

  forward "/api/docs",
          OpenApiSpex.Plug.SwaggerUI,
          path: "/api/v1/open_api",
          default_model_expand_depth: 4

  scope "/api/v1" do
    pipe_through :public_api

    forward "/", NexusWeb.AshJsonApiRouter
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:nexus, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: NexusWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/" do
      pipe_through :browser

      oban_dashboard("/oban")
    end
  end
end
