defmodule RobotTableWeb.DashboardLive do
  @moduledoc """
  Main Industrial Dashboard for Robot Table Automation System

  This LiveView provides a comprehensive real-time dashboard for monitoring
  and controlling the industrial robot table system. Features include:
  - Real-time system status monitoring
  - Safety system indicators
  - Motion control visualization
  - Grinder status and control
  - Network connectivity status
  - Alarm notifications
  - Emergency stop controls
  """

  use RobotTableWeb, :live_view

  alias RobotTable.SafetySystem
  alias RobotTable.MotionControl.TableController
  alias RobotTable.GrinderController
  alias RobotTable.NetworkManager
  alias RobotTable.AlarmManager

  @update_interval 100  # 10Hz update rate for smooth UI

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to system events
      Phoenix.PubSub.subscribe(RobotTable.PubSub, "safety_system")
      Phoenix.PubSub.subscribe(RobotTable.PubSub, "alarms")
      Phoenix.PubSub.subscribe(RobotTable.PubSub, "motion_control")
      Phoenix.PubSub.subscribe(RobotTable.PubSub, "grinder")
      Phoenix.PubSub.subscribe(RobotTable.PubSub, "network")

      # Schedule periodic updates
      :timer.send_interval(@update_interval, self(), :update_status)
    end

    # Initialize dashboard state
    initial_state = %{
      safety_status: fetch_safety_status(),
      table_status: fetch_table_status(),
      grinder_status: fetch_grinder_status(),
      network_status: fetch_network_status(),
      active_alarms: fetch_active_alarms(),
      system_uptime: System.uptime(),
      last_update: DateTime.utc_now(),
      emergency_stop_armed: true,
      operator_mode: :monitoring,  # :monitoring, :control, :maintenance
      selected_tab: :overview
    }

    {:ok, assign(socket, initial_state)}
  end

  def handle_info(:update_status, socket) do
    updated_state = %{
      safety_status: fetch_safety_status(),
      table_status: fetch_table_status(),
      grinder_status: fetch_grinder_status(),
      network_status: fetch_network_status(),
      active_alarms: fetch_active_alarms(),
      system_uptime: System.uptime(),
      last_update: DateTime.utc_now()
    }

    {:noreply, assign(socket, updated_state)}
  end

  def handle_info({:alarm, alarm}, socket) do
    # Handle real-time alarm notifications
    updated_alarms = [alarm | socket.assigns.active_alarms] |> Enum.take(10)

    # Flash alert for critical alarms
    flash_message = case alarm.priority do
      :emergency -> {:error, "EMERGENCY: #{alarm.type}"}
      :critical -> {:error, "CRITICAL: #{alarm.type}"}
      :warning -> {:info, "Warning: #{alarm.type}"}
      _ -> nil
    end

    socket = if flash_message do
      {level, message} = flash_message
      put_flash(socket, level, message)
    else
      socket
    end

    {:noreply, assign(socket, active_alarms: updated_alarms)}
  end

  def handle_info({:clear, alarm}, socket) do
    # Handle alarm clear notifications
    updated_alarms = Enum.reject(socket.assigns.active_alarms, &(&1.type == alarm.type))
    {:noreply, assign(socket, active_alarms: updated_alarms)}
  end

  def handle_event("emergency_stop", _params, socket) do
    SafetySystem.emergency_stop("Operator initiated from dashboard")
    {:noreply, put_flash(socket, :info, "Emergency stop activated")}
  end

  def handle_event("reset_safety", _params, socket) do
    case SafetySystem.reset_safety_system("dashboard_operator") do
      :ok ->
        {:noreply, put_flash(socket, :info, "Safety system reset successful")}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Safety reset failed: #{reason}")}
    end
  end

  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, selected_tab: String.to_atom(tab))}
  end

  def handle_event("set_operator_mode", %{"mode" => mode}, socket) do
    operator_mode = String.to_atom(mode)
    {:noreply, assign(socket, operator_mode: operator_mode)}
  end

  def handle_event("acknowledge_alarm", %{"alarm_type" => alarm_type}, socket) do
    case AlarmManager.acknowledge_alarm(String.to_atom(alarm_type), "dashboard_operator") do
      :ok ->
        {:noreply, put_flash(socket, :info, "Alarm acknowledged: #{alarm_type}")}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to acknowledge alarm: #{reason}")}
    end
  end

  def handle_event("table_home", _params, socket) do
    case TableController.home_axes() do
      :ok ->
        {:noreply, put_flash(socket, :info, "Table homing initiated")}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Homing failed: #{reason}")}
    end
  end

  def handle_event("table_stop", _params, socket) do
    case TableController.stop_motion() do
      :ok ->
        {:noreply, put_flash(socket, :info, "Table motion stopped")}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Stop failed: #{reason}")}
    end
  end

  def handle_event("grinder_stop", _params, socket) do
    case GrinderController.stop_grinder() do
      :ok ->
        {:noreply, put_flash(socket, :info, "Grinder stopped")}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Grinder stop failed: #{reason}")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="industrial-dashboard" phx-hook="KeyboardShortcuts">
      <!-- Header with emergency controls -->
      <header class="dashboard-header">
        <div class="header-left">
          <h1>Robot Table Control System</h1>
          <div class="system-status">
            <div class={"status-indicator #{safety_status_class(@safety_status)}"}>
              <%= @safety_status.state |> Atom.to_string() |> String.upcase() %>
            </div>
            <div class="uptime">
              Uptime: <%= format_uptime(@system_uptime) %>
            </div>
          </div>
        </div>

        <div class="header-center">
          <!-- Tab Navigation -->
          <nav class="tab-nav">
            <button
              phx-click="change_tab"
              phx-value-tab="overview"
              class={["tab-button", @selected_tab == :overview && "active"]}
            >
              Overview
            </button>
            <button
              phx-click="change_tab"
              phx-value-tab="motion"
              class={["tab-button", @selected_tab == :motion && "active"]}
            >
              Motion
            </button>
            <button
              phx-click="change_tab"
              phx-value-tab="grinder"
              class={["tab-button", @selected_tab == :grinder && "active"]}
            >
              Grinder
            </button>
            <button
              phx-click="change_tab"
              phx-value-tab="alarms"
              class={["tab-button", @selected_tab == :alarms && "active"]}
            >
              Alarms (<%= length(@active_alarms) %>)
            </button>
          </nav>
        </div>

        <div class="header-right">
          <!-- Emergency Stop Button -->
          <button
            phx-click="emergency_stop"
            class="emergency-stop-btn"
            title="Emergency Stop (Ctrl+E)"
          >
            ⏹ EMERGENCY STOP
          </button>

          <!-- Operator Mode Selector -->
          <select phx-change="set_operator_mode" value={@operator_mode}>
            <option value="monitoring">Monitoring</option>
            <option value="control">Control</option>
            <option value="maintenance">Maintenance</option>
          </select>
        </div>
      </header>

      <!-- Main Dashboard Content -->
      <main class="dashboard-main">
        <div class="tab-content">
          <%= case @selected_tab do %>
            <% :overview -> %>
              <%= render_overview_tab(assigns) %>
            <% :motion -> %>
              <%= render_motion_tab(assigns) %>
            <% :grinder -> %>
              <%= render_grinder_tab(assigns) %>
            <% :alarms -> %>
              <%= render_alarms_tab(assigns) %>
          <% end %>
        </div>
      </main>

      <!-- Footer with status bar -->
      <footer class="dashboard-footer">
        <div class="footer-left">
          Network:
          <span class={"network-status #{@network_status.connection_state}"}>
            <%= @network_status.connection_state |> Atom.to_string() |> String.upcase() %>
          </span>
          <%= if @network_status.current_network do %>
            (<%= @network_status.current_network.ssid %>)
          <% end %>
        </div>

        <div class="footer-center">
          Last Update: <%= Calendar.strftime(@last_update, "%H:%M:%S") %>
        </div>

        <div class="footer-right">
          <%= if length(@active_alarms) > 0 do %>
            <div class="active-alarms-indicator">
              <span class="alarm-count"><%= length(@active_alarms) %></span>
              Active Alarms
            </div>
          <% end %>
        </div>
      </footer>
    </div>

    <style>
      .industrial-dashboard {
        height: 100vh;
        display: flex;
        flex-direction: column;
        background: #1a1a1a;
        color: #ffffff;
        font-family: 'Courier New', monospace;
      }

      .dashboard-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 1rem;
        background: #2d2d2d;
        border-bottom: 2px solid #ff6b35;
      }

      .status-indicator {
        padding: 0.5rem 1rem;
        border-radius: 4px;
        font-weight: bold;
        display: inline-block;
        margin-right: 1rem;
      }

      .status-safe { background: #4CAF50; color: white; }
      .status-unsafe { background: #FF5722; color: white; animation: blink 1s infinite; }
      .status-fault { background: #F44336; color: white; animation: blink 0.5s infinite; }

      @keyframes blink {
        50% { opacity: 0.5; }
      }

      .emergency-stop-btn {
        background: #d32f2f;
        color: white;
        border: 3px solid #ffebee;
        padding: 1rem 2rem;
        font-size: 1.2rem;
        font-weight: bold;
        border-radius: 8px;
        cursor: pointer;
        transition: all 0.2s;
      }

      .emergency-stop-btn:hover {
        background: #b71c1c;
        transform: scale(1.05);
      }

      .tab-nav {
        display: flex;
        gap: 0.5rem;
      }

      .tab-button {
        padding: 0.75rem 1.5rem;
        background: #404040;
        border: none;
        color: white;
        cursor: pointer;
        border-radius: 4px 4px 0 0;
      }

      .tab-button.active {
        background: #ff6b35;
      }

      .dashboard-main {
        flex: 1;
        padding: 1rem;
        overflow-y: auto;
      }

      .dashboard-footer {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 0.5rem 1rem;
        background: #2d2d2d;
        border-top: 1px solid #404040;
        font-size: 0.9rem;
      }

      .network-status.connected { color: #4CAF50; }
      .network-status.disconnected { color: #F44336; }

      .active-alarms-indicator {
        background: #ff6b35;
        padding: 0.25rem 0.75rem;
        border-radius: 16px;
        font-size: 0.8rem;
      }
    </style>
    """
  end

  defp render_overview_tab(assigns) do
    ~H"""
    <div class="overview-grid">
      <!-- Safety System Card -->
      <div class="status-card safety-card">
        <h3>Safety System</h3>
        <div class={"status-large #{safety_status_class(@safety_status)}"}>
          <%= @safety_status.state |> Atom.to_string() |> String.upcase() %>
        </div>
        <div class="status-details">
          <div>Emergency Stops: <%= format_boolean(@safety_status.emergency_stops_ok) %></div>
          <div>Interlocks: <%= format_boolean(@safety_status.interlocks_ok) %></div>
          <div>Watchdog: <%= format_boolean(@safety_status.watchdog_ok) %></div>
        </div>
        <%= if @safety_status.state != :safe do %>
          <button phx-click="reset_safety" class="reset-btn">Reset Safety</button>
        <% end %>
      </div>

      <!-- Table Position Card -->
      <div class="status-card motion-card">
        <h3>Table Position</h3>
        <div class="position-display">
          <div class="axis-reading">X: <%= format_position(@table_status.current_position.x) %> mm</div>
          <div class="axis-reading">Y: <%= format_position(@table_status.current_position.y) %> mm</div>
          <div class="axis-reading">Z: <%= format_position(@table_status.current_position.z) %> mm</div>
          <div class="axis-reading">A: <%= format_position(@table_status.current_position.a) %>°</div>
          <div class="axis-reading">B: <%= format_position(@table_status.current_position.b) %>°</div>
        </div>
        <div class="motion-state">
          State: <%= @table_status.state |> Atom.to_string() |> String.upcase() %>
        </div>
        <%= if @operator_mode in [:control, :maintenance] do %>
          <div class="control-buttons">
            <button phx-click="table_home" class="action-btn">Home All</button>
            <button phx-click="table_stop" class="stop-btn">Stop</button>
          </div>
        <% end %>
      </div>

      <!-- Grinder Status Card -->
      <div class="status-card grinder-card">
        <h3>9" Grinder</h3>
        <div class="grinder-display">
          <div class="speed-reading">
            Speed: <%= @grinder_status.actual_speed_rpm %> RPM
            <%= if @grinder_status.target_speed_rpm > 0 do %>
              (Target: <%= @grinder_status.target_speed_rpm %>)
            <% end %>
          </div>
          <div class="current-reading">
            Current: <%= format_current(@grinder_status.motor_current) %> A
          </div>
          <div class="temp-reading">
            Temp: <%= format_temperature(@grinder_status.motor_temperature) %>°C
          </div>
        </div>
        <div class="grinder-state">
          State: <%= @grinder_status.state |> Atom.to_string() |> String.upcase() %>
        </div>
        <%= if @operator_mode in [:control, :maintenance] and @grinder_status.state == :running do %>
          <button phx-click="grinder_stop" class="stop-btn">Stop Grinder</button>
        <% end %>
      </div>

      <!-- Recent Alarms Card -->
      <div class="status-card alarms-card">
        <h3>Recent Alarms</h3>
        <%= if length(@active_alarms) == 0 do %>
          <div class="no-alarms">No Active Alarms</div>
        <% else %>
          <div class="alarm-list">
            <%= for alarm <- Enum.take(@active_alarms, 3) do %>
              <div class={"alarm-item priority-#{alarm.priority}"}>
                <div class="alarm-type"><%= alarm.type %></div>
                <div class="alarm-time"><%= format_alarm_time(alarm.timestamp) %></div>
                <%= if not alarm.acknowledged do %>
                  <button
                    phx-click="acknowledge_alarm"
                    phx-value-alarm_type={alarm.type}
                    class="ack-btn"
                  >
                    ACK
                  </button>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>

    <style>
      .overview-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
        gap: 1rem;
        height: 100%;
      }

      .status-card {
        background: #2d2d2d;
        border: 1px solid #404040;
        border-radius: 8px;
        padding: 1.5rem;
        display: flex;
        flex-direction: column;
      }

      .status-card h3 {
        margin: 0 0 1rem 0;
        color: #ff6b35;
        border-bottom: 1px solid #404040;
        padding-bottom: 0.5rem;
      }

      .status-large {
        font-size: 1.5rem;
        font-weight: bold;
        padding: 1rem;
        text-align: center;
        border-radius: 4px;
        margin-bottom: 1rem;
      }

      .position-display, .grinder-display {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }

      .axis-reading, .speed-reading, .current-reading, .temp-reading {
        display: flex;
        justify-content: space-between;
        padding: 0.5rem;
        background: #1a1a1a;
        border-radius: 4px;
        font-family: monospace;
      }

      .control-buttons {
        display: flex;
        gap: 0.5rem;
        margin-top: auto;
      }

      .action-btn, .stop-btn, .reset-btn {
        flex: 1;
        padding: 0.75rem;
        border: none;
        border-radius: 4px;
        cursor: pointer;
        font-weight: bold;
      }

      .action-btn, .reset-btn {
        background: #4CAF50;
        color: white;
      }

      .stop-btn {
        background: #f44336;
        color: white;
      }

      .alarm-item {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 0.5rem;
        margin-bottom: 0.5rem;
        border-radius: 4px;
      }

      .priority-emergency { background: #f44336; }
      .priority-critical { background: #ff9800; }
      .priority-warning { background: #2196f3; }
      .priority-info { background: #4caf50; }

      .no-alarms {
        text-align: center;
        color: #4CAF50;
        font-style: italic;
        padding: 2rem;
      }
    </style>
    """
  end

  defp render_motion_tab(assigns) do
    ~H"""
    <div class="motion-control-interface">
      <p>Motion Control Interface - Coming Soon</p>
    </div>
    """
  end

  defp render_grinder_tab(assigns) do
    ~H"""
    <div class="grinder-control-interface">
      <p>Grinder Control Interface - Coming Soon</p>
    </div>
    """
  end

  defp render_alarms_tab(assigns) do
    ~H"""
    <div class="alarms-interface">
      <p>Alarms Management Interface - Coming Soon</p>
    </div>
    """
  end

  # Helper functions
  defp fetch_safety_status do
    case SafetySystem.get_state() do
      state when state in [:safe, :unsafe, :fault, :test] ->
        %{
          state: state,
          emergency_stops_ok: true,
          interlocks_ok: true,
          watchdog_ok: true
        }
      _ ->
        %{
          state: :unknown,
          emergency_stops_ok: false,
          interlocks_ok: false,
          watchdog_ok: false
        }
    end
  rescue
    _ ->
      %{
        state: :disconnected,
        emergency_stops_ok: false,
        interlocks_ok: false,
        watchdog_ok: false
      }
  end

  defp fetch_table_status do
    case TableController.get_status() do
      status when is_map(status) -> status
      _ -> %{
        state: :disconnected,
        current_position: %{x: 0.0, y: 0.0, z: 0.0, a: 0.0, b: 0.0}
      }
    end
  rescue
    _ -> %{
      state: :disconnected,
      current_position: %{x: 0.0, y: 0.0, z: 0.0, a: 0.0, b: 0.0}
    }
  end

  defp fetch_grinder_status do
    case GrinderController.get_status() do
      status when is_map(status) -> status
      _ -> %{
        state: :disconnected,
        actual_speed_rpm: 0,
        target_speed_rpm: 0,
        motor_current: 0.0,
        motor_temperature: 0.0
      }
    end
  rescue
    _ -> %{
      state: :disconnected,
      actual_speed_rpm: 0,
      target_speed_rpm: 0,
      motor_current: 0.0,
      motor_temperature: 0.0
    }
  end

  defp fetch_network_status do
    case NetworkManager.get_network_status() do
      status when is_map(status) -> status
      _ -> %{connection_state: :disconnected, current_network: nil}
    end
  rescue
    _ -> %{connection_state: :disconnected, current_network: nil}
  end

  defp fetch_active_alarms do
    case AlarmManager.get_active_alarms() do
      alarms when is_list(alarms) -> alarms
      _ -> []
    end
  rescue
    _ -> []
  end

  defp safety_status_class(%{state: :safe}), do: "status-safe"
  defp safety_status_class(%{state: :unsafe}), do: "status-unsafe"
  defp safety_status_class(%{state: :fault}), do: "status-fault"
  defp safety_status_class(_), do: "status-fault"

  defp format_uptime(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)
    "#{hours}h #{minutes}m #{secs}s"
  end

  defp format_position(pos) when is_number(pos) do
    :io_lib.format("~.2f", [pos]) |> List.to_string()
  end
  defp format_position(_), do: "-.--"

  defp format_current(current) when is_number(current) do
    :io_lib.format("~.1f", [current]) |> List.to_string()
  end
  defp format_current(_), do: "-.--"

  defp format_temperature(temp) when is_number(temp) do
    :io_lib.format("~.1f", [temp]) |> List.to_string()
  end
  defp format_temperature(_), do: "--.-"

  defp format_boolean(true), do: "✓"
  defp format_boolean(_), do: "✗"

  defp format_alarm_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end
  defp format_alarm_time(_), do: "--:--:--"
end
