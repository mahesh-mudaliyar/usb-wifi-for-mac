#!/bin/bash
# Re-runs the Alpine side of the setup (driver firmware, Wi-Fi helpers, network, NAT, keepalive)
# on an existing Alpine machine, then restarts it. Alpine needs internet for this, so its Wi-Fi
# must be connected (or the machine must be on VMware's NAT network).
# Usage: bash setup/mac/push-alpine-setup.sh [alpine-ip]     (default 192.168.235.100)
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
IP=${1:-$ALPINE_IP}
[ -f "$SSHCFG" ] || fail "Missing $SSHCFG." "Run 'Install Mac Wi-Fi' first."
step "Re-run the Alpine setup on $IP"
alp_up -o HostName="$IP" || fail "Alpine isn't answering at $IP." "Start it with '1 Start Wi-Fi' first."
B=$(mktemp -d "${TMPDIR:-/tmp}/alpinewifi-push.XXXXXX") || fail "Couldn't make a temporary folder."
add_cleanup "rm -rf '$B'"
make_alpine_bundle "$B" || fail "Couldn't collect the setup files."
COPYFILE_DISABLE=1 tar --format ustar -C "$B" -cf - . |
  with_timeout 1200 ssh -F "$SSHCFG" -o HostName="$IP" -o ConnectTimeout=5 alp \
    'rm -rf /root/alpinewifi-setup && mkdir -p /root/alpinewifi-setup && tar -xf - -C /root/alpinewifi-setup && FINISH=reboot sh /root/alpinewifi-setup/install.sh' \
  || fail "The Alpine setup didn't finish." "Read the messages above; the log inside Alpine is /root/alpinewifi-install.log."
ok "Alpine setup re-applied; Alpine is restarting (about 30 s)"
