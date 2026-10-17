#!/bin/sh
# Runs at login and every minute: keeps the Alpine Wi-Fi machine running hidden
# (no window, no Dock icon), unless you turned Wi-Fi off with shortcut 3.
D="$HOME/Virtual Machines.localized/Alpine WiFi.vmwarevm"
VR="/Applications/VMware Fusion.app/Contents/Library/vmrun"
LOG="$HOME/Library/Logs/alpinewifi-autostart.log"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

[ -f "$HOME/.alpinewifi-disabled" ] && exit 0
[ -x "$VR" ] || { log "vmrun not found"; exit 0; }
"$VR" list 2>/dev/null | grep -qxF "$D/Alpine WiFi.vmx" && exit 0

log "Alpine not running - starting it"
# Clear a lock left behind by a crash or restart
if ! pgrep -f "Contents/Library/vmware-vmx" >/dev/null && [ -d "$D/Alpine WiFi.vmx.lck" ]; then
  mkdir -p "$D/old"; mv "$D/Alpine WiFi.vmx.lck" "$D/old/lock-$(date +%s)"; log "cleared stale lock"
fi
gui_was_open=no; pgrep -x "VMware Fusion" >/dev/null && gui_was_open=yes
out=$("$VR" -T fusion start "$D/Alpine WiFi.vmx" nogui 2>&1); rc=$?
log "vmrun start exit=$rc $(echo "$out" | tr '\n' ' ' | cut -c1-200)"
# vmrun opens the Fusion window; close it again unless you had it open yourself
sleep 8
[ "$gui_was_open" = no ] && pkill -x "VMware Fusion"
if "$VR" list 2>/dev/null | grep -qxF "$D/Alpine WiFi.vmx"; then log "Alpine running"; else log "Alpine still NOT running"; fi
exit 0
