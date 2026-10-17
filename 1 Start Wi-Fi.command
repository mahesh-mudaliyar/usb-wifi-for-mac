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
rm -f "$HOME/.alpinewifi-disabled"

# 1. VMware and the Wi-Fi adapter
[ -x "$VR" ] || fail "VMware Fusion isn't installed in Applications."
if ioreg -p IOUSB -l -w0 2>/dev/null | grep -q '"USB Product Name" = "802.11n NIC"' || "$VR" list 2>/dev/null | grep -qxF "$V/Alpine WiFi.vmx"; then
  ok "Wi-Fi adapter detected"
else
  info "Wi-Fi adapter not seen on USB - check it's plugged in (continuing anyway)"
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
  info "Waiting for the Wi-Fi adapter to appear in Alpine..."
  for i in $(seq 1 15); do "${SSH[@]}" '[ -e /sys/class/net/wlan0 ]' 2>/dev/null && break; sleep 2; done
  "${SSH[@]}" '[ -e /sys/class/net/wlan0 ]' 2>/dev/null || fail "Alpine can't see the Wi-Fi adapter. Unplug it, plug it back in, and try again."
}
ok "Wi-Fi adapter working in Alpine"

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
ok "Connected to \"$ssid\"  (signal $sig, address $addr)"

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
