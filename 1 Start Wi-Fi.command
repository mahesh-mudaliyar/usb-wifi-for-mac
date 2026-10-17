#!/bin/bash
# Turns Wi-Fi on: starts the hidden Alpine Wi-Fi machine, waits for it to join Wi-Fi,
# then waits for the Mac to switch over. Shows each step as it happens.
V="$HOME/Virtual Machines.localized/Alpine WiFi.vmwarevm"
VR="/Applications/VMware Fusion.app/Contents/Library/vmrun"
SSH=(ssh -n -F "$V/sshcfg" -o ConnectTimeout=3 alp)
START=$(date +%s)
t()    { printf "[%3ss] " $(( $(date +%s) - START )); }
ok()   { t; echo "OK    $*"; }
info() { t; echo "...   $*"; }
fail() { t; echo "PROBLEM: $*"; echo; read -r -p "Press Return to close." _; exit 1; }
main_gw() { route -n get default 2>/dev/null | awk '/gateway/{print $2}'; }
main_if() { route -n get default 2>/dev/null | awk '/interface/{print $2}'; }

echo "=== Turning on Wi-Fi ==="
if [ -f "$HOME/.alpinewifi-disabled" ]; then
  info "Wi-Fi was turned OFF (shortcut 3, since $(stat -f '%Sm' -t '%d %b %H:%M' "$HOME/.alpinewifi-disabled" 2>/dev/null)) - turning it back ON"
  rm -f "$HOME/.alpinewifi-disabled"
else
  ok "Wi-Fi setting is ON"
fi

# the USB Wi-Fi dongle chosen by "Check Wi-Fi hardware" (default: the original RTL8188EU)
AID=$(sed -n 's/^ID=//p' "$HOME/.alpinewifi-adapter" 2>/dev/null | head -1); AID=${AID:-0bda:8179}
ANAME=$(sed -n 's/^NAME=//p' "$HOME/.alpinewifi-adapter" 2>/dev/null | head -1); ANAME=${ANAME:-USB Wi-Fi dongle}
on_usb() { ioreg -p IOUSB -l -w0 2>/dev/null | awk -v v=$((16#${AID%%:*})) -v p=$((16#${AID##*:})) '
  /"idVendor" = / { cv = $NF } /"idProduct" = / { if (cv == v && $NF == p) f = 1 } END { exit !f }'; }
# why_no_wlan  - asks Alpine what it sees of the dongle and explains it
why_no_wlan() {
  local s; s=$("${SSH[@]}" '/usr/local/bin/wifi-adapter-info 2>/dev/null | tail -1' 2>/dev/null)
  case "$s" in
    "ADAPTER firmware"*) echo "Alpine has a driver for the dongle, but its firmware is missing (${s#ADAPTER firmware }). Run 'Install Mac Wi-Fi' with internet available." ;;
    "ADAPTER nodriver"*) echo "Alpine sees USB device ${s#ADAPTER nodriver } but has no Linux driver for it - this dongle won't work. See docs/WIFI-ADAPTERS.md." ;;
    "ADAPTER none"*)     echo "Alpine doesn't see the dongle. Unplug it, plug it back in, and try again. If you changed dongles, run 'Check Wi-Fi hardware' first." ;;
    *)                   echo "Alpine can't see the Wi-Fi dongle. Unplug it, plug it back in, and try again." ;;
  esac
}

# 1. VMware and the Wi-Fi dongle
[ -x "$VR" ] || fail "VMware Fusion isn't installed in Applications."
if on_usb || "$VR" list 2>/dev/null | grep -qxF "$V/Alpine WiFi.vmx"; then
  ok "Wi-Fi dongle: $ANAME ($AID)"
else
  info "$ANAME ($AID) not seen on USB - check it's plugged in (continuing anyway)"
fi

# 2. Alpine machine
if "$VR" list 2>/dev/null | grep -qxF "$V/Alpine WiFi.vmx"; then
  ok "Alpine machine already running"
else
  info "Starting the Alpine machine (hidden)..."
  sh "$V/autostart-vm.sh"
  "$VR" list 2>/dev/null | grep -qxF "$V/Alpine WiFi.vmx" || fail "Alpine didn't start. Open VMware Fusion once to see why, then try again."
  ok "Alpine machine started"
fi

# 3. Reach Alpine
info "Waiting for Alpine to finish booting..."
for i in $(seq 1 40); do "${SSH[@]}" true 2>/dev/null && break; sleep 3; done
"${SSH[@]}" true 2>/dev/null || fail "Can't reach Alpine after 2 minutes. Run \"0 Which internet am I on\" and tell Claude what it says."
ok "Alpine is up"

# 4. Wi-Fi adapter inside Alpine
"${SSH[@]}" '[ -e /sys/class/net/wlan0 ]' 2>/dev/null || {
  info "Waiting for the Wi-Fi dongle to appear in Alpine..."
  for i in $(seq 1 15); do "${SSH[@]}" '[ -e /sys/class/net/wlan0 ]' 2>/dev/null && break; sleep 2; done
  "${SSH[@]}" '[ -e /sys/class/net/wlan0 ]' 2>/dev/null || fail "$(why_no_wlan)"
}
ok "Wi-Fi dongle working in Alpine"

# 5. Join Wi-Fi
"${SSH[@]}" 'grep -q "^network=" /etc/wpa_supplicant/wpa_supplicant.conf' 2>/dev/null || fail "No Wi-Fi network saved yet. Use \"2 Change Wi-Fi network\" to pick one."
info "Joining Wi-Fi (Alpine retries automatically, up to ~4 minutes after a restart)..."
last=""
for i in $(seq 1 80); do
  # shellcheck disable=SC2016  # runs inside Alpine
  st=$("${SSH[@]}" 'if iw dev wlan0 link 2>/dev/null | grep -q Connected; then a=$(ip -4 addr show wlan0 | sed -n "s/.*inet \([0-9.]*\).*/\1/p"); echo "linked|$(iw dev wlan0 link | sed -n "s/^[[:space:]]*SSID: //p")|$(iw dev wlan0 link | sed -n "s/^[[:space:]]*signal: //p")|$a"; else echo "searching"; fi' 2>/dev/null)
  case "$st" in
    linked*) IFS='|' read -r _ ssid sig addr <<< "$st"; [ -n "$addr" ] && break; [ "$last" != joined ] && { info "Joined \"$ssid\", waiting for an address from the router..."; last=joined; } ;;
    *) [ $((i % 10)) -eq 0 ] && info "Still searching for a saved network..." ;;
  esac
  sleep 3
done
[ -n "$addr" ] || fail "Couldn't join a saved Wi-Fi network. Is it in range? Use \"2 Change Wi-Fi network\" to search and pick one."
case "$sig" in ""|0*) sigtxt="" ;; *) sigtxt="signal $sig, " ;; esac
ok "Connected to \"$ssid\"  (${sigtxt}address $addr)"

# 6. Internet through Wi-Fi
if "${SSH[@]}" 'ping -c1 -W3 1.1.1.1 >/dev/null 2>&1 || ping -c1 -W3 8.8.8.8 >/dev/null 2>&1' 2>/dev/null; then
  ok "\"$ssid\" has internet"
else
  fail "Joined \"$ssid\" but it has no internet (router offline, or a login page). The Mac stays on the phone."
fi

# 7. Mac switches over
info "Waiting for the Mac to switch to Wi-Fi (the switcher checks every 15 s, up to 90 s)..."
for i in $(seq 1 30); do [ "$(main_gw)" = 192.168.235.100 ] && break; sleep 3; done
if [ "$(main_gw)" = 192.168.235.100 ]; then
  ok "Mac switched to Wi-Fi"
else
  fail "The Mac hasn't switched yet (still on $(main_if)). Run \"0 Which internet am I on\" in a minute; if it still hasn't, tell Claude."
fi
if curl -s -o /dev/null --max-time 8 https://www.apple.com; then ok "Mac internet working"; else info "Mac internet test failed - try again in a few seconds"; fi

echo
echo "=== Wi-Fi is on: \"$ssid\". Phone USB tethering stays ready as a backup. ==="
read -r -p "Press Return to close." _
