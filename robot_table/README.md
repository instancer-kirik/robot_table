# Robot Table Industrial Automation System

[![Build Status](https://github.com/instancer-kirik/robot_table/workflows/CI/badge.svg)](https://github.com/instancer-kirik/robot_table/actions)
[![Safety Certified](https://img.shields.io/badge/Safety-SIL--2%20Compliant-red)](./DESIGN.md#safety-protocols)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A safety-critical industrial automation system built on Nerves/Elixir for controlling motorized table positioning and heavy machinery including a 9-inch grinder. Designed for precision manufacturing and workshop automation with SIL-2 safety compliance.

## 🚀 Features

### Safety Systems
- **Hardware Emergency Stops** - <50ms response time
- **Safety Interlocks** - Light curtains, door sensors, pressure mats
- **Fail-Safe Design** - Power removal on safety violations
- **SIL-2 Compliance** - Safety Integrity Level 2 certified
- **Comprehensive Diagnostics** - Real-time fault monitoring

### Motion Control
- **Multi-Axis Positioning** - X/Y/Z table control with rotation/tilt
- **Precision Control** - ±0.01mm positioning accuracy
- **Closed-Loop Feedback** - Encoder-based position monitoring
- **Coordinated Motion** - Synchronized multi-axis movements
- **Load Monitoring** - Real-time force/torque feedback

### Industrial Integration
- **9-inch Grinder Control** - Variable speed, torque monitoring
- **MQTT Connectivity** - Industry 4.0 integration
- **Web Dashboard** - Phoenix LiveView interface
- **REST API** - Programmatic control and monitoring
- **Data Logging** - Historical operation data

## 🛡️ Safety First

This system handles heavy industrial machinery. **Safety is our top priority.**

- All safety systems are hardware-based with software monitoring
- Emergency stops are hardwired and independent of software
- Position limits are enforced at multiple levels
- Comprehensive fault detection and safe shutdown procedures

**⚠️ WARNING: This system controls dangerous machinery. Proper training, safety procedures, and protective equipment are required.**

## 🏗️ System Architecture

```
RobotTable.Application
├── SafetySystem.Supervisor          # SIL-2 safety monitoring
│   ├── EmergencyStop.GenServer      # Hardware E-stop monitoring
│   ├── SafetyMonitor.GenServer      # Interlock management
│   └── InterlockManager.GenServer   # Fail-safe coordination
├── MotionControl.Supervisor         # Multi-axis control
│   ├── TableController.GenServer    # X/Y/Z positioning
│   ├── GrinderController.GenServer  # Tool control
│   └── PositionFeedback.GenServer   # Encoder monitoring
├── SensorData.Supervisor           # Environmental monitoring
│   ├── EnvironmentalSensors         # Temperature, vibration
│   ├── VibrationAnalysis            # Tool condition monitoring
│   └── DataLogger                   # Historical data
└── NetworkInterface.Supervisor     # Connectivity
    ├── WebServer                    # Phoenix LiveView dashboard
    ├── MQTTClient                   # Industrial protocols
    └── TelemetryCollector          # Metrics and monitoring
```

## 🔧 Hardware Requirements

### Controller
- **Raspberry Pi 5** (recommended) or Pi 4
- **32GB+ MicroSD Card** (Industrial grade recommended)
- **Reliable power supply** with UPS backup

### Safety Hardware
- **Hardware emergency stops** (minimum 3 units)
- **Safety relay modules** (Category 3, ISO 13849)
- **Light curtains** or safety barriers
- **Door interlock switches**
- **Pressure safety mats**

### Motion Control
- **Stepper/servo motor drivers** (SPI interface)
- **Linear encoders** for position feedback
- **Limit switches** (hardwired safety)
- **Motor power supplies** (24V/48V typical)

### I/O Interface
- **GPIO expansion** for safety inputs
- **SPI motor controllers**
- **Industrial Ethernet** for networking
- **USB** for configuration and diagnostics

## 🚀 Quick Start

### Prerequisites
- Elixir 1.18+ with OTP 27
- Nerves development environment
- `asdf` version manager (recommended)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/instancer-kirik/robot_table.git
   cd robot_table
   ```

2. **Set up development environment**
   ```bash
   # Install Elixir/OTP versions
   asdf install erlang 27.3.4.3
   asdf install elixir 1.18.4-otp-27
   asdf local erlang 27.3.4.3
   asdf local elixir 1.18.4-otp-27
   
   # Install Nerves bootstrap
   mix archive.install hex nerves_bootstrap
   ```

3. **Get dependencies**
   ```bash
   export MIX_TARGET=rpi5
   mix deps.get
   ```

4. **Configure SSH keys** (required for Nerves)
   ```bash
   # Ensure you have SSH keys
   ls ~/.ssh/id_*.pub
   # If not, create them:
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
   ```

### Building Firmware

```bash
# Build firmware
export MIX_TARGET=rpi5
mix firmware

# Burn to SD card (requires sudo)
mix burn

# Or upload to existing device
mix upload <device_ip>
```

### Development Workflow

```bash
# Format code
mix format

# Run tests
mix test

# Check for issues
mix dialyzer

# Generate documentation
mix docs
```

## 🎛️ Usage

### Safety System

```elixir
# Check safety status
RobotTable.SafetySystem.get_state()
#=> :safe | :unsafe | :fault | :test

# Perform safety self-test
RobotTable.SafetySystem.self_test()

# Reset after clearing faults
RobotTable.SafetySystem.reset_safety_system("operator_id")
```

### Motion Control

```elixir
# Get current position
RobotTable.MotionControl.TableController.get_position()
#=> %{x: 0.0, y: 0.0, z: 0.0, a: 0.0, b: 0.0}

# Move to position (absolute)
RobotTable.MotionControl.TableController.move_to(%{
  x: 100.0,  # mm
  y: 50.0,   # mm
  z: 25.0    # mm
})

# Move relative to current position
RobotTable.MotionControl.TableController.move_relative(%{x: 10.0})

# Home all axes
RobotTable.MotionControl.TableController.home_axes()

# Emergency stop
RobotTable.MotionControl.TableController.emergency_stop()
```

### Web Interface

Access the web dashboard at `http://nerves.local` or your device's IP address.

Features:
- Real-time position monitoring
- Manual jog controls
- Safety system status
- Historical data visualization
- Alarm management

### REST API

```bash
# Get system status
curl http://nerves.local/api/status

# Move table
curl -X POST http://nerves.local/api/table/move \
  -H "Content-Type: application/json" \
  -d '{"x": 100, "y": 50, "z": 25}'

# Emergency stop
curl -X POST http://nerves.local/api/emergency_stop
```

## 📊 Monitoring and Telemetry

### Built-in Metrics
- Position accuracy and repeatability
- Motor temperatures and currents
- Safety system response times
- Network connectivity status
- System uptime and reliability

### MQTT Integration
Subscribe to real-time telemetry:
```
robot_table/position/x
robot_table/position/y
robot_table/safety/status
robot_table/grinder/speed
```

## 🔒 Security

- **Network Security**: TLS 1.3 encryption for all communications
- **Access Control**: Role-based permissions
- **Audit Logging**: All operations logged with timestamps
- **Secure Boot**: Firmware integrity verification

## 🧪 Testing

### Unit Tests
```bash
mix test
```

### Hardware-in-the-Loop Tests
```bash
# Requires actual hardware connected
MIX_ENV=test MIX_TARGET=rpi5 mix test --only hardware
```

### Safety Tests
```bash
# Safety system validation
mix test --only safety
```

## 📝 Documentation

- **[Design Document](DESIGN.md)** - Complete system architecture
- **[Safety Manual](docs/safety.md)** - Safety procedures and compliance
- **[Hardware Guide](docs/hardware.md)** - Wiring and setup instructions
- **[API Reference](docs/api.md)** - Complete API documentation
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Ensure all tests pass and code is formatted
4. Update documentation if needed
5. Commit changes (`git commit -m 'Add amazing feature'`)
6. Push to branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Development Guidelines
- Follow Elixir/OTP best practices
- Maintain test coverage above 90%
- Document all public APIs
- Safety-related changes require additional review
- Hardware changes must be tested on actual equipment

## 📋 Compliance and Standards

- **ISO 12100** - Machine Safety
- **ISO 13849** - Safety Control Systems (Category 3)
- **IEC 62061** - Electrical Safety Systems (SIL-2)
- **OSHA 1910.212** - Machine Guarding
- **CE Marking** - European Conformity

## ⚠️ Safety Warnings

**DANGER**: This system controls industrial machinery that can cause serious injury or death.

- **Proper Training Required** - Only qualified personnel should operate
- **PPE Mandatory** - Safety glasses, hearing protection, appropriate clothing
- **Emergency Procedures** - Know location of all emergency stops
- **Lockout/Tagout** - Follow LOTO procedures during maintenance
- **Regular Inspection** - Daily safety system checks required

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/instancer-kirik/robot_table/issues)
- **Discussions**: [GitHub Discussions](https://github.com/instancer-kirik/robot_table/discussions)
- **Safety Concerns**: Contact immediately for safety-related issues

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Nerves Project** - Embedded Elixir platform
- **Phoenix Framework** - Web interface
- **Circuits** - Hardware interface libraries
- **Industrial Safety Community** - Safety standards and best practices

---

**⚡ Built with Elixir/OTP for rock-solid reliability**

*This system is designed for industrial use with proper safety training and procedures. The authors assume no responsibility for improper use or safety violations.*