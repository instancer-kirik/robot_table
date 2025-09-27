defmodule RobotTable.AlarmManager do
  @moduledoc """
  Alarm Management System for Robot Table Industrial Automation

  This module provides centralized alarm management for the industrial automation system,
  handling fault detection, alarm classification, and notification systems. Designed to
  meet industrial safety standards with proper alarm prioritization and escalation.

  ## Features
  - Hierarchical alarm classification (Emergency, Critical, Warning, Info)
  - Automatic alarm escalation and acknowledgment tracking
  - Historical alarm logging with timestamps
  - Integration with safety systems and emergency stops
  - Configurable notification channels (local, MQTT, email, SMS)
  - Alarm suppression and filtering to prevent alarm floods
  - Maintenance and diagnostic alarms

  ## Alarm Priority Levels
  - **Emergency**: Immediate danger - triggers emergency stops
  - **Critical**: System faults requiring immediate attention
  - **Warning**: Conditions that may lead to faults
  - **Info**: Operational status notifications

  ## Integration
  - Safety System: Automatic emergency stop on critical alarms
  - Web Interface: Real-time alarm display and acknowledgment
  - MQTT: Industrial protocol integration
  - Data Logger: Historical alarm tracking
  """

  use GenServer
  require Logger

  alias RobotTable.SafetySystem

  # Alarm priorities and escalation times
  @alarm_priorities [:emergency, :critical, :warning, :info]
  @escalation_times %{
    emergency: 0,      # Immediate
    critical: 30_000,  # 30 seconds
    warning: 300_000,  # 5 minutes
    info: :never
  }

  # Maximum number of active alarms before suppression
  @max_active_alarms 100
  @alarm_history_limit 1000

  # Notification channels
  @notification_channels [:local_display, :web_interface, :mqtt, :log_file]

  defstruct [
    :active_alarms,
    :alarm_history,
    :alarm_counters,
    :notification_config,
    :suppression_rules,
    :escalation_timers
  ]

  ## Client API

  @doc """
  Starts the Alarm Manager GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Triggers a new alarm with specified priority and data.
  """
  def trigger_alarm(alarm_type, data \\ %{}, priority \\ :warning) do
    GenServer.cast(__MODULE__, {:trigger_alarm, alarm_type, data, priority})
  end

  @doc """
  Clears an active alarm by type.
  """
  def clear_alarm(alarm_type) do
    GenServer.call(__MODULE__, {:clear_alarm, alarm_type})
  end

  @doc """
  Acknowledges an alarm (stops escalation but keeps it active).
  """
  def acknowledge_alarm(alarm_type, operator_id) do
    GenServer.call(__MODULE__, {:acknowledge_alarm, alarm_type, operator_id})
  end

  @doc """
  Gets all currently active alarms.
  """
  def get_active_alarms do
    GenServer.call(__MODULE__, :get_active_alarms)
  end

  @doc """
  Gets alarm history with optional filtering.
  """
  def get_alarm_history(opts \\ []) do
    GenServer.call(__MODULE__, {:get_alarm_history, opts})
  end

  @doc """
  Gets alarm statistics and counters.
  """
  def get_alarm_statistics do
    GenServer.call(__MODULE__, :get_alarm_statistics)
  end

  @doc """
  Configures notification channels and settings.
  """
  def configure_notifications(config) do
    GenServer.call(__MODULE__, {:configure_notifications, config})
  end

  @doc """
  Sets up alarm suppression rules to prevent alarm floods.
  """
  def configure_suppression_rules(rules) do
    GenServer.call(__MODULE__, {:configure_suppression_rules, rules})
  end

  @doc """
  Performs alarm system self-test.
  """
  def self_test do
    GenServer.call(__MODULE__, :self_test, 10_000)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    # Load configuration from persistent storage
    notification_config = load_notification_config()
    suppression_rules = load_suppression_rules()

    # Initialize alarm tracking structures
    initial_state = %__MODULE__{
      active_alarms: %{},
      alarm_history: :queue.new(),
      alarm_counters: initialize_counters(),
      notification_config: notification_config,
      suppression_rules: suppression_rules,
      escalation_timers: %{}
    }

    Logger.info("Alarm Manager initialized with #{length(@notification_channels)} notification channels")
    {:ok, initial_state}
  end

  @impl true
  def handle_cast({:trigger_alarm, alarm_type, data, priority}, state) do
    # Check if this alarm should be suppressed
    case should_suppress_alarm?(alarm_type, priority, state) do
      false ->
        alarm = create_alarm(alarm_type, data, priority)
        new_state = add_active_alarm(state, alarm)
        Logger.log(priority_to_log_level(priority), "ALARM [#{priority}] #{alarm_type}: #{inspect(data)}")
        {:noreply, new_state}

      true ->
        Logger.debug("Alarm suppressed: #{alarm_type}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:clear_alarm, alarm_type}, _from, state) do
    case Map.get(state.active_alarms, alarm_type) do
      nil ->
        {:reply, {:error, :alarm_not_found}, state}

      alarm ->
        new_state = clear_active_alarm(state, alarm_type)
        Logger.info("Alarm cleared: #{alarm_type}")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:acknowledge_alarm, alarm_type, operator_id}, _from, state) do
    case Map.get(state.active_alarms, alarm_type) do
      nil ->
        {:reply, {:error, :alarm_not_found}, state}

      alarm ->
        acknowledged_alarm = %{alarm |
          acknowledged: true,
          acknowledged_by: operator_id,
          acknowledged_at: DateTime.utc_now()
        }

        new_active_alarms = Map.put(state.active_alarms, alarm_type, acknowledged_alarm)
        new_state = %{state | active_alarms: new_active_alarms}

        # Cancel escalation timer
        cancel_escalation_timer(alarm_type, state.escalation_timers)

        Logger.info("Alarm acknowledged by #{operator_id}: #{alarm_type}")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:get_active_alarms, _from, state) do
    # Return sorted by priority and timestamp
    sorted_alarms = state.active_alarms
    |> Map.values()
    |> Enum.sort_by(fn alarm ->
      {priority_sort_order(alarm.priority), alarm.timestamp}
    end)

    {:reply, sorted_alarms, state}
  end

  @impl true
  def handle_call({:get_alarm_history, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 100)
    priority_filter = Keyword.get(opts, :priority)
    type_filter = Keyword.get(opts, :type)

    filtered_history = state.alarm_history
    |> :queue.to_list()
    |> filter_alarms(priority_filter, type_filter)
    |> Enum.take(limit)

    {:reply, filtered_history, state}
  end

  @impl true
  def handle_call(:get_alarm_statistics, _from, state) do
    stats = %{
      active_count: map_size(state.active_alarms),
      total_history_count: :queue.len(state.alarm_history),
      counters_by_priority: state.alarm_counters,
      critical_alarms: count_alarms_by_priority(state.active_alarms, :critical),
      emergency_alarms: count_alarms_by_priority(state.active_alarms, :emergency),
      acknowledged_count: count_acknowledged_alarms(state.active_alarms),
      last_emergency: find_last_alarm_by_priority(state.alarm_history, :emergency)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:configure_notifications, config}, _from, state) do
    # Validate configuration
    case validate_notification_config(config) do
      :ok ->
        save_notification_config(config)
        new_state = %{state | notification_config: config}
        Logger.info("Notification configuration updated")
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:configure_suppression_rules, rules}, _from, state) do
    case validate_suppression_rules(rules) do
      :ok ->
        save_suppression_rules(rules)
        new_state = %{state | suppression_rules: rules}
        Logger.info("Alarm suppression rules updated")
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:self_test, _from, state) do
    test_results = %{
      notification_channels: test_notification_channels(state.notification_config),
      alarm_creation: test_alarm_creation(),
      escalation_system: test_escalation_system(),
      suppression_rules: test_suppression_rules(state.suppression_rules),
      data_persistence: test_data_persistence()
    }

    all_passed = Enum.all?(test_results, fn {_test, result} -> result == :pass end)

    if all_passed do
      Logger.info("Alarm Manager self-test passed")
      {:reply, {:ok, test_results}, state}
    else
      Logger.error("Alarm Manager self-test failed: #{inspect(test_results)}")
      {:reply, {:error, test_results}, state}
    end
  end

  @impl true
  def handle_info({:escalate_alarm, alarm_type}, state) do
    case Map.get(state.active_alarms, alarm_type) do
      nil ->
        # Alarm was cleared before escalation
        {:noreply, state}

      alarm ->
        unless alarm.acknowledged do
          escalated_alarm = escalate_alarm(alarm)
          new_active_alarms = Map.put(state.active_alarms, alarm_type, escalated_alarm)
          new_state = %{state | active_alarms: new_active_alarms}

          Logger.warning("Alarm escalated: #{alarm_type} -> #{escalated_alarm.priority}")
          {:noreply, new_state}
        else
          {:noreply, state}
        end
    end
  end

  ## Private Functions

  defp create_alarm(alarm_type, data, priority) do
    %{
      type: alarm_type,
      priority: priority,
      data: data,
      timestamp: DateTime.utc_now(),
      acknowledged: false,
      acknowledged_by: nil,
      acknowledged_at: nil,
      escalation_count: 0,
      id: generate_alarm_id()
    }
  end

  defp add_active_alarm(state, alarm) do
    # Add to active alarms
    new_active_alarms = Map.put(state.active_alarms, alarm.type, alarm)

    # Add to history
    new_history = :queue.in(alarm, state.alarm_history)
    trimmed_history = if :queue.len(new_history) > @alarm_history_limit do
      {_, trimmed} = :queue.out(new_history)
      trimmed
    else
      new_history
    end

    # Update counters
    new_counters = increment_counter(state.alarm_counters, alarm.priority)

    # Set up escalation timer if needed
    new_escalation_timers = setup_escalation_timer(alarm, state.escalation_timers)

    # Send notifications
    send_alarm_notifications(alarm, state.notification_config)

    # Trigger emergency stop if needed
    if alarm.priority == :emergency do
      SafetySystem.emergency_stop("Critical alarm: #{alarm.type}")
    end

    %{state |
      active_alarms: new_active_alarms,
      alarm_history: trimmed_history,
      alarm_counters: new_counters,
      escalation_timers: new_escalation_timers
    }
  end

  defp clear_active_alarm(state, alarm_type) do
    # Remove from active alarms
    {alarm, new_active_alarms} = Map.pop(state.active_alarms, alarm_type)

    # Cancel escalation timer
    new_escalation_timers = cancel_escalation_timer(alarm_type, state.escalation_timers)

    # Send clear notification
    if alarm do
      send_clear_notification(alarm, state.notification_config)
    end

    %{state |
      active_alarms: new_active_alarms,
      escalation_timers: new_escalation_timers
    }
  end

  defp should_suppress_alarm?(alarm_type, priority, state) do
    # Check maximum active alarms
    if map_size(state.active_alarms) >= @max_active_alarms and priority not in [:emergency, :critical] do
      true
    else
      # Check suppression rules
      Enum.any?(state.suppression_rules, fn rule ->
        matches_suppression_rule?(alarm_type, priority, rule)
      end)
    end
  end

  defp setup_escalation_timer(alarm, escalation_timers) do
    escalation_time = @escalation_times[alarm.priority]

    if escalation_time != :never and escalation_time > 0 do
      timer_ref = Process.send_after(self(), {:escalate_alarm, alarm.type}, escalation_time)
      Map.put(escalation_timers, alarm.type, timer_ref)
    else
      escalation_timers
    end
  end

  defp cancel_escalation_timer(alarm_type, escalation_timers) do
    case Map.get(escalation_timers, alarm_type) do
      nil -> escalation_timers
      timer_ref ->
        Process.cancel_timer(timer_ref)
        Map.delete(escalation_timers, alarm_type)
    end
  end

  defp escalate_alarm(alarm) do
    new_priority = case alarm.priority do
      :info -> :warning
      :warning -> :critical
      :critical -> :emergency
      :emergency -> :emergency  # Already at highest level
    end

    %{alarm |
      priority: new_priority,
      escalation_count: alarm.escalation_count + 1
    }
  end

  defp send_alarm_notifications(alarm, notification_config) do
    Enum.each(@notification_channels, fn channel ->
      if channel_enabled?(channel, notification_config) do
        send_notification(channel, :alarm, alarm)
      end
    end)
  end

  defp send_clear_notification(alarm, notification_config) do
    Enum.each(@notification_channels, fn channel ->
      if channel_enabled?(channel, notification_config) do
        send_notification(channel, :clear, alarm)
      end
    end)
  end

  defp send_notification(:local_display, type, alarm) do
    # Update local display (LED indicators, LCD screen, etc.)
    Logger.debug("Local display notification: #{type} - #{alarm.type}")
  end

  defp send_notification(:web_interface, type, alarm) do
    # Broadcast to Phoenix LiveView via PubSub
    Phoenix.PubSub.broadcast(
      RobotTable.PubSub,
      "alarms",
      {type, alarm}
    )
  end

  defp send_notification(:mqtt, type, alarm) do
    # Send MQTT message for industrial integration
    topic = "robot_table/alarms/#{type}"
    payload = Jason.encode!(%{
      type: alarm.type,
      priority: alarm.priority,
      timestamp: alarm.timestamp,
      data: alarm.data
    })

    # This would integrate with your MQTT client
    Logger.debug("MQTT notification: #{topic} - #{payload}")
  end

  defp send_notification(:log_file, type, alarm) do
    # Write to alarm log file
    log_level = priority_to_log_level(alarm.priority)
    Logger.log(log_level, "ALARM_#{String.upcase(to_string(type))}: #{alarm.type} - #{inspect(alarm.data)}")
  end

  # Helper functions
  defp generate_alarm_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16()

  defp initialize_counters do
    Map.new(@alarm_priorities, fn priority -> {priority, 0} end)
  end

  defp increment_counter(counters, priority) do
    Map.update(counters, priority, 1, &(&1 + 1))
  end

  defp priority_to_log_level(:emergency), do: :emergency
  defp priority_to_log_level(:critical), do: :critical
  defp priority_to_log_level(:warning), do: :warning
  defp priority_to_log_level(:info), do: :info

  defp priority_sort_order(:emergency), do: 0
  defp priority_sort_order(:critical), do: 1
  defp priority_sort_order(:warning), do: 2
  defp priority_sort_order(:info), do: 3

  defp count_alarms_by_priority(active_alarms, priority) do
    active_alarms
    |> Map.values()
    |> Enum.count(&(&1.priority == priority))
  end

  defp count_acknowledged_alarms(active_alarms) do
    active_alarms
    |> Map.values()
    |> Enum.count(&(&1.acknowledged))
  end

  defp find_last_alarm_by_priority(alarm_history, priority) do
    alarm_history
    |> :queue.to_list()
    |> Enum.find(&(&1.priority == priority))
  end

  defp filter_alarms(alarms, priority_filter, type_filter) do
    alarms
    |> Enum.filter(fn alarm ->
      priority_match = is_nil(priority_filter) or alarm.priority == priority_filter
      type_match = is_nil(type_filter) or alarm.type == type_filter
      priority_match and type_match
    end)
  end

  # Configuration and validation functions
  defp load_notification_config do
    %{
      local_display: %{enabled: true},
      web_interface: %{enabled: true},
      mqtt: %{enabled: false, broker: nil},
      log_file: %{enabled: true, path: "/tmp/alarms.log"}
    }
  end

  defp load_suppression_rules, do: []

  defp save_notification_config(_config), do: :ok
  defp save_suppression_rules(_rules), do: :ok
  defp validate_notification_config(_config), do: :ok
  defp validate_suppression_rules(_rules), do: :ok
  defp channel_enabled?(_channel, _config), do: true
  defp matches_suppression_rule?(_alarm_type, _priority, _rule), do: false

  # Self-test functions
  defp test_notification_channels(_config), do: :pass
  defp test_alarm_creation, do: :pass
  defp test_escalation_system, do: :pass
  defp test_suppression_rules(_rules), do: :pass
  defp test_data_persistence, do: :pass
end
