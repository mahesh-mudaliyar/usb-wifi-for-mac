#!/bin/sh
# Runs as root every 15 seconds.
# Prefers Wi-Fi through the Alpine VM; falls back to phone USB tethering (muta); returns when Wi-Fi recovers.
HOSTIP=192.168.235.1
GW=192.168.235.100
NETADDR=192.168.235.0
IF=$(ifconfig | awk -v h="$HOSTIP" '/^[a-z]/{i=$1; sub(":","",i)} $1=="inet" && $2==h {print i; exit}')
ST=/var/run/alpinewifi
MUTA=/usr/local/libexec/muta/muta
DISABLED="__USER_HOME__/.alpinewifi-disabled"
mkdir -p $ST

log() { logger -t alpinewifi "$*"; echo "$(date '+%F %T') $*" >> /var/log/alpinewifi.log; }

# VMware's network isn't up yet (just booted, Fusion services starting)
[ -n "$IF" ] && ifconfig "$IF" >/dev/null 2>&1 || exit 0

to_alpine_ok() { route -n get $GW 2>/dev/null | grep -q "interface: $IF"; }
ensure_subnet() {
  to_alpine_ok && return
  # 1. remove wrong cached routes to Alpine, including ones tied to another interface (e.g. the phone's utun)
  for i in $(ifconfig -l); do route -n delete -host $GW -ifscope "$i" >/dev/null 2>&1; done
  route -n delete -host $GW >/dev/null 2>&1
  to_alpine_ok && { log "route to Alpine fixed (cached route removed)"; return; }
  # 2. re-apply VMware's address so macOS rebuilds the local network route
  out=$(ifconfig "$IF" inet $HOSTIP netmask 255.255.255.0 2>&1); [ -n "$out" ] && log "ifconfig: $out"
  sleep 1
  to_alpine_ok && { log "route to Alpine fixed (address re-applied)"; return; }
  # 3. add the routes by hand
  out=$(route -n add -net $NETADDR -netmask 255.255.255.0 -interface "$IF" 2>&1); log "subnet add: $out"
  out=$(route -n add -host $GW -interface "$IF" 2>&1); log "host add: $out"
  to_alpine_ok && { log "route to Alpine fixed (added by hand)"; return; }
  log "still no route to Alpine: $(route -n get $GW 2>&1 | grep -E 'gateway|interface|flags' | tr -s ' \n' ' ')"
}
ensure_scoped_default() {
  # VMware adds a gateway-less default on bridge101; point it at Alpine instead
  if [ "$(route -n get -ifscope "$IF" default 2>/dev/null | awk '/gateway/{print $2}')" != "$GW" ]; then
    route -n delete -ifscope "$IF" default >/dev/null 2>&1
    route -n add -ifscope "$IF" default $GW >/dev/null 2>&1
  fi
}
flush_rejects() {
  # cached "host down" routes left over from a broken moment
  netstat -rn -f inet | awk -v i="$IF" '$4==i && $3 ~ /R/ {print $1}' | while read -r h; do route -n delete -host "$h" >/dev/null 2>&1; done
}
ensure_usb_default() {
  route -n get default >/dev/null 2>&1 && return
  g=$($MUTA status 2>/dev/null | awk '/^gateway/{print $2}')
  [ -n "$g" ] && route -n add default "$g" >/dev/null 2>&1
}
wifi_ok() {
  # Real internet through Alpine, without DNS, that a Wi-Fi login page can't fake (TLS to an IP)
  ping -c1 -t2 $GW >/dev/null 2>&1 || { echo "Alpine not reachable" > $ST/reason; return 1; }
  flush_rejects   # don't let failures cached while Alpine was still booting block this test
  curl -s --interface "$IF" --max-time 6 https://1.1.1.1/cdn-cgi/trace 2>/dev/null | grep -q '^ip=' && return 0
  [ "$(curl -s -o /dev/null -w '%{http_code}' --interface "$IF" --max-time 6 https://8.8.8.8/ 2>/dev/null)" != 000 ] && return 0
  echo "Alpine reachable but no internet through it" > $ST/reason; return 1
}
active() {
  printf 'show State:/Network/Service/AlpineWiFi/IPv4\n' | scutil | grep -q Router
}
use_wifi() {
  scutil <<EOF
d.init
d.add Addresses * $HOSTIP
d.add SubnetMasks * 255.255.255.0
d.add InterfaceName $IF
d.add Router $GW
d.add OverridePrimary # 1
set State:/Network/Service/AlpineWiFi/IPv4
d.init
d.add ServerAddresses * 1.1.1.1 8.8.8.8
d.add SupplementalMatchDomains * ""
set State:/Network/Service/AlpineWiFi/DNS
EOF
  sleep 2
  ensure_subnet; ensure_scoped_default; flush_rejects
}
use_usb() {
  scutil <<EOF
remove State:/Network/Service/AlpineWiFi/IPv4
remove State:/Network/Service/AlpineWiFi/DNS
EOF
  sleep 2
  ensure_subnet; ensure_scoped_default; ensure_usb_default; flush_rejects
}
bump()  { n=$(( $(cat "$ST/$1" 2>/dev/null || echo 0) + 1 )); echo $n > "$ST/$1"; echo $n; }
reset() { echo 0 > "$ST/$1"; }

ensure_subnet
ensure_scoped_default

if [ -f "$DISABLED" ]; then
  if active; then use_usb; log "Wi-Fi turned off by user, using phone USB"; fi
  ensure_usb_default
  exit 0
fi

if wifi_ok; then
  reset bad
  if ! active && [ "$(bump good)" -ge 2 ]; then use_wifi; reset good; log "switched Mac to Wi-Fi ($(( $(date +%s) - $(sysctl -n kern.boottime | awk -F'[ ,]+' '{print $4}') ))s after boot)"; fi
else
  reset good
  # note why Wi-Fi isn't usable, once per change of reason
  r=$(cat $ST/reason 2>/dev/null); [ "$r" != "$(cat $ST/lastreason 2>/dev/null)" ] && { ! active && log "Wi-Fi not usable yet: $r"; echo "$r" > $ST/lastreason; }
  if active; then
    if [ "$(bump bad)" -ge 2 ]; then use_usb; reset bad; log "Wi-Fi has no internet, switched Mac to phone USB"; fi
  else
    ensure_usb_default
  fi
fi
exit 0
