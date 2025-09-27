defmodule RobotTable.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # Core safety system - highest priority
        RobotTable.SafetySystem,

        # Alarm management
        RobotTable.AlarmManager,

        # Network connectivity
        RobotTable.NetworkManager,

        # Motion control systems
        RobotTable.MotionControl.TableController,
        RobotTable.GrinderController,

        # Children for all targets
        # Starts a worker by calling: RobotTable.Worker.start_link(arg)
        # {RobotTable.Worker, arg},
      ] ++ target_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RobotTable.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # List all child processes to be supervised
  if Mix.target() == :host do
    defp target_children() do
      [
        # Phoenix web interface for development
        {Phoenix.PubSub, name: RobotTable.PubSub},
        RobotTableWeb.Endpoint,

        # Children that only run on the host during development or test.
        # In general, prefer using `config/host.exs` for differences.
        #
        # Starts a worker by calling: Host.Worker.start_link(arg)
        # {Host.Worker, arg},
      ]
    end
  else
    defp target_children() do
      [
        # Phoenix web interface for production
        {Phoenix.PubSub, name: RobotTable.PubSub},
        RobotTableWeb.Endpoint,

        # Children for all targets except host
        # Starts a worker by calling: Target.Worker.start_link(arg)
        # {Target.Worker, arg},
      ]
    end
  end
end
