#!/bin/sh
# Colemak keyboard layout support for Nerves systems
# This script sets up Colemak keyboard mapping for console and TTY sessions

# Set console keyboard layout to Colemak
if [ -x /usr/bin/loadkeys ]; then
    # Create Colemak keymap inline since we can't rely on external files
    cat > /tmp/colemak.map << 'EOF'
# Colemak keyboard layout for Linux console
# Based on the Colemak layout by Shai Coleman
# https://colemak.com/

keymaps 0-127
charset "iso-8859-1"

# Main Colemak remappings
keycode  16 = q            Q            q            Q
keycode  17 = w            W            w            W
keycode  18 = f            F            f            F
keycode  19 = p            P            p            P
keycode  20 = g            G            g            G
keycode  21 = j            J            j            J
keycode  22 = l            L            l            L
keycode  23 = u            U            u            U
keycode  24 = y            Y            y            Y
keycode  25 = semicolon    colon        semicolon    colon

keycode  30 = a            A            a            A
keycode  31 = r            R            r            R
keycode  32 = s            S            s            S
keycode  33 = t            T            t            T
keycode  34 = d            D            d            D
keycode  35 = h            H            h            H
keycode  36 = n            N            n            N
keycode  37 = e            E            e            E
keycode  38 = i            I            i            I
keycode  39 = o            O            o            O

keycode  44 = z            Z            z            Z
keycode  45 = x            X            x            X
keycode  46 = c            C            c            C
keycode  47 = v            V            v            V
keycode  48 = b            B            b            B
keycode  49 = k            K            k            K
keycode  50 = m            M            m            M

# Keep common punctuation in familiar places
keycode  51 = comma        less         comma        less
keycode  52 = period       greater      period       greater
keycode  53 = slash        question     slash        question
EOF

    # Load the Colemak keymap
    loadkeys /tmp/colemak.map > /dev/null 2>&1

    # Clean up
    rm -f /tmp/colemak.map

    echo "Colemak keyboard layout loaded"
fi

# For systems with setterm available, configure console
if [ -x /usr/bin/setterm ]; then
    # Set console to not blank (useful for industrial systems)
    setterm -blank 0 -powerdown 0
fi

# Export environment variable for applications that might use it
export KEYBOARD_LAYOUT=colemak
