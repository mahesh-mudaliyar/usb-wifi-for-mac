#!/bin/bash
# Saves a copy of the working Alpine Wi-Fi machine (with your saved Wi-Fi networks) to
# ~/Mac Wi-Fi Backups. Wi-Fi pauses for 1-2 minutes; the Mac uses the phone meanwhile.
S="$(cd "$(dirname "$0")" && pwd)/setup/backup.sh"
[ -f "$S" ] || S="$HOME/Library/Application Support/Mac Wi-Fi/setup/backup.sh"
if [ -f "$S" ]; then bash "$S"; else echo "Can't find setup/backup.sh. Run 'Install Mac Wi-Fi' once first."; fi
echo
read -r -p "Press Return to close." _
