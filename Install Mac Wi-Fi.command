#!/bin/bash
# Double-click to install or repair Mac Wi-Fi (USB Wi-Fi adapter via Alpine + phone USB backup).
# Safe to run again at any time: it only does what's missing.
S="$(cd "$(dirname "$0")" && pwd)/setup/install-all.sh"
[ -f "$S" ] || S="$HOME/Library/Application Support/Mac Wi-Fi/setup/install-all.sh"
if [ -f "$S" ]; then bash "$S"; else echo "Can't find the installer (setup/install-all.sh). Keep this file next to its 'setup' folder."; fi
echo
read -r -p "Press Return to close this window." _
