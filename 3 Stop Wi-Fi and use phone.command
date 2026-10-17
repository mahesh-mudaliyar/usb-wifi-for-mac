#!/bin/bash
# Turns Wi-Fi off and moves the Mac to phone USB tethering.
# Waits for the Mac to be on the phone BEFORE shutting Alpine down, so there's no gap.
V="$HOME/Virtual Machines.localized/Alpine WiFi.vmwarevm"
START=$(date +%s)
t()  { printf "[%3ss] " $(( $(date +%s) - START )); }
gw() { route -n get default 2>/dev/null | awk '/gateway/{print $2}'; }

echo "=== Switching from Wi-Fi to phone USB ==="
if ! "$HOME/.cargo/bin/muta" status 2>/dev/null | grep -q connected; then
  t; echo "PROBLEM: the phone isn't connected. Plug it in and turn on USB tethering first,"
  echo "        otherwise the Mac would have no internet. Nothing was changed."
  read -r -p "Press Return to close." _; exit 1
fi
t; echo "OK    Phone USB tethering is connected"

touch "$HOME/.alpinewifi-disabled"
t; echo "OK    Wi-Fi turned OFF (stays off until you use shortcut 5 or 1)"

t; echo "...   Waiting for the Mac to move to the phone (checks every 15 s)..."
for _ in $(seq 1 20); do [ "$(gw)" != 192.168.235.100 ] && [ -n "$(gw)" ] && break; sleep 3; done
if [ "$(gw)" = 192.168.235.100 ] || [ -z "$(gw)" ]; then
  t; echo "PROBLEM: the Mac didn't move to the phone. Alpine was left running so you stay online."
  echo "        Run \"0 Which internet am I on\" and tell Claude what it says."
  read -r -p "Press Return to close." _; exit 1
fi
t; echo "OK    Mac is on phone USB"

ssh -n -F "$V/sshcfg" -o ConnectTimeout=4 alp poweroff 2>/dev/null
t; echo "OK    Alpine Wi-Fi machine shut down"
if curl -s -o /dev/null --max-time 8 https://www.apple.com; then t; echo "OK    Internet working"; else t; echo "...   Internet test failed - try again in a few seconds"; fi
echo
echo "=== On phone USB. Use shortcut 5 to go back to Wi-Fi. ==="
read -r -p "Press Return to close." _
