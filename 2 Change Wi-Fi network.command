#!/bin/bash
# Search for Wi-Fi networks, pick one, and connect the Alpine Wi-Fi adapter to it.
# Every network you join is remembered; Alpine reconnects to whichever is in range.
V="$HOME/Virtual Machines.localized/Alpine WiFi.vmwarevm"
SSH=(ssh -n -F "$V/sshcfg" -o ConnectTimeout=5 alp)
SSHIN=(ssh -F "$V/sshcfg" -o ConnectTimeout=5 alp)

if ! "${SSH[@]}" true 2>/dev/null; then
  echo "The Alpine Wi-Fi machine isn't running. Double-click \"1 Start Wi-Fi\" first, then try again."
  read -r -p "Press Return to close." _; exit 1
fi

# which bands the dongle can use, e.g. "2.4GHz" or "2.4GHz+5GHz"
BANDS=$("${SSH[@]}" '/usr/local/bin/wifi-adapter-info 2>/dev/null | tail -1' 2>/dev/null | awk '$2 == "ok" {print $5}')
[ -n "$BANDS" ] && echo "Your Wi-Fi dongle can use: $BANDS"

while true; do
  echo
  echo "Current Wi-Fi: $("${SSH[@]}" "iw dev wlan0 link | sed -n 's/^[[:space:]]*SSID: //p'" 2>/dev/null || true)"
  echo "Searching for Wi-Fi networks..."
  list=$("${SSH[@]}" /usr/local/bin/wifi-scan-list 2>/dev/null)
  names=(); i=0
  echo
  if [ -z "$list" ]; then
    echo "  No networks found. (This dongle sees: ${BANDS:-unknown bands}.)"
  else
    printf "  %-3s %-34s %-8s %s\n" "#" "Network" "Signal" "Lock"
    while IFS='|' read -r sig sec name; do
      i=$((i+1)); names[i]="$name"
      if   [ "$sig" -ge -60 ]; then bars="●●●●"
      elif [ "$sig" -ge -70 ]; then bars="●●●○"
      elif [ "$sig" -ge -80 ]; then bars="●●○○"
      else bars="●○○○"; fi
      lock=""; [ "$sec" = locked ] && lock="password"
      printf "  %-3s %-34s %-8s %s\n" "$i" "$name" "$bars" "$lock"
    done <<< "$list"
  fi
  echo
  echo "  r = search again    h = hidden network (type its name)    q = quit"
  read -r -p "Choose a network number: " pick

  case "$pick" in
    q|Q) exit 0 ;;
    r|R|"") continue ;;
    h|H) read -r -p "Network name (exactly, including capitals): " SSID; secured=ask ;;
    *)
      if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le "$i" ]; then
        SSID="${names[$pick]}"
        secured=$(echo "$list" | sed -n "${pick}p" | cut -d'|' -f2)
      else
        echo "\"$pick\" isn't on the list."; continue
      fi ;;
  esac
  [ -n "$SSID" ] || { echo "No name entered."; continue; }

  PASS=""
  if [ "$secured" = locked ] || [ "$secured" = ask ]; then
    [ "$secured" = ask ] && echo "(Leave empty if the network has no password.)"
    read -r -s -p "Password for \"$SSID\" (hidden as you type): " PASS; echo
  fi

  echo "Connecting to \"$SSID\"..."
  result=$(printf '%s\n%s\n' "$SSID" "$PASS" | "${SSHIN[@]}" /usr/local/bin/wifi-join 2>&1)
  PASS=""
  echo "${result//RESULT: /}"
  if echo "$result" | grep -q "with internet"; then
    echo "The Mac will switch to this Wi-Fi by itself within about 30 seconds."
    read -r -p "Press Return to close." _; exit 0
  fi
  echo "Pick another network or try again."
done
