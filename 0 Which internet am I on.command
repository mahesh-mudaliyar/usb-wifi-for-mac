#!/bin/bash
# Shows which internet the Mac is using right now, and the state of Wi-Fi and the phone.
V="$HOME/Virtual Machines.localized/Alpine WiFi.vmwarevm"
main=$(route -n get default 2>/dev/null | awk '/interface/{print $2}'); gw=$(route -n get default 2>/dev/null | awk '/gateway/{print $2}'); [ "$gw" = 192.168.235.100 ] && main=alpine
case "$main" in
  alpine) using="Wi-Fi (through the Alpine machine)" ;;
  utun*)     using="Phone USB tethering" ;;
  "")        using="NOTHING - no connection" ;;
  *)         using="$main" ;;
esac
echo "Mac is using:   $using"
[ "$main" != alpine ] && [ -s /var/run/alpinewifi/reason ] && echo "Why not Wi-Fi:  $(cat /var/run/alpinewifi/reason)"
curl -s -o /dev/null --max-time 6 https://www.apple.com && echo "Internet:       working" || echo "Internet:       NOT working"
if ssh -n -F "$V/sshcfg" -o ConnectTimeout=3 alp true 2>/dev/null; then
  w=$(ssh -n -F "$V/sshcfg" alp "iw dev wlan0 link | sed -n 's/^[[:space:]]*SSID: //p'; iw dev wlan0 link | sed -n 's/^[[:space:]]*signal: //p'" 2>/dev/null | paste -sd'|' -)
  echo "Wi-Fi network:  ${w%%|*}  (signal ${w##*|})"
  a=$(ssh -n -F "$V/sshcfg" alp '/usr/local/bin/wifi-adapter-info 2>/dev/null | tail -1' 2>/dev/null)
  case "$a" in
    "ADAPTER ok"*) echo "Wi-Fi dongle:   working (${a#ADAPTER ok })" ;;
    "ADAPTER "*)   echo "Wi-Fi dongle:   PROBLEM (${a#ADAPTER }) - run '1 Start Wi-Fi' for an explanation" ;;
  esac
else
  [ -f "$HOME/.alpinewifi-disabled" ] && echo "Wi-Fi:          turned off (shortcut 3). Use shortcut 1 to turn it on." || echo "Wi-Fi:          Alpine machine starting or not running"
fi
"$HOME/.cargo/bin/muta" status 2>/dev/null | grep -q "connected" && echo "Phone USB:      connected (backup ready)" || echo "Phone USB:      not connected"
echo; echo "Recent switches:"; tail -3 /var/log/alpinewifi.log 2>/dev/null | sed 's/^/  /'
read -r -p "Press Return to close." _
