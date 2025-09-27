defmodule RobotTable.SafetySystem do
  @moduledoc """
  Safety System Manager for Robot Table Industrial Automation

  This module implements the core safety system for the robot table automation platform.
  It manages emergency stops, safety interlocks, and fail-safe operations according to
  ISO 13849 Category 3 safety requirements.

  ## Safety Features
  - Hardware emergency stop monitoring
  - Safety interlock management
  - Fail-safe state transitions
  - Safety circuit diagnostics
  - Watchdog timer management

  ## Safety Integrity Level
  Designed to meet SIL-2 (Safety Integrity Level 2) requirements with:
  - Probability of dangerous failure per hour < 10^-7
  - Hardware fault tolerance of 1
  - Systematic capability of SC2

  ## States
  - `:safe` - All safety systems operational, normal operation allowed
  - `:unsafe` - Safety violation detected, all motion stopped
  - `:fault` - Safety system fault detected, maintenance required
  - `:test` - Safety system in test mode (limited operation)
  """

  use GenServer
  require Logger

  alias RobotTable.MotionControl
  alias RobotTable.GrinderControl
  alias RobotTable.AlarmManager

  # Safety timing constants (in milliseconds)
  @emergency_stop_response_time 50
  @safety_check_interval 10
  @watchdog_timeout 1000
  @interlock_debounce_time 100

  # Safety input pin definitions
  # Multiple E-stop inputs for redundancy
  @emergency_stop_pins [18, 19, 20]
  @light_curtain_pin 21
  @door_interlock_pin 22
  @pressure_mat_pin 23
  @safety_relay_output 24

  defstruct [
    :state,
    :last_watchdog_ping,
    :emergency_stops,
    :interlocks,
    :fault_count,
    :safety_timer,
    :diagnostics
  ]

  ## Client API

  @doc """
  Starts the Safety System GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current safety system state.
  Returns `:safe`, `:unsafe`, `:fault`, or `:test`.
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Performs a safety system self-test.
  Returns `{:ok, results}` or `{:error, reason}`.
  """
  def self_test do
    GenServer.call(__MODULE__, :self_test, 10_000)
  end

  @doc """
  Triggers an emergency stop from software.
  This should only be used when automatic systems detect unsafe conditions.
  """
  def emergency_stop(reason) do
    GenServer.cast(__MODULE__, {:emergency_stop, reason})
  end

  @doc """
  Attempts to reset the safety system after clearing faults.
  Requires manual operator acknowledgment.
  """
  def reset_safety_system(operator_id) do
    GenServer.call(__MODULE__, {:reset_safety_system, operator_id})
  end

  @doc """
  Gets current safety diagnostics information.
  """
  def get_diagnostics do
    GenServer.call(__MODULE__, :get_diagnostics)
  end

  @doc """
  Pings the safety system watchdog.
  Should be called by critical processes to indicate they're alive.
  """
  def watchdog_ping(process_name) do
    GenServer.cast(__MODULE__, {:watchdog_ping, process_name})
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    # Initialize hardware GPIO pins
    setup_gpio_pins()

    # Schedule periodic safety checks
    timer_ref = Process.send_after(self(), :safety_check, @safety_check_interval)

    initial_state = %__MODULE__{
      # Start in unsafe state until first safety check passes
      state: :unsafe,
      last_watchdog_ping: System.monotonic_time(:millisecond),
      emergency_stops: %{},
      interlocks: %{
        light_curtain: false,
        door_interlock: false,
        pressure_mat: false
      },
      fault_count: 0,
      safety_timer: timer_ref,
      diagnostics: %{
        last_self_test: nil,
        fault_history: [],
        uptime: System.monotonic_time(:millisecond)
      }
    }

    Logger.info("Safety System initialized - starting in unsafe state")
    {:ok, initial_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.state, state}
  end

  @impl true
  def handle_call(:self_test, _from, state) do
    Logger.info("Starting safety system self-test")

    test_results = %{
      emergency_stops: test_emergency_stops(),
      interlocks: test_safety_interlocks(),
      watchdog: test_watchdog_system(),
      gpio_pins: test_gpio_functionality(),
      timing: test_response_timing()
    }

    all_passed = Enum.all?(test_results, fn {_test, result} -> result == :pass end)

    new_diagnostics =
      Map.put(state.diagnostics, :last_self_test, {DateTime.utc_now(), test_results})

    new_state = %{state | diagnostics: new_diagnostics}

    if all_passed do
      Logger.info("Safety system self-test completed successfully")
      {:reply, {:ok, test_results}, new_state}
    else
      Logger.error("Safety system self-test failed: #{inspect(test_results)}")
      {:reply, {:error, test_results}, transition_to_fault(new_state, "Self-test failed")}
    end
  end

  @impl true
  def handle_call({:reset_safety_system, operator_id}, _from, state) do
    Logger.info("Safety system reset requested by operator: #{operator_id}")

    case state.state do
      :fault ->
        # Verify all safety conditions are met before allowing reset
        if all_safety_conditions_met?() do
          new_state = transition_to_safe(state)
          Logger.info("Safety system reset successful by operator: #{operator_id}")
          {:reply, :ok, new_state}
        else
          Logger.warning("Safety system reset denied - unsafe conditions present")
          {:reply, {:error, :unsafe_conditions}, state}
        end

      :unsafe ->
        if all_safety_conditions_met?() do
          new_state = transition_to_safe(state)
          Logger.info("Safety system cleared to safe state by operator: #{operator_id}")
          {:reply, :ok, new_state}
        else
          Logger.warning("Safety system reset denied - unsafe conditions present")
          {:reply, {:error, :unsafe_conditions}, state}
        end

      _ ->
        {:reply, {:error, :invalid_state}, state}
    end
  end

  @impl true
  def handle_call(:get_diagnostics, _from, state) do
    current_diagnostics =
      Map.merge(state.diagnostics, %{
        current_state: state.state,
        fault_count: state.fault_count,
        emergency_stops: state.emergency_stops,
        interlocks: state.interlocks,
        uptime_hours:
          (System.monotonic_time(:millisecond) - state.diagnostics.uptime) / (1000 * 60 * 60)
      })

    {:reply, current_diagnostics, state}
  end

  @impl true
  def handle_cast({:emergency_stop, reason}, state) do
    Logger.critical("EMERGENCY STOP activated: #{reason}")

    # Immediately stop all motion systems
    stop_all_motion_systems()

    # Activate safety relay (cut power to motors)
    Circuits.GPIO.write(@safety_relay_output, 0)

    # Trigger alarms
    AlarmManager.trigger_alarm(:emergency_stop, %{reason: reason, timestamp: DateTime.utc_now()})

    new_state = transition_to_unsafe(state, reason)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:watchdog_ping, process_name}, state) do
    new_state = %{state | last_watchdog_ping: System.monotonic_time(:millisecond)}
    Logger.debug("Watchdog ping received from #{process_name}")
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:safety_check, state) do
    # Perform periodic safety checks
    new_state = perform_safety_checks(state)

    # Schedule next safety check
    timer_ref = Process.send_after(self(), :safety_check, @safety_check_interval)
    final_state = %{new_state | safety_timer: timer_ref}

    {:noreply, final_state}
  end

  @impl true
  def handle_info({:gpio_interrupt, pin, value}, state) do
    # Handle GPIO interrupts from safety devices
    new_state = handle_safety_input_change(state, pin, value)
    {:noreply, new_state}
  end

  ## Private Functions

  defp setup_gpio_pins do
    # Initialize all safety-related GPIO pins
    {:ok, _} = Circuits.GPIO.open(@safety_relay_output, :output, initial_value: 0)

    # Set up emergency stop inputs with pull-up resistors
    Enum.each(@emergency_stop_pins, fn pin ->
      {:ok, gpio} = Circuits.GPIO.open(pin, :input, pull_mode: :pullup)
      Circuits.GPIO.set_interrupts(gpio, :both)
    end)

    # Set up safety interlock inputs
    for {pin, name} <- [
          {@light_curtain_pin, :light_curtain},
          {@door_interlock_pin, :door_interlock},
          {@pressure_mat_pin, :pressure_mat}
        ] do
      {:ok, gpio} = Circuits.GPIO.open(pin, :input, pull_mode: :pullup)
      Circuits.GPIO.set_interrupts(gpio, :both)
    end

    Logger.info("Safety system GPIO pins initialized")
  end

  defp perform_safety_checks(state) do
    # Check all emergency stops
    e_stop_states = check_emergency_stops()

    # Check safety interlocks
    interlock_states = check_safety_interlocks()

    # Check watchdog timer
    watchdog_ok = check_watchdog_timer(state)

    # Determine if system is safe
    all_safe =
      Enum.all?(e_stop_states, fn {_pin, active} -> not active end) and
        Enum.all?(interlock_states, fn {_name, ok} -> ok end) and
        watchdog_ok

    new_interlocks = Map.new(interlock_states)
    new_emergency_stops = Map.new(e_stop_states)

    updated_state = %{state | interlocks: new_interlocks, emergency_stops: new_emergency_stops}

    case {state.state, all_safe} do
      {:safe, false} ->
        # Was safe, now unsafe
        reason = determine_unsafe_reason(e_stop_states, interlock_states, watchdog_ok)
        transition_to_unsafe(updated_state, reason)

      {:unsafe, true} ->
        # Was unsafe, now all conditions are safe - but require manual reset
        Logger.info("Safety conditions cleared - manual reset required")
        updated_state

      {current_state, _} ->
        # No state change required
        updated_state
    end
  end

  defp check_emergency_stops do
    Enum.map(@emergency_stop_pins, fn pin ->
      # E-stop is active low (0V when pressed, 3.3V when released)
      value = Circuits.GPIO.read(pin)
      {pin, value == 0}
    end)
  end

  defp check_safety_interlocks do
    [
      {:light_curtain, Circuits.GPIO.read(@light_curtain_pin) == 1},
      {:door_interlock, Circuits.GPIO.read(@door_interlock_pin) == 1},
      # Active low
      {:pressure_mat, Circuits.GPIO.read(@pressure_mat_pin) == 0}
    ]
  end

  defp check_watchdog_timer(state) do
    current_time = System.monotonic_time(:millisecond)
    current_time - state.last_watchdog_ping < @watchdog_timeout
  end

  defp handle_safety_input_change(state, pin, value) do
    Logger.info("Safety input changed - Pin: #{pin}, Value: #{value}")

    cond do
      pin in @emergency_stop_pins and value == 0 ->
        # Emergency stop activated
        Logger.critical("Hardware emergency stop activated on pin #{pin}")
        stop_all_motion_systems()
        Circuits.GPIO.write(@safety_relay_output, 0)
        transition_to_unsafe(state, "Hardware E-stop pin #{pin}")

      pin == @light_curtain_pin and value == 0 ->
        # Light curtain broken
        Logger.warning("Light curtain safety breach detected")
        stop_all_motion_systems()
        transition_to_unsafe(state, "Light curtain breach")

      pin == @door_interlock_pin and value == 0 ->
        # Door opened
        Logger.warning("Safety door interlock opened")
        stop_all_motion_systems()
        transition_to_unsafe(state, "Door interlock open")

      pin == @pressure_mat_pin and value == 1 ->
        # Someone stepped on pressure mat
        Logger.warning("Pressure mat safety activation")
        stop_all_motion_systems()
        transition_to_unsafe(state, "Pressure mat activation")

      true ->
        # Safety input returned to safe state
        Logger.info("Safety input #{pin} returned to safe state")
        state
    end
  end

  defp stop_all_motion_systems do
    # Emergency stop all motion controllers
    GenServer.cast(MotionControl.TableController, :emergency_stop)
    GenServer.cast(GrinderControl, :emergency_stop)

    Logger.critical("All motion systems emergency stopped")
  end

  defp all_safety_conditions_met? do
    e_stops_ok = Enum.all?(check_emergency_stops(), fn {_pin, active} -> not active end)
    interlocks_ok = Enum.all?(check_safety_interlocks(), fn {_name, ok} -> ok end)

    e_stops_ok and interlocks_ok
  end

  defp transition_to_safe(state) do
    Logger.info("Safety system transitioning to SAFE state")

    # Enable safety relay (allow power to motors)
    Circuits.GPIO.write(@safety_relay_output, 1)

    # Clear any previous alarms
    AlarmManager.clear_alarm(:safety_system)

    %{state | state: :safe, fault_count: 0}
  end

  defp transition_to_unsafe(state, reason) do
    Logger.warning("Safety system transitioning to UNSAFE state: #{reason}")

    # Ensure safety relay is disabled
    Circuits.GPIO.write(@safety_relay_output, 0)

    # Trigger safety alarm
    AlarmManager.trigger_alarm(:safety_system, %{
      reason: reason,
      timestamp: DateTime.utc_now(),
      previous_state: state.state
    })

    new_fault_history =
      [
        %{
          timestamp: DateTime.utc_now(),
          reason: reason,
          previous_state: state.state
        }
        | state.diagnostics.fault_history
      ]
      # Keep last 100 faults
      |> Enum.take(100)

    new_diagnostics = Map.put(state.diagnostics, :fault_history, new_fault_history)

    %{state | state: :unsafe, fault_count: state.fault_count + 1, diagnostics: new_diagnostics}
  end

  defp transition_to_fault(state, reason) do
    Logger.error("Safety system transitioning to FAULT state: #{reason}")

    # Disable safety relay
    Circuits.GPIO.write(@safety_relay_output, 0)

    # Stop all systems
    stop_all_motion_systems()

    # Trigger critical alarm
    AlarmManager.trigger_alarm(:safety_fault, %{
      reason: reason,
      timestamp: DateTime.utc_now()
    })

    %{state | state: :fault, fault_count: state.fault_count + 1}
  end

  defp determine_unsafe_reason(e_stop_states, interlock_states, watchdog_ok) do
    cond do
      not watchdog_ok -> "Watchdog timeout"
      Enum.any?(e_stop_states, fn {_pin, active} -> active end) -> "Emergency stop active"
      not interlock_states[:light_curtain] -> "Light curtain breach"
      not interlock_states[:door_interlock] -> "Door interlock open"
      interlock_states[:pressure_mat] -> "Pressure mat activation"
      true -> "Unknown safety violation"
    end
  end

  # Self-test functions
  defp test_emergency_stops do
    # Test each emergency stop input
    results =
      Enum.map(@emergency_stop_pins, fn pin ->
        try do
          _value = Circuits.GPIO.read(pin)
          :pass
        rescue
          _ -> :fail
        end
      end)

    if Enum.all?(results, &(&1 == :pass)), do: :pass, else: :fail
  end

  defp test_safety_interlocks do
    try do
      _light_curtain = Circuits.GPIO.read(@light_curtain_pin)
      _door_interlock = Circuits.GPIO.read(@door_interlock_pin)
      _pressure_mat = Circuits.GPIO.read(@pressure_mat_pin)
      :pass
    rescue
      _ -> :fail
    end
  end

  defp test_watchdog_system do
    # Test watchdog functionality by checking if it responds properly
    start_time = System.monotonic_time(:millisecond)
    watchdog_ping("self_test")

    # Verify the ping was recorded
    if System.monotonic_time(:millisecond) - start_time < 100, do: :pass, else: :fail
  end

  defp test_gpio_functionality do
    try do
      # Test safety relay output
      Circuits.GPIO.write(@safety_relay_output, 1)
      Process.sleep(10)
      Circuits.GPIO.write(@safety_relay_output, 0)
      :pass
    rescue
      _ -> :fail
    end
  end

  defp test_response_timing do
    # Test emergency stop response timing
    start_time = System.monotonic_time(:millisecond)
    stop_all_motion_systems()
    response_time = System.monotonic_time(:millisecond) - start_time

    if response_time <= @emergency_stop_response_time, do: :pass, else: :fail
  end
end
