#!/usr/bin/env fish

# Nerves firmware burn script for Fish shell
# This script sets up the asdf environment and burns firmware to SD card

# Add asdf to PATH and source it
set -x PATH "$HOME/.asdf/bin" $PATH
source ~/.asdf/asdf.fish

# Set the target
set -x MIX_TARGET rpi5

# Run the burn command with sudo
echo "Setting up Nerves environment for rpi5..."
echo "This will burn the firmware to your SD card."
echo "Make sure you have the correct SD card inserted!"
echo ""

# Check if firmware exists
if not test -f _build/rpi5_dev/nerves/images/robot_table.fw
    echo "Firmware not found. Building firmware first..."
    mix firmware
    if test $status -ne 0
        echo "Failed to build firmware!"
        exit 1
    end
end

# Run burn with sudo
echo "Running mix burn (will prompt for sudo password)..."
sudo -E fish -c "set -x PATH '$HOME/.asdf/bin' \$PATH; source ~/.asdf/asdf.fish; set -x MIX_TARGET rpi5; mix burn"
