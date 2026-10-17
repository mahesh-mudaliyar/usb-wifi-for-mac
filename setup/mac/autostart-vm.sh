#!/bin/sh
# Runs at login and every minute:
#  1. keeps the Alpine Wi-Fi machine running hidden (no window, no Dock icon),
#  2. self-heals the Wi-Fi adapter: if Alpine's Wi-Fi stays down and the radio can't see any
#     networks, restarts Alpine - a fresh VMware USB link revives the adapter, Alpine's own resets can't.
# Does nothing while Wi-Fi is turned off with shortcut 3.
D="$HOME/Virtual Machines.localized/Alpine WiFi.vmwarevm"
VR="/Applications/VMware Fusion.app/Contents/Library/vmrun"
LOG="$HOME/Library/Logs/alpinewifi-autostart.log"
HEALED="$HOME/Library/Caches/alpinewifi-lastheal"
ssha() { ssh -n -F "$D/sshcfg" -o ConnectTimeout=4 alp "$@"; }
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

start_alpine() {
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
}

[ -f "$HOME/.alpinewifi-disabled" ] && exit 0
[ -x "$VR" ] || { log "vmrun not found"; exit 0; }

# 1. Keep Alpine running
if ! "$VR" list 2>/dev/null | grep -qxF "$D/Alpine WiFi.vmx"; then
  log "Alpine not running - starting it"
  start_alpine
  exit 0
fi

# 2. Self-heal a stuck Wi-Fi adapter
# shellcheck disable=SC2046,SC2016  # split into 3 numbers on purpose; the command runs inside Alpine
set -- $(ssha 'echo "$(cut -d. -f1 /proc/uptime) $(cat /run/wifi-keepalive.fails 2>/dev/null || echo 0) $(iw dev wlan0 link 2>/dev/null | grep -c Connected)"' 2>/dev/null)
up=${1:-0}; fails=${2:-0}; linked=${3:-1}
# only when Alpine has been up 4+ minutes and its Wi-Fi has failed 3+ checks in a row
[ "$up" -gt 240 ] && [ "$linked" = 0 ] && [ "$fails" -ge 3 ] || exit 0
last=$(cat "$HEALED" 2>/dev/null || echo 0)
[ $(( $(date +%s) - last )) -gt 600 ] || exit 0           # at most once every 10 minutes
seen=$(ssha '/usr/local/bin/wifi-scan-list | wc -l' 2>/dev/null | tr -d ' ')
# a deaf radio sees nothing; if networks are visible, only restart after a long outage
[ "${seen:-0}" -eq 0 ] || [ "$fails" -ge 10 ] || exit 0
log "Wi-Fi down for $fails checks, radio sees ${seen:-0} networks - restarting Alpine to reset the adapter"
date +%s > "$HEALED"
ssha poweroff 2>/dev/null
for _ in $(seq 1 30); do "$VR" list 2>/dev/null | grep -qxF "$D/Alpine WiFi.vmx" || break; sleep 2; done
"$VR" list 2>/dev/null | grep -qxF "$D/Alpine WiFi.vmx" && "$VR" -T fusion stop "$D/Alpine WiFi.vmx" hard >/dev/null 2>&1
start_alpine
exit 0
