#!/bin/bash
# Shuts down Alpine Wi-Fi. The Mac falls back to phone USB tethering by itself.
V="$HOME/Virtual Machines.localized/Alpine WiFi.vmwarevm"
touch "$HOME/.alpinewifi-disabled"
ssh -n -F "$V/sshcfg" -o ConnectTimeout=3 alp poweroff 2>/dev/null
echo "Alpine Wi-Fi stopped. Plug in the phone and turn on USB tethering."
echo "Waiting for the Mac to switch (up to 60 s)..."
for _ in $(seq 1 20); do route -n get default 2>/dev/null | awk '/interface/{print $2}' | grep -q utun && break; sleep 3; done
echo "Main connection: $(route -n get default 2>/dev/null | awk '/interface/{print $2}')  (utun = phone USB)"
echo "To turn Wi-Fi back on, use shortcut 1."
read -r -p "Press Return to close." _
