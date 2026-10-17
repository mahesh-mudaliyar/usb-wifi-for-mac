#!/bin/bash
# Checks whether this Mac's own Wi-Fi works, and which USB Wi-Fi dongle is plugged in and whether
# Linux (Alpine) has a driver for it. If you changed dongles, this hands the new one to Alpine.
S="$(cd "$(dirname "$0")" && pwd)/setup/check-wifi.sh"
[ -f "$S" ] || S="$HOME/Library/Application Support/Mac Wi-Fi/setup/check-wifi.sh"
if [ -f "$S" ]; then bash "$S"; else echo "Can't find setup/check-wifi.sh. Keep this file next to its 'setup' folder."; fi
echo
read -r -p "Press Return to close." _
