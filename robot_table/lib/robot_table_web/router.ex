defmodule RobotTableWeb.Router do
  use RobotTableWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RobotTableWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Industrial safety pipeline - additional security for control operations
  pipeline :industrial_control do
    plug :browser
    plug RobotTableWeb.Plugs.SafetyCheck
    plug RobotTableWeb.Plugs.OperatorAuth
  end

  scope "/", RobotTableWeb do
    pipe_through :browser

    # Main dashboard - real-time system overview
    live "/", DashboardLive, :index

    # System status and monitoring
    live "/status", StatusLive, :index
    live "/diagnostics", DiagnosticsLive, :index
    live "/alarms", AlarmsLive, :index
  end

  # Industrial control interfaces (requires additional authentication)
  scope "/control", RobotTableWeb do
    pipe_through :industrial_control

    # Motion control interface
    live "/table", TableControlLive, :index
    live "/grinder", GrinderControlLive, :index

    # Safety system interface
    live "/safety", SafetyControlLive, :index
    live "/emergency", EmergencyControlLive, :index
  end

  # API endpoints for programmatic access
  scope "/api/v1", RobotTableWeb do
    pipe_through :api

    # System information endpoints
    get "/status", ApiController, :status
    get "/diagnostics", ApiController, :diagnostics
    get "/alarms", ApiController, :alarms

    # Control endpoints (POST only for safety)
    post "/table/move", ApiController, :table_move
    post "/table/home", ApiController, :table_home
    post "/table/stop", ApiController, :table_stop

    post "/grinder/start", ApiController, :grinder_start
    post "/grinder/stop", ApiController, :grinder_stop
    post "/grinder/speed", ApiController, :grinder_speed

    post "/emergency_stop", ApiController, :emergency_stop
    post "/safety/reset", ApiController, :safety_reset
    post "/alarms/acknowledge", ApiController, :acknowledge_alarm
  end

  # Development tools (only available in dev/test)
  if Application.compile_env(:robot_table, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: RobotTableWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # WebSocket API for real-time data streaming
  scope "/ws", RobotTableWeb do
    pipe_through :api

    get "/telemetry", WebSocketController, :telemetry
    get "/control", WebSocketController, :control
  end

  # Static files for industrial HMI assets
  scope "/assets", RobotTableWeb do
    get "/industrial/*path", StaticController, :industrial_assets
  end

  # Health check endpoint for monitoring systems
  get "/health", RobotTableWeb.HealthController, :check

  # Network configuration interface (Colemak-friendly)
  scope "/network", RobotTableWeb do
    pipe_through :industrial_control

    live "/wifi", NetworkConfigLive, :wifi
    live "/diagnostics", NetworkDiagnosticsLive, :index
  end
end
