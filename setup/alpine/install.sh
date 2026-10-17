#!/bin/sh
# Runs inside Alpine as root. Turns it into the Mac's Wi-Fi router:
#   - Wi-Fi driver: the rtl8xxxu driver is already in Alpine's kernel; it only needs the
#     Realtek firmware from the linux-firmware-rtlwifi package (plus iw / wpa_supplicant)
#   - the wifi-join / wifi-scan-list / wifi-keepalive helpers
#   - a fixed address on eth0 (the Mac's side), DHCP on wlan0 (the Wi-Fi side)
#   - NAT, so the Mac's traffic goes out through Wi-Fi
#   - a cron job that reconnects Wi-Fi every minute if it drops
# Safe to run again. Settings come from files/alpinewifi.env (ALPINE_IP, HOST_NET).
# FINISH=reboot (default) | poweroff | none  - what to do when done.
cd "$(dirname "$0")" || exit 1
LOG=/root/alpinewifi-install.log
ALPINE_IP=192.168.235.100
HOST_NET=192.168.235.0/24
# shellcheck disable=SC1091
[ -f files/alpinewifi.env ] && . ./files/alpinewifi.env
FINISH=${FINISH:-reboot}

say() { echo "$*"; echo "$(date '+%F %T') $*" >> "$LOG"; }
die() { say "PHASE2 FAILED: $* boot=$(cat /proc/sys/kernel/random/boot_id)"; exit 1; }
run() { "$@" >> "$LOG" 2>&1; }    # details go to the log only

[ "$(id -u)" = 0 ] || die "this must run as root"
say "=== Alpine Wi-Fi router setup (Alpine $(cat /etc/alpine-release), address $ALPINE_IP) ==="

say "1/7 Waiting for internet inside Alpine (needed to download packages, up to 2 min)..."
deadline=$(( $(date +%s) + 120 ))
until timeout 8 wget -q -T 5 -O /dev/null http://dl-cdn.alpinelinux.org/alpine/ 2>/dev/null; do
  [ "$(date +%s)" -ge $deadline ] && die "no internet inside Alpine after 2 minutes (first setup: VMware's NAT network and the Mac must be online; later: Alpine's own Wi-Fi must be connected)"
  sleep 5
done

say "2/7 Installing Wi-Fi tools, Realtek firmware and firewall (1-5 min)..."
PKGS="iw wpa_supplicant wireless-regdb linux-firmware-rtlwifi linux-firmware-other iptables openssh chrony"
n=0
run apk update
# shellcheck disable=SC2086
until run timeout 600 apk add --no-progress $PKGS; do
  n=$((n + 1))
  [ $n -ge 3 ] && die "installing packages failed 3 times (details in $LOG)"
  say "    download problem - trying again in 10 s ($n of 3)"
  sleep 10
  run apk update
done

say "3/7 Installing the Wi-Fi helpers..."
install -m 755 files/wifi-join files/wifi-scan-list files/wifi-keepalive /usr/local/bin/ || die "couldn't copy the helpers"
mkdir -p /etc/wpa_supplicant
[ -f /etc/wpa_supplicant/wpa_supplicant.conf ] || printf "ctrl_interface=/var/run/wpa_supplicant\nupdate_config=1\ncountry=IN\n" > /etc/wpa_supplicant/wpa_supplicant.conf
chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf

say "4/7 Network settings (eth0 = $ALPINE_IP for the Mac, wlan0 = Wi-Fi)..."
[ -f /etc/network/interfaces.orig ] || cp /etc/network/interfaces /etc/network/interfaces.orig 2>/dev/null
sed "s/__ALPINE_IP__/$ALPINE_IP/" files/interfaces > /etc/network/interfaces || die "couldn't write the network settings"
echo alpinewifi > /etc/hostname
hostname alpinewifi
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/90-alpinewifi.conf
run sysctl -p /etc/sysctl.d/90-alpinewifi.conf

say "5/7 Firewall: share Wi-Fi with the Mac (NAT)..."
# stop first: the iptables service saves its current rules over the file when it stops
run rc-service iptables stop
mkdir -p /etc/iptables
cp files/rules-save /etc/iptables/rules-save
run rc-update add iptables default
run rc-service iptables start || die "the firewall rules didn't load (details in $LOG)"

say "6/7 Services and the every-minute Wi-Fi keepalive..."
grep -q wifi-keepalive /etc/crontabs/root 2>/dev/null || echo "* * * * * /usr/local/bin/wifi-keepalive" >> /etc/crontabs/root
mkdir -p /etc/ssh/sshd_config.d
echo "PerSourcePenaltyExemptList $HOST_NET" > /etc/ssh/sshd_config.d/10-mac-exempt.conf
run sshd -t || { rm -f /etc/ssh/sshd_config.d/10-mac-exempt.conf; say "    (this SSH version doesn't know PerSourcePenaltyExemptList - skipped)"; }
for s in networking:boot sysctl:boot sshd:default crond:default chronyd:default; do
  run rc-update add "${s%%:*}" "${s##*:}"
done
run rc-service crond restart
# rebuild OpenRC's service list now; otherwise a wrong clock at boot can make it skip new services
run rc-update -u

say "7/7 Checking everything..."
modinfo rtl8xxxu >/dev/null 2>&1          || die "the rtl8xxxu Wi-Fi driver is missing from the kernel (is linux-lts installed?)"
ls /lib/firmware/rtlwifi/rtl8188eufw.bin* >/dev/null 2>&1 || die "the Realtek firmware file is missing"
iptables -t nat -C POSTROUTING -o wlan0 -j MASQUERADE 2>/dev/null || die "the NAT rule isn't active"
[ "$(cat /proc/sys/net/ipv4/ip_forward)" = 1 ] || die "IP forwarding is off"
grep -q wifi-keepalive /etc/crontabs/root  || die "the keepalive job wasn't added"
say "    driver rtl8xxxu: OK, firmware: OK, NAT: OK, forwarding: OK, keepalive: OK"
modprobe rtl8xxxu 2>/dev/null
sleep 2
if [ -e /sys/class/net/wlan0 ]; then
  say "    Wi-Fi adapter: found ($(dmesg | grep -o 'RTL8188[A-Z]*' | tail -1))"
else
  say "    Wi-Fi adapter: not connected right now (that's fine during setup)"
fi

rm -f /etc/local.d/alpinewifi-firstboot.start
say "PHASE2 DONE boot=$(cat /proc/sys/kernel/random/boot_id)"
case "$FINISH" in
  poweroff) say "Shutting down in a few seconds."; (sleep 8; poweroff) >/dev/null 2>&1 & ;;
  reboot)   say "Restarting in a few seconds; it comes back at $ALPINE_IP."; (sleep 3; reboot) >/dev/null 2>&1 & ;;
esac
exit 0
