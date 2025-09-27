defmodule RobotTableWeb.Layouts do
  @moduledoc """
  This module contains the layouts for the Robot Table Industrial Automation web interface.
  Provides industrial-themed layouts optimized for operator use and safety-critical operations.
  """

  use RobotTableWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the root layout with industrial theming and safety indicators.
  """
  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="[scrollbar-gutter:stable]">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <.live_title suffix=" · Robot Table">
          <%= assigns[:page_title] || "Industrial Control System" %>
        </.live_title>

        <!-- Industrial favicon -->
        <link rel="icon" type="image/svg+xml" href="/images/industrial-icon.svg" />

        <!-- Industrial color scheme -->
        <meta name="theme-color" content="#ff6b35" />

        <!-- Preload critical fonts -->
        <link rel="preload" href="/fonts/roboto-mono.woff2" as="font" type="font/woff2" crossorigin />

        <!-- Industrial CSS framework -->
        <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />

        <!-- Real-time updates -->
        <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}>
        </script>

        <style>
          /* Industrial dark theme */
          :root {
            --industrial-primary: #ff6b35;
            --industrial-secondary: #2d2d2d;
            --industrial-background: #1a1a1a;
            --industrial-surface: #2d2d2d;
            --industrial-text: #ffffff;
            --industrial-text-secondary: #cccccc;
            --industrial-success: #4caf50;
            --industrial-warning: #ff9800;
            --industrial-error: #f44336;
            --industrial-critical: #d32f2f;
          }

          * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
          }

          html, body {
            height: 100%;
            font-family: 'Roboto Mono', 'Courier New', monospace;
            background-color: var(--industrial-background);
            color: var(--industrial-text);
            line-height: 1.4;
          }

          /* Disable text selection for industrial interface */
          .no-select {
            user-select: none;
            -webkit-user-select: none;
            -moz-user-select: none;
            -ms-user-select: none;
          }

          /* High contrast mode support */
          @media (prefers-contrast: high) {
            :root {
              --industrial-primary: #ffffff;
              --industrial-background: #000000;
              --industrial-surface: #333333;
            }
          }

          /* Keyboard navigation focus styles */
          button:focus,
          input:focus,
          select:focus {
            outline: 2px solid var(--industrial-primary);
            outline-offset: 2px;
          }

          /* Emergency button styles */
          .emergency-control {
            border: 3px solid var(--industrial-critical) !important;
            background: var(--industrial-critical) !important;
            animation: pulse-emergency 2s infinite;
          }

          @keyframes pulse-emergency {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.7; }
          }
        </style>
      </head>

      <body class="no-select">
        <!-- Emergency status bar -->
        <div id="emergency-status" class="emergency-status-hidden" phx-hook="EmergencyStatus">
          <div class="emergency-message">
            ⚠️ EMERGENCY STOP ACTIVE - ALL SYSTEMS HALTED
          </div>
        </div>

        <!-- Main application container -->
        <%= @inner_content %>

        <!-- Industrial system notifications -->
        <div id="system-notifications" phx-hook="SystemNotifications" class="system-notifications">
        </div>

        <!-- Keyboard shortcuts help -->
        <div id="shortcuts-help" class="shortcuts-help hidden">
          <div class="shortcuts-content">
            <h3>Keyboard Shortcuts (Colemak Optimized)</h3>
            <div class="shortcuts-grid">
              <div class="shortcut-item">
                <kbd>Ctrl + E</kbd>
                <span>Emergency Stop</span>
              </div>
              <div class="shortcut-item">
                <kbd>Ctrl + R</kbd>
                <span>Reset Safety</span>
              </div>
              <div class="shortcut-item">
                <kbd>Ctrl + H</kbd>
                <span>Home All Axes</span>
              </div>
              <div class="shortcut-item">
                <kbd>Ctrl + S</kbd>
                <span>Stop Motion</span>
              </div>
              <div class="shortcut-item">
                <kbd>F1</kbd>
                <span>Toggle This Help</span>
              </div>
              <div class="shortcut-item">
                <kbd>F5</kbd>
                <span>Refresh Dashboard</span>
              </div>
            </div>
            <button onclick="toggleShortcutsHelp()" class="close-shortcuts">Close</button>
          </div>
        </div>

        <style>
          .emergency-status-hidden {
            display: none;
          }

          .emergency-status-active {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            z-index: 9999;
            background: var(--industrial-critical);
            color: white;
            text-align: center;
            padding: 1rem;
            font-weight: bold;
            font-size: 1.2rem;
            animation: blink 1s infinite;
          }

          @keyframes blink {
            50% { opacity: 0.5; }
          }

          .system-notifications {
            position: fixed;
            top: 20px;
            right: 20px;
            z-index: 1000;
            max-width: 400px;
          }

          .notification {
            background: var(--industrial-surface);
            border: 1px solid var(--industrial-primary);
            border-radius: 4px;
            padding: 1rem;
            margin-bottom: 0.5rem;
            box-shadow: 0 4px 8px rgba(0,0,0,0.3);
            animation: slideIn 0.3s ease-out;
          }

          .notification.success {
            border-left: 4px solid var(--industrial-success);
          }

          .notification.warning {
            border-left: 4px solid var(--industrial-warning);
          }

          .notification.error {
            border-left: 4px solid var(--industrial-error);
          }

          @keyframes slideIn {
            from {
              transform: translateX(100%);
              opacity: 0;
            }
            to {
              transform: translateX(0);
              opacity: 1;
            }
          }

          .shortcuts-help {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0, 0, 0, 0.8);
            z-index: 2000;
            display: flex;
            align-items: center;
            justify-content: center;
          }

          .shortcuts-help.hidden {
            display: none;
          }

          .shortcuts-content {
            background: var(--industrial-surface);
            padding: 2rem;
            border-radius: 8px;
            border: 2px solid var(--industrial-primary);
            max-width: 600px;
            width: 90%;
          }

          .shortcuts-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
            margin: 1rem 0;
          }

          .shortcut-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 0.5rem;
            background: var(--industrial-background);
            border-radius: 4px;
          }

          kbd {
            background: var(--industrial-primary);
            color: white;
            padding: 0.25rem 0.5rem;
            border-radius: 3px;
            font-family: inherit;
            font-size: 0.85em;
          }

          .close-shortcuts {
            background: var(--industrial-primary);
            color: white;
            border: none;
            padding: 0.75rem 1.5rem;
            border-radius: 4px;
            cursor: pointer;
            font-family: inherit;
            margin-top: 1rem;
          }
        </style>

        <script>
          function toggleShortcutsHelp() {
            const help = document.getElementById('shortcuts-help');
            help.classList.toggle('hidden');
          }

          // Global keyboard shortcuts
          document.addEventListener('keydown', function(event) {
            // F1 - Toggle shortcuts help
            if (event.key === 'F1') {
              event.preventDefault();
              toggleShortcutsHelp();
            }

            // Ctrl+E - Emergency stop
            if (event.ctrlKey && event.key === 'e') {
              event.preventDefault();
              const emergencyBtn = document.querySelector('.emergency-stop-btn');
              if (emergencyBtn) emergencyBtn.click();
            }

            // Escape - Close dialogs
            if (event.key === 'Escape') {
              const help = document.getElementById('shortcuts-help');
              if (!help.classList.contains('hidden')) {
                help.classList.add('hidden');
              }
            }
          });
        </script>
      </body>
    </html>
    """
  end

  @doc """
  Renders the main application layout with industrial navigation and status indicators.
  """
  def app(assigns) do
    ~H"""
    <div class="app-layout">
      <!-- System status header -->
      <div class="system-header">
        <div class="system-info">
          <span class="system-title">Robot Table Control</span>
          <span class="system-mode">Industrial Mode</span>
        </div>

        <div class="system-indicators">
          <div class="indicator safety" title="Safety System Status">
            <span class="indicator-light"></span>
            <span class="indicator-label">SAFETY</span>
          </div>
          <div class="indicator network" title="Network Status">
            <span class="indicator-light"></span>
            <span class="indicator-label">NETWORK</span>
          </div>
          <div class="indicator power" title="Power Status">
            <span class="indicator-light"></span>
            <span class="indicator-label">POWER</span>
          </div>
        </div>
      </div>

      <!-- Main content area -->
      <main class="main-content">
        <.flash_group flash={@flash} />
        <%= @inner_content %>
      </main>
    </div>

    <style>
      .app-layout {
        display: flex;
        flex-direction: column;
        height: 100vh;
      }

      .system-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 0.5rem 1rem;
        background: var(--industrial-secondary);
        border-bottom: 2px solid var(--industrial-primary);
        min-height: 60px;
      }

      .system-info {
        display: flex;
        flex-direction: column;
      }

      .system-title {
        font-size: 1.2rem;
        font-weight: bold;
        color: var(--industrial-primary);
      }

      .system-mode {
        font-size: 0.8rem;
        color: var(--industrial-text-secondary);
      }

      .system-indicators {
        display: flex;
        gap: 1rem;
      }

      .indicator {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.25rem;
      }

      .indicator-light {
        width: 12px;
        height: 12px;
        border-radius: 50%;
        background: var(--industrial-error);
        animation: pulse 2s infinite;
      }

      .indicator.online .indicator-light {
        background: var(--industrial-success);
        animation: none;
      }

      .indicator-label {
        font-size: 0.7rem;
        color: var(--industrial-text-secondary);
      }

      @keyframes pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.3; }
      }

      .main-content {
        flex: 1;
        overflow: auto;
      }
    </style>
    """
  end

  @doc """
  Renders flash messages with industrial styling.
  """
  def flash_group(assigns) do
    ~H"""
    <div class="flash-group" phx-hook="FlashMessages">
      <.flash kind={:info} title="Info" flash={@flash} />
      <.flash kind={:error} title="Error" flash={@flash} />
    </div>
    """
  end

  @doc """
  Renders individual flash messages.
  """
  def flash(assigns) do
    ~H"""
    <div
      :if={msg = live_flash(@flash, @kind)}
      id={"flash-#{@kind}"}
      class={["flash-message", "flash-#{@kind}"]}
      phx-click="lv:clear-flash"
      phx-value-key={@kind}
      phx-hook="AutoDismiss"
      role="alert"
    >
      <div class="flash-content">
        <div class="flash-title"><%= @title %></div>
        <div class="flash-text"><%= msg %></div>
      </div>
      <button type="button" class="flash-close" aria-label="close">
        ×
      </button>
    </div>

    <style>
      .flash-group {
        position: fixed;
        top: 80px;
        right: 20px;
        z-index: 1000;
        max-width: 400px;
      }

      .flash-message {
        display: flex;
        align-items: flex-start;
        background: var(--industrial-surface);
        border: 1px solid;
        border-radius: 4px;
        padding: 1rem;
        margin-bottom: 0.5rem;
        box-shadow: 0 4px 8px rgba(0,0,0,0.3);
        animation: slideIn 0.3s ease-out;
        cursor: pointer;
      }

      .flash-info {
        border-color: var(--industrial-primary);
        background: rgba(255, 107, 53, 0.1);
      }

      .flash-error {
        border-color: var(--industrial-error);
        background: rgba(244, 67, 54, 0.1);
      }

      .flash-content {
        flex: 1;
      }

      .flash-title {
        font-weight: bold;
        margin-bottom: 0.25rem;
        color: var(--industrial-primary);
      }

      .flash-text {
        font-size: 0.9rem;
        line-height: 1.4;
      }

      .flash-close {
        background: none;
        border: none;
        color: var(--industrial-text-secondary);
        font-size: 1.5rem;
        cursor: pointer;
        padding: 0;
        margin-left: 1rem;
        line-height: 1;
      }

      .flash-close:hover {
        color: var(--industrial-text);
      }
    </style>
    """
  end
end
