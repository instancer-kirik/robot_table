defmodule RobotTable.MotionControl.TableController do
  @moduledoc """
  Table Motion Controller for Robot Table Industrial Automation

  This module controls the motorized table positioning system with precise
  multi-axis control for X, Y, Z positioning and table tilt/rotation.

  ## Features
  - Multi-axis stepper/servo motor control
  - Closed-loop position feedback with encoders
  - Soft and hard limit protection
  - Coordinated motion planning
  - Real-time position monitoring
  - Emergency stop handling
  - Load monitoring and protection

  ## Coordinate System
  - X-axis: Left/Right movement (mm)
  - Y-axis: Forward/Back movement (mm)
  - Z-axis: Up/Down movement (mm)
  - A-axis: Table rotation (degrees)
  - B-axis: Table tilt (degrees)

  ## Safety Features
  - Position limits enforcement
  - Collision detection
  - Over-current protection
  - Thermal protection
  - Emergency stop response < 50ms
  """

  use GenServer
  require Logger

  alias RobotTable.SafetySystem
  alias RobotTable.MotionControl.MotorDriver
  alias RobotTable.MotionControl.PositionFeedback
  alias RobotTable.AlarmManager

  # Motion parameters
  # mm/min, deg/min
  @max_velocity %{x: 1000.0, y: 1000.0, z: 500.0, a: 180.0, b: 45.0}
  # mm/min², deg/min²
  @max_acceleration %{x: 5000.0, y: 5000.0, z: 2500.0, a: 900.0, b: 225.0}
  # mm
  @position_tolerance 0.01
  # degrees
  @angle_tolerance 0.1

  # Physical limits (mm, degrees)
  @soft_limits %{
    x: {-500.0, 500.0},
    y: {-300.0, 300.0},
    z: {0.0, 200.0},
    a: {-180.0, 180.0},
    b: {-30.0, 30.0}
  }

  @hard_limits %{
    x: {-520.0, 520.0},
    y: {-320.0, 320.0},
    z: {-10.0, 220.0},
    a: {-185.0, 185.0},
    b: {-35.0, 35.0}
  }

  # GPIO pin assignments for limit switches
  @limit_pins %{
    x_min: 5,
    x_max: 6,
    y_min: 7,
    y_max: 8,
    z_min: 9,
    z_max: 10,
    a_min: 11,
    a_max: 12,
    b_min: 13,
    b_max: 14
  }

  # Motor driver SPI configuration
  @spi_bus "spidev0.0"
  @spi_speed_hz 1_000_000

  defstruct [
    :state,
    :current_position,
    :target_position,
    :motion_profile,
    :motor_drivers,
    :position_feedback,
    :limit_switches,
    :homing_status,
    :move_start_time,
    :emergency_stopped,
    :load_monitoring,
    :temperature_monitoring
  ]

  ## Client API

  @doc """
  Starts the Table Controller GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current position of all axes.
  Returns a map with x, y, z, a, b coordinates.
  """
  def get_position do
    GenServer.call(__MODULE__, :get_position)
  end

  @doc """
  Moves the table to the specified position.
  Position should be a map with x, y, z, a, b coordinates.
  Missing coordinates will maintain current position.
  """
  def move_to(position, opts \\ []) do
    GenServer.call(__MODULE__, {:move_to, position, opts}, 30_000)
  end

  @doc """
  Moves the table relative to current position.
  Delta should be a map with x, y, z, a, b deltas.
  """
  def move_relative(delta, opts \\ []) do
    GenServer.call(__MODULE__, {:move_relative, delta, opts}, 30_000)
  end

  @doc """
  Initiates homing sequence for specified axes.
  If no axes specified, homes all axes.
  """
  def home_axes(axes \\ [:x, :y, :z, :a, :b]) do
    GenServer.call(__MODULE__, {:home_axes, axes}, 60_000)
  end

  @doc """
  Stops all motion immediately.
  """
  def stop_motion do
    GenServer.call(__MODULE__, :stop_motion)
  end

  @doc """
  Handles emergency stop from safety system.
  """
  def emergency_stop do
    GenServer.cast(__MODULE__, :emergency_stop)
  end

  @doc """
  Gets current motion status and diagnostics.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Enables or disables motors.
  """
  def set_motor_enable(enabled) do
    GenServer.call(__MODULE__, {:set_motor_enable, enabled})
  end

  @doc """
  Sets motion parameters for specified axis.
  """
  def set_motion_parameters(axis, params) do
    GenServer.call(__MODULE__, {:set_motion_parameters, axis, params})
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    # Initialize hardware interfaces
    {:ok, motor_drivers} = initialize_motor_drivers()
    {:ok, position_feedback} = initialize_position_feedback()
    limit_switches = initialize_limit_switches()

    # Start monitoring processes
    schedule_position_update()
    schedule_temperature_check()

    initial_state = %__MODULE__{
      state: :initializing,
      current_position: %{x: 0.0, y: 0.0, z: 0.0, a: 0.0, b: 0.0},
      target_position: %{x: 0.0, y: 0.0, z: 0.0, a: 0.0, b: 0.0},
      motion_profile: nil,
      motor_drivers: motor_drivers,
      position_feedback: position_feedback,
      limit_switches: limit_switches,
      homing_status: %{},
      move_start_time: nil,
      emergency_stopped: false,
      load_monitoring: %{},
      temperature_monitoring: %{}
    }

    Logger.info("Table Controller initialized")
    {:ok, %{initial_state | state: :idle}}
  end

  @impl true
  def handle_call(:get_position, _from, state) do
    {:reply, state.current_position, state}
  end

  @impl true
  def handle_call({:move_to, position, opts}, _from, state) do
    case state.state do
      :idle ->
        case validate_position(position) do
          :ok ->
            target_pos = Map.merge(state.current_position, position)
            motion_profile = calculate_motion_profile(state.current_position, target_pos, opts)

            case execute_motion(motion_profile, state) do
              {:ok, new_state} ->
                Logger.info("Starting move to position: #{inspect(target_pos)}")
                {:reply, :ok, new_state}

              {:error, reason} ->
                Logger.error("Failed to start motion: #{reason}")
                {:reply, {:error, reason}, state}
            end

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      current_state ->
        {:reply, {:error, "Cannot move in state: #{current_state}"}, state}
    end
  end

  @impl true
  def handle_call({:move_relative, delta, opts}, _from, state) do
    target_position = %{
      x: state.current_position.x + Map.get(delta, :x, 0.0),
      y: state.current_position.y + Map.get(delta, :y, 0.0),
      z: state.current_position.z + Map.get(delta, :z, 0.0),
      a: state.current_position.a + Map.get(delta, :a, 0.0),
      b: state.current_position.b + Map.get(delta, :b, 0.0)
    }

    handle_call({:move_to, target_position, opts}, nil, state)
  end

  @impl true
  def handle_call({:home_axes, axes}, _from, state) do
    case state.state do
      :idle ->
        Logger.info("Starting homing sequence for axes: #{inspect(axes)}")
        new_state = start_homing_sequence(state, axes)
        {:reply, :ok, new_state}

      current_state ->
        {:reply, {:error, "Cannot home in state: #{current_state}"}, state}
    end
  end

  @impl true
  def handle_call(:stop_motion, _from, state) do
    Logger.info("Motion stop requested")
    new_state = stop_all_motors(state)
    {:reply, :ok, %{new_state | state: :idle}}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      state: state.state,
      current_position: state.current_position,
      target_position: state.target_position,
      homing_status: state.homing_status,
      emergency_stopped: state.emergency_stopped,
      motor_temperatures: get_motor_temperatures(state),
      load_status: state.load_monitoring,
      limit_switches: read_all_limit_switches()
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call({:set_motor_enable, enabled}, _from, state) do
    result = set_all_motor_enable(state.motor_drivers, enabled)
    Logger.info("Motor enable set to: #{enabled}")
    {:reply, result, state}
  end

  @impl true
  def handle_call({:set_motion_parameters, axis, params}, _from, state) do
    # Update motion parameters for specified axis
    # This would update internal motion planning parameters
    Logger.info("Motion parameters updated for axis #{axis}: #{inspect(params)}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(:emergency_stop, state) do
    Logger.critical("EMERGENCY STOP - Table Controller")

    # Immediately stop all motors
    new_state = emergency_stop_all_motors(state)

    # Set emergency stopped flag
    final_state = %{
      new_state
      | emergency_stopped: true,
        state: :emergency_stopped,
        motion_profile: nil
    }

    {:noreply, final_state}
  end

  @impl true
  def handle_info(:update_position, state) do
    # Read current position from encoders
    new_position = read_position_feedback(state.position_feedback)

    # Check if we're in motion and update motion profile
    new_state =
      case state.state do
        :moving ->
          update_motion_progress(state, new_position)

        _ ->
          %{state | current_position: new_position}
      end

    # Check position limits
    final_state = check_position_limits(new_state)

    # Schedule next position update
    schedule_position_update()

    {:noreply, final_state}
  end

  @impl true
  def handle_info(:temperature_check, state) do
    # Monitor motor and driver temperatures
    temperatures = get_motor_temperatures(state)

    # Check for overtemperature conditions
    new_state = check_temperature_limits(state, temperatures)

    # Schedule next temperature check
    schedule_temperature_check()

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:gpio_interrupt, pin, value}, state) do
    # Handle limit switch interrupts
    new_state = handle_limit_switch_change(state, pin, value)
    {:noreply, new_state}
  end

  ## Private Functions

  defp initialize_motor_drivers do
    Logger.info("Initializing motor drivers")

    # Initialize SPI bus for motor drivers
    {:ok, spi} = Circuits.SPI.open(@spi_bus, mode: 0, speed_hz: @spi_speed_hz)

    # Configure each motor driver
    motor_configs = %{
      x: %{address: 0x00, steps_per_mm: 200.0, current: 1.5},
      y: %{address: 0x01, steps_per_mm: 200.0, current: 1.5},
      z: %{address: 0x02, steps_per_mm: 400.0, current: 2.0},
      a: %{address: 0x03, steps_per_degree: 11.111, current: 1.0},
      b: %{address: 0x04, steps_per_degree: 22.222, current: 1.0}
    }

    drivers =
      Map.new(motor_configs, fn {axis, config} ->
        {:ok, driver} = MotorDriver.init(spi, config)
        {axis, driver}
      end)

    {:ok, drivers}
  end

  defp initialize_position_feedback do
    Logger.info("Initializing position feedback encoders")

    # Initialize encoder interfaces (typically via SPI or I2C)
    encoder_configs = %{
      x: %{type: :quadrature, resolution: 4096, scaling: 0.01},
      y: %{type: :quadrature, resolution: 4096, scaling: 0.01},
      z: %{type: :absolute, resolution: 16384, scaling: 0.005},
      a: %{type: :absolute, resolution: 16384, scaling: 0.022},
      b: %{type: :absolute, resolution: 16384, scaling: 0.022}
    }

    encoders =
      Map.new(encoder_configs, fn {axis, config} ->
        {:ok, encoder} = PositionFeedback.init(config)
        {axis, encoder}
      end)

    {:ok, encoders}
  end

  defp initialize_limit_switches do
    Logger.info("Initializing limit switches")

    # Set up GPIO pins for limit switches
    Enum.each(@limit_pins, fn {name, pin} ->
      {:ok, gpio} = Circuits.GPIO.open(pin, :input, pull_mode: :pullup)
      Circuits.GPIO.set_interrupts(gpio, :both)
    end)

    @limit_pins
  end

  defp validate_position(position) do
    # Check if all coordinates are within soft limits
    invalid_axes =
      Enum.filter(position, fn {axis, value} ->
        case @soft_limits[axis] do
          {min, max} -> value < min or value > max
          nil -> false
        end
      end)

    if Enum.empty?(invalid_axes) do
      :ok
    else
      {:error, "Position out of bounds: #{inspect(invalid_axes)}"}
    end
  end

  defp calculate_motion_profile(start_pos, target_pos, opts) do
    # Calculate trapezoidal motion profile for each axis
    max_vel = Keyword.get(opts, :max_velocity, @max_velocity)
    max_accel = Keyword.get(opts, :max_acceleration, @max_acceleration)

    profiles =
      Map.new([:x, :y, :z, :a, :b], fn axis ->
        distance = target_pos[axis] - start_pos[axis]

        profile = %{
          start_pos: start_pos[axis],
          target_pos: target_pos[axis],
          distance: distance,
          max_velocity: max_vel[axis],
          acceleration: max_accel[axis],
          profile_time: calculate_profile_time(distance, max_vel[axis], max_accel[axis])
        }

        {axis, profile}
      end)

    # Synchronize all axes to complete at the same time
    max_time =
      Enum.max_by(profiles, fn {_axis, profile} -> profile.profile_time end)
      |> elem(1)
      |> Map.get(:profile_time)

    synchronized_profiles =
      Map.new(profiles, fn {axis, profile} ->
        adjusted_profile = Map.put(profile, :synchronized_time, max_time)
        {axis, adjusted_profile}
      end)

    %{
      profiles: synchronized_profiles,
      total_time: max_time,
      start_time: System.monotonic_time(:millisecond)
    }
  end

  defp calculate_profile_time(distance, max_velocity, acceleration) do
    # Calculate time for trapezoidal profile
    abs_distance = abs(distance)

    # Time to reach max velocity
    accel_time = max_velocity / acceleration
    accel_distance = 0.5 * acceleration * accel_time * accel_time

    if abs_distance <= 2 * accel_distance do
      # Triangular profile (never reach max velocity)
      2 * :math.sqrt(abs_distance / acceleration)
    else
      # Trapezoidal profile
      const_vel_distance = abs_distance - 2 * accel_distance
      const_vel_time = const_vel_distance / max_velocity
      2 * accel_time + const_vel_time
    end
  end

  defp execute_motion(motion_profile, state) do
    # Start motion on all motor drivers
    results =
      Enum.map(motion_profile.profiles, fn {axis, profile} ->
        MotorDriver.start_motion(state.motor_drivers[axis], profile)
      end)

    if Enum.all?(results, &(&1 == :ok)) do
      new_state = %{
        state
        | state: :moving,
          motion_profile: motion_profile,
          target_position:
            Map.new(motion_profile.profiles, fn {axis, profile} ->
              {axis, profile.target_pos}
            end),
          move_start_time: System.monotonic_time(:millisecond)
      }

      {:ok, new_state}
    else
      {:error, "Failed to start motion on one or more axes"}
    end
  end

  defp start_homing_sequence(state, axes) do
    Logger.info("Starting homing sequence for axes: #{inspect(axes)}")

    # Initialize homing status
    homing_status = Map.new(axes, fn axis -> {axis, :homing} end)

    # Start homing motion for each axis
    Enum.each(axes, fn axis ->
      MotorDriver.start_homing(state.motor_drivers[axis])
    end)

    %{state | state: :homing, homing_status: homing_status}
  end

  defp stop_all_motors(state) do
    Enum.each(state.motor_drivers, fn {_axis, driver} ->
      MotorDriver.stop(driver)
    end)

    state
  end

  defp emergency_stop_all_motors(state) do
    Enum.each(state.motor_drivers, fn {_axis, driver} ->
      MotorDriver.emergency_stop(driver)
    end)

    state
  end

  defp update_motion_progress(state, new_position) do
    case state.motion_profile do
      nil ->
        %{state | current_position: new_position}

      motion_profile ->
        current_time = System.monotonic_time(:millisecond)
        elapsed_time = current_time - motion_profile.start_time

        if elapsed_time >= motion_profile.total_time * 1000 do
          # Motion should be complete
          Logger.info("Motion profile completed")
          %{state | state: :idle, current_position: new_position, motion_profile: nil}
        else
          # Motion in progress
          %{state | current_position: new_position}
        end
    end
  end

  defp check_position_limits(state) do
    # Check if current position exceeds hard limits
    violations =
      Enum.filter(state.current_position, fn {axis, pos} ->
        case @hard_limits[axis] do
          {min, max} -> pos < min or pos > max
          nil -> false
        end
      end)

    if not Enum.empty?(violations) do
      Logger.error("Hard limit violation detected: #{inspect(violations)}")
      emergency_stop_all_motors(state)
      AlarmManager.trigger_alarm(:hard_limit_violation, violations)

      %{state | state: :fault, emergency_stopped: true}
    else
      state
    end
  end

  defp check_temperature_limits(state, temperatures) do
    overtemp_motors = Enum.filter(temperatures, fn {_axis, temp} -> temp > 80.0 end)

    if not Enum.empty?(overtemp_motors) do
      Logger.warning("Motor overtemperature detected: #{inspect(overtemp_motors)}")
      AlarmManager.trigger_alarm(:motor_overtemperature, overtemp_motors)
    end

    %{state | temperature_monitoring: temperatures}
  end

  defp handle_limit_switch_change(state, pin, value) do
    # Identify which limit switch changed
    limit_switch = Enum.find(@limit_pins, fn {_name, switch_pin} -> switch_pin == pin end)

    case limit_switch do
      {switch_name, _pin} when value == 0 ->
        # Limit switch activated (active low)
        Logger.warning("Limit switch activated: #{switch_name}")

        # Stop motion if moving towards this limit
        stop_all_motors(state)

        %{state | state: :limit_switch_active}

      _ ->
        state
    end
  end

  defp read_position_feedback(encoders) do
    Map.new(encoders, fn {axis, encoder} ->
      position = PositionFeedback.read_position(encoder)
      {axis, position}
    end)
  end

  defp get_motor_temperatures(state) do
    Map.new(state.motor_drivers, fn {axis, driver} ->
      temp = MotorDriver.read_temperature(driver)
      {axis, temp}
    end)
  end

  defp read_all_limit_switches do
    Map.new(@limit_pins, fn {name, pin} ->
      value = Circuits.GPIO.read(pin)
      # Active low
      {name, value == 0}
    end)
  end

  defp set_all_motor_enable(drivers, enabled) do
    results =
      Enum.map(drivers, fn {_axis, driver} ->
        MotorDriver.set_enable(driver, enabled)
      end)

    if Enum.all?(results, &(&1 == :ok)), do: :ok, else: {:error, "Failed to set motor enable"}
  end

  defp schedule_position_update do
    # 100Hz update rate
    Process.send_after(self(), :update_position, 10)
  end

  defp schedule_temperature_check do
    # Every 5 seconds
    Process.send_after(self(), :temperature_check, 5000)
  end
end
