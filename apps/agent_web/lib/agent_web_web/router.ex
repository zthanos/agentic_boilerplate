defmodule AgentWebWeb.Router do
  use AgentWebWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AgentWebWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: AgentWeb.OpenApi
  end

  scope "/", AgentWebWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/runs", RunHistoryLive, :index
    live "/chat", ChatExecuteLive, :index

  end

  pipeline :sse do
    plug :fetch_session
  end


  scope "/api" do
    pipe_through :api

    get "/openapi", OpenApiSpex.Plug.RenderSpec, :show

    get "/swaggerui", OpenApiSpex.Plug.SwaggerUI,
      path: "/api/openapi",
      default_model_expand_depth: 3
  end

  scope "/api", AgentWebWeb do
    pipe_through :api

    get "/runs", RunController, :index
    get "/runs/:run_id", RunController, :show
    post "/llm/execute", LlmExecuteController, :execute


  end

  scope "/api", AgentWebWeb do
    pipe_through :sse

    post "/llm/execute/stream", LlmExecuteController, :stream

  end




  # Other scopes may use custom stacks.
  # scope "/api", AgentWebWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:agent_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AgentWebWeb.Telemetry
    end
  end
end
