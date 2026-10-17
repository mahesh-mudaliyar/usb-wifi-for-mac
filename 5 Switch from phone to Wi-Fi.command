#!/bin/bash
# Switches the Mac from phone USB tethering to Wi-Fi right away.
# First checks whether Wi-Fi was turned off (shortcut 3) and turns it back on.
FLAG="$HOME/.alpinewifi-disabled"
VR="/Applications/VMware Fusion.app/Contents/Library/vmrun"
echo "=== Switching from phone USB to Wi-Fi ==="
echo

# Where things stand
gw=$(route -n get default 2>/dev/null | awk '/gateway/{print $2}')
case "$gw" in
  192.168.235.100) now="Wi-Fi" ;;
  "")              now="no internet" ;;
  *)               now="phone USB" ;;
esac
echo "Mac is using now:  $now"

if [ -f "$FLAG" ]; then
  echo "Wi-Fi setting:     OFF (turned off with shortcut 3 on $(stat -f '%Sm' -t '%d %b at %H:%M' "$FLAG"))"
  echo "                   -> turning Wi-Fi back ON"
  rm -f "$FLAG"
else
  echo "Wi-Fi setting:     ON"
fi

if "$VR" list 2>/dev/null | grep -qxF "$HOME/Virtual Machines.localized/Alpine WiFi.vmwarevm/Alpine WiFi.vmx"; then echo "Alpine Wi-Fi:      running"; else echo "Alpine Wi-Fi:      stopped (will start it)"; fi
if "$HOME/.cargo/bin/muta" status 2>/dev/null | grep -q "connected"; then echo "Phone USB:         connected"; else echo "Phone USB:         not connected"; fi
echo

if [ "$now" = "Wi-Fi" ]; then
  echo "Already on Wi-Fi - nothing to do."
  read -r -p "Press Return to close." _; exit 0
fi

touch "$HOME/.alpinewifi-switchnow"
exec bash "$(dirname "$0")/1 Start Wi-Fi.command"
