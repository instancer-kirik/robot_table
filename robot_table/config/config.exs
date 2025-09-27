# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
import Config

# Enable the Nerves integration with Mix
Application.start(:nerves_bootstrap)

config :robot_table, target: Mix.target()

# Customize non-Elixir parts of the firmware. See
# https://hexdocs.pm/nerves/advanced-configuration.html for details.

config :nerves, :firmware, rootfs_overlay: "rootfs_overlay"

# Set the SOURCE_DATE_EPOCH date for reproducible builds.
# See https://reproducible-builds.org/docs/source-date-epoch/ for more information

config :nerves, source_date_epoch: "1734968400"

# Configure Phoenix Framework
config :robot_table, RobotTableWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: RobotTableWeb.ErrorHTML, json: RobotTableWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: RobotTable.PubSub,
  live_view: [signing_salt: "industrial_robot_table"]

# Configure Phoenix LiveView
config :phoenix, :json_library, Jason

# Configure logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Industrial automation specific config
config :robot_table,
  # Safety system configuration
  safety_system: [
    emergency_stop_timeout_ms: 50,
    watchdog_timeout_ms: 1000,
    self_test_interval_hours: 24
  ],
  # Motion control configuration
  motion_control: [
    position_tolerance_mm: 0.01,
    max_velocity_mm_min: 1000,
    max_acceleration_mm_min2: 5000
  ],
  # Grinder configuration
  grinder: [
    max_speed_rpm: 11000,
    min_speed_rpm: 1000,
    emergency_stop_time_ms: 250
  ]

if Mix.target() == :host do
  import_config "host.exs"
else
  import_config "target.exs"
end
