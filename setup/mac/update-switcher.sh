#!/bin/sh
# Run with sudo from the Alpine WiFi VM folder. Installs the latest Wi-Fi/USB switcher and runs it once right away.
[ "$(id -u)" = 0 ] || { echo "Run with sudo"; exit 1; }
D=$(cd "$(dirname "$0")" && pwd)
U=${SUDO_USER:-$(stat -f %Su /dev/console)}
H=$(dscl . -read "/Users/$U" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
[ -d "$H" ] || { echo "Can't find the home folder of $U"; exit 1; }
T=$(mktemp /tmp/alpinewifi-failover.XXXXXX) || exit 1
sed "s|__USER_HOME__|$H|g" "$D/wifi-failover.sh" > "$T"
install -o root -g wheel -m 755 "$T" /usr/local/libexec/alpinewifi-failover.sh
rm -f "$T"
sh /usr/local/libexec/alpinewifi-failover.sh
sleep 3
echo "Route to Alpine: $(route -n get 192.168.235.100 2>/dev/null | awk '/interface/{print $2}')  (should be a bridge interface)"
ping -c1 -t2 192.168.235.100 >/dev/null 2>&1 && echo "Alpine reachable: yes" || echo "Alpine reachable: NO"
echo "Main connection: $(route -n get default 2>/dev/null | awk '/interface/{print $2}')"
curl -s -o /dev/null --max-time 8 https://www.apple.com && echo "Internet: WORKING" || echo "Internet: not working"
echo "--- switcher log ---"; tail -5 /var/log/alpinewifi.log 2>/dev/null
