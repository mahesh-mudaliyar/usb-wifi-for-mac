#!/bin/sh
# Run with sudo, from the Alpine WiFi VM folder (the installer copies it there).
# Sets up: phone USB tethering as a background service (muta), and a root watchdog
# that prefers Alpine Wi-Fi and falls back to USB automatically.
[ "$(id -u)" = 0 ] || { echo "Run with sudo"; exit 1; }
D=$(cd "$(dirname "$0")" && pwd)
U=${SUDO_USER:-$(stat -f %Su /dev/console)}
H=$(dscl . -read "/Users/$U" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
[ -d "$H" ] || { echo "Can't find the home folder of $U"; exit 1; }
MUTA="$H/.cargo/bin/muta"
[ -x "$MUTA" ] || { echo "muta isn't installed at $MUTA"; exit 1; }
[ -f "$D/wifi-failover.sh" ] || { echo "wifi-failover.sh is missing from $D"; exit 1; }

echo "1/3 Installing phone USB tethering as a background service..."
pkill -INT -f "muta run" 2>/dev/null || true
sleep 3
"$MUTA" install || { echo "muta install failed"; exit 1; }

echo "2/3 Installing the Wi-Fi/USB switcher..."
mkdir -p /usr/local/libexec
T=$(mktemp /tmp/alpinewifi-failover.XXXXXX) || exit 1
sed "s|__USER_HOME__|$H|g" "$D/wifi-failover.sh" > "$T"
install -o root -g wheel -m 755 "$T" /usr/local/libexec/alpinewifi-failover.sh
rm -f "$T"
cat > /Library/LaunchDaemons/com.alpinewifi.failover.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.alpinewifi.failover</string>
  <key>ProgramArguments</key><array><string>/bin/sh</string><string>/usr/local/libexec/alpinewifi-failover.sh</string></array>
  <key>StartInterval</key><integer>15</integer>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST
chown root:wheel /Library/LaunchDaemons/com.alpinewifi.failover.plist
chmod 644 /Library/LaunchDaemons/com.alpinewifi.failover.plist
launchctl bootout system/com.alpinewifi.failover 2>/dev/null || true
sleep 1
launchctl bootstrap system /Library/LaunchDaemons/com.alpinewifi.failover.plist || { echo "Couldn't start the switcher"; exit 1; }

echo "3/3 Checking..."
sleep 5
"$MUTA" status || true
echo "Main connection: $(route -n get default 2>/dev/null | awk '/interface/{print $2}')  (bridge = Wi-Fi via Alpine, utun = phone USB)"
echo "Done. Wi-Fi is preferred; USB tethering takes over automatically when Wi-Fi has no internet."
