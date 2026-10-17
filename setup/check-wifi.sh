#!/bin/bash
# Checks two things and explains the options:
#   1. Can this Mac use its own (built-in) Wi-Fi?  If yes, you don't need the Alpine setup at all.
#   2. Which USB Wi-Fi dongle is plugged in, and does Alpine's Linux have a driver for it?
# The chosen dongle is saved in ~/.alpinewifi-adapter and handed to the Alpine machine.
# Run directly ("Check Wi-Fi hardware" shortcut) or source it (install-all.sh uses the functions).

[ -n "${MW_SETUP_DIR:-}" ] || . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

USB_ID_TABLE="$MW_SETUP_DIR/data/wifi-usb-ids.txt"
DRIVER_TABLE="$MW_SETUP_DIR/data/wifi-drivers.txt"
# dongles that first show up as a "driver CD" and switch to Wi-Fi when that CD is ejected
CDMODE_IDS="0bda:1a2b 0e8d:2870"

# ---------- 1. the Mac's own Wi-Fi ----------
# wifi_check_builtin  - sets MW_BUILTIN_STATE: missing | off | connected | on-idle | on-blind | unknown
#   plus MW_BUILTIN_DEV, MW_BUILTIN_SSID, MW_BUILTIN_SEEN (networks macOS sees), MW_BUILTIN_CARD
wifi_check_builtin() {
  local js json line power
  MW_BUILTIN_STATE=missing MW_BUILTIN_DEV="" MW_BUILTIN_SSID="" MW_BUILTIN_SEEN=0 MW_BUILTIN_CARD="" MW_BUILTIN_STATUS=""
  MW_BUILTIN_DEV=$(networksetup -listallhardwareports 2>/dev/null | awk '/^Hardware Port: (Wi-Fi|AirPort)$/ {getline; print $2; exit}')
  json=$(mktemp "${TMPDIR:-/tmp}/mw-airport.XXXXXX") || return 0
  with_timeout 30 system_profiler -json SPAirPortDataType > "$json" 2>/dev/null
  js='ObjC.import("Foundation");
  function run(argv) {
    var s = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
    if (!s) return "";
    var j; try { j = JSON.parse(s.js); } catch (e) { return ""; }
    var top = (j.SPAirPortDataType || [])[0] || {}, out = [];
    (top.spairport_airport_interfaces || []).forEach(function (i) {
      var name = i._name || "";
      if (!/^en[0-9]+$/.test(name)) return;
      var cur = i.spairport_current_network_information || {};
      var seen = (i.spairport_airport_other_local_wireless_networks || []).length;
      out.push([name, i.spairport_status_information || "", cur._name || "", seen,
                i.spairport_wireless_card_type || ""].join("\u001f"));
    });
    return out.join("\n");
  }'
  line=$(osascript -l JavaScript -e "$js" "$json" 2>/dev/null | head -1)
  rm -f "$json"
  if [ -n "$line" ]; then
    # fields are split by the "unit separator" character, which (unlike tab) keeps empty fields
    IFS=$'\x1f' read -r MW_BUILTIN_DEV MW_BUILTIN_STATUS MW_BUILTIN_SSID MW_BUILTIN_SEEN MW_BUILTIN_CARD <<< "$line"
  fi
  [ -n "$MW_BUILTIN_DEV" ] || { MW_BUILTIN_STATE=missing; return 0; }
  if [ -z "$line" ]; then        # macOS lists a Wi-Fi port but gave no details
    MW_BUILTIN_STATE=unknown
    case "$(networksetup -getairportpower "$MW_BUILTIN_DEV" 2>/dev/null)" in *": Off"*) MW_BUILTIN_STATE=off ;; esac
    log "built-in Wi-Fi: state=$MW_BUILTIN_STATE dev=$MW_BUILTIN_DEV (no details from System Information)"
    return 0
  fi
  case "$MW_BUILTIN_STATUS" in
    *disconnected*|*Disconnected*) MW_BUILTIN_STATE=on-idle ;;
    *connected*|*Connected*)       MW_BUILTIN_STATE=connected ;;
    *off*|*Off*)                   MW_BUILTIN_STATE=off ;;
    *)                             MW_BUILTIN_STATE=on-idle ;;
  esac
  power=$(networksetup -getairportpower "$MW_BUILTIN_DEV" 2>/dev/null)
  case "$power" in *": Off"*) MW_BUILTIN_STATE=off ;; esac
  case "$MW_BUILTIN_SEEN" in ''|*[!0-9]*) MW_BUILTIN_SEEN=0 ;; esac
  if [ "$MW_BUILTIN_STATE" = on-idle ] && [ "$MW_BUILTIN_SEEN" -eq 0 ]; then MW_BUILTIN_STATE=on-blind; fi
  log "built-in Wi-Fi: state=$MW_BUILTIN_STATE dev=$MW_BUILTIN_DEV status=$MW_BUILTIN_STATUS seen=$MW_BUILTIN_SEEN card=$MW_BUILTIN_CARD"
  return 0
}

wifi_report_builtin() {
  case "$MW_BUILTIN_STATE" in
    connected)
      ok "This Mac's own Wi-Fi works: connected${MW_BUILTIN_SSID:+ to \"$MW_BUILTIN_SSID\"} ($MW_BUILTIN_DEV)"
      why "You don't need the USB dongle setup - use the Wi-Fi menu in the menu bar." ;;
    on-idle)
      ok "This Mac's own Wi-Fi is on and sees $MW_BUILTIN_SEEN network(s), but isn't connected"
      why "It looks healthy: pick a network from the Wi-Fi menu in the menu bar. You probably don't need the dongle setup." ;;
    off)
      warn "This Mac's own Wi-Fi is switched OFF ($MW_BUILTIN_DEV)"
      why "Turn it on in the menu bar (Wi-Fi icon) or System Settings > Wi-Fi, and check whether it finds networks." ;;
    unknown)
      warn "This Mac has a Wi-Fi port ($MW_BUILTIN_DEV), but macOS didn't report whether it works"
      why "Click the Wi-Fi icon in the menu bar: if it lists networks, the built-in Wi-Fi works and you don't need this setup." ;;
    on-blind)
      warn "This Mac's own Wi-Fi is on, but sees no networks at all ($MW_BUILTIN_DEV)"
      why "If a phone or another computer nearby does see Wi-Fi, the Mac's Wi-Fi hardware (or its antenna) is probably faulty."
      why "Try once: restart the Mac, then check System Settings > Wi-Fi again." ;;
    *)
      warn "This Mac can't find its own Wi-Fi hardware at all"
      why "macOS shows no Wi-Fi card (System Information > Network > Wi-Fi has no interface). This usually means"
      why "the Wi-Fi chip has failed or isn't connected, so the Wi-Fi menu says 'Wi-Fi: No hardware installed'."
      why "That's exactly the case this setup is for: a USB Wi-Fi dongle, driven by a tiny Linux, gives the Mac Wi-Fi." ;;
  esac
}

# wifi_builtin_offer_on  - offers to switch the built-in Wi-Fi on (only when it's off). 0 = it now works.
wifi_builtin_offer_on() {
  [ "$MW_BUILTIN_STATE" = off ] || return 1
  ask_yes_no "Switch this Mac's own Wi-Fi on now to test it?" y 60 || return 1
  networksetup -setairportpower "$MW_BUILTIN_DEV" on 2>>"$MW_LOG" || { warn "Couldn't switch it on."; return 1; }
  info "Switched on - giving it 20 seconds to find networks..."
  sleep 20
  wifi_check_builtin
  wifi_report_builtin
  case "$MW_BUILTIN_STATE" in connected|on-idle) return 0 ;; esac
  return 1
}

# ---------- 2. USB Wi-Fi dongles ----------
# driver_info DRIVER FIELD  - field 2 chips, 3 firmware package, 4 rating, 5 bands, 6 note
driver_info() { awk -F'|' -v d="$1" -v f="$2" '$1 == d { print $f; exit }' "$DRIVER_TABLE" 2>/dev/null; }
id_drivers()  { awk -v id="$1" '$1 == id { printf "%s%s", sep, $2; sep = " " }' "$USB_ID_TABLE" 2>/dev/null; }

# wifi_scan_usb  - fills MW_USB_ID[], MW_USB_NAME[], MW_USB_DRV[], MW_USB_KIND[] (supported | cdmode | unknown-wifi)
wifi_scan_usb() {
  local id name vid pid drv kind
  MW_USB_ID=(); MW_USB_NAME=(); MW_USB_DRV=(); MW_USB_KIND=()
  while IFS=$'\t' read -r vid pid name; do
    [ -n "$vid" ] && [ -n "$pid" ] || continue
    id=$(printf '%04x:%04x' "$vid" "$pid")
    drv=$(id_drivers "$id"); kind=""
    if [ -n "$drv" ]; then kind=supported
    elif printf ' %s ' "$CDMODE_IDS" | grep -q " $id "; then kind=cdmode
    elif printf '%s' "$name" | grep -qiE '802\.11|wlan|wi-?fi|wireless (lan|network|adapter|usb)|dual ?band|(ac|ax)[0-9]{3,4}'; then kind=unknown-wifi
    fi
    [ -n "$kind" ] || continue
    MW_USB_ID[${#MW_USB_ID[@]}]=$id; MW_USB_NAME[${#MW_USB_NAME[@]}]=$name
    MW_USB_DRV[${#MW_USB_DRV[@]}]=$drv; MW_USB_KIND[${#MW_USB_KIND[@]}]=$kind
    log "USB Wi-Fi candidate: $id '$name' kind=$kind drivers='$drv'"
  done < <(ioreg -p IOUSB -l -w0 2>/dev/null | awk '
      function out() { if (v != "") { nm = n; if (vn != "" && index(n, vn) != 1) nm = vn " " n; print v "\t" p "\t" nm } }
      /\+-o / { out(); v = ""; p = ""; vn = ""; n = $0; sub(/.*\+-o /, "", n); sub(/@.*/, "", n) }
      /"idVendor" = /  { v = $NF }
      /"idProduct" = / { p = $NF }
      /"USB Product Name" = / { s = $0; sub(/.*"USB Product Name" = "/, "", s); sub(/"$/, "", s); n = s }
      /"USB Vendor Name" = /  { s = $0; sub(/.*"USB Vendor Name" = "/, "", s); sub(/"$/, "", s); vn = s }
      END { out() }')
}

wifi_report_usb() {
  local i n=${#MW_USB_ID[@]} d
  if [ "$n" -eq 0 ]; then
    warn "No USB Wi-Fi dongle found."
    why "Plug one in (directly, or through a powered hub) and run this check again."
    why "See docs/WIFI-ADAPTERS.md for which dongles work."
    return
  fi
  for (( i=0; i<n; i++ )); do
    case "${MW_USB_KIND[$i]}" in
      supported)
        d=${MW_USB_DRV[$i]%% *}
        ok "USB Wi-Fi dongle: ${MW_USB_NAME[$i]}  (USB ID ${MW_USB_ID[$i]})"
        why "Linux driver: $d - $(driver_info "$d" 2)"
        why "Bands: $(driver_info "$d" 5).  Rating: $(driver_info "$d" 4).  $(driver_info "$d" 6)"
        [ "$(driver_info "$d" 4)" = no ] && warn "This chip won't work out of the box: $(driver_info "$d" 3). See docs/WIFI-ADAPTERS.md." ;;
      cdmode)
        warn "USB device ${MW_USB_ID[$i]} (${MW_USB_NAME[$i]}) is a Wi-Fi dongle in 'driver CD' mode."
        why "It pretends to be a CD with Windows drivers. Ejecting that CD switches it to Wi-Fi mode." ;;
      unknown-wifi)
        warn "USB device ${MW_USB_ID[$i]} (${MW_USB_NAME[$i]}) looks like Wi-Fi, but Alpine's Linux has no driver for this ID."
        why "It won't work with this setup. Common examples: AIC8800-based 'AX300/AX900' dongles. See docs/WIFI-ADAPTERS.md." ;;
    esac
  done
}

# wifi_cdmode_help  - asks you to eject a dongle's "driver CD" so it switches to Wi-Fi mode, then looks again
wifi_cdmode_help() {
  pause_for_user "In Finder, eject the dongle's CD (it has a Windows driver on it; click the eject arrow next to it). Wait 5 seconds."
  wifi_scan_usb
}

# ---------- choosing the dongle (load_adapter / save_adapter are in lib.sh) ----------
# wifi_choose_adapter  - picks the dongle to use (asks only if there's more than one). 0 = chosen.
wifi_choose_adapter() {
  local i n pick idx=()
  n=${#MW_USB_ID[@]}
  for (( i=0; i<n; i++ )); do
    [ "${MW_USB_KIND[$i]}" = supported ] && [ "$(driver_info "${MW_USB_DRV[$i]%% *}" 4)" != no ] && idx[${#idx[@]}]=$i
  done
  [ ${#idx[@]} -eq 0 ] && return 1
  pick=${idx[0]}
  if [ ${#idx[@]} -gt 1 ]; then
    echo "          More than one usable dongle is plugged in:"
    for (( i=0; i<${#idx[@]}; i++ )); do echo "            $((i + 1))) ${MW_USB_NAME[${idx[$i]}]}  (${MW_USB_ID[${idx[$i]}]}, ${MW_USB_DRV[${idx[$i]}]%% *})"; done
    local a; read -r -t 120 -p "          Which one should Alpine use? [1] " a || a=1
    case "$a" in ''|*[!0-9]*) a=1 ;; esac
    [ "$a" -ge 1 ] && [ "$a" -le ${#idx[@]} ] || a=1
    pick=${idx[$((a - 1))]}
  fi
  ADAPTER_ID=${MW_USB_ID[$pick]} ADAPTER_DRIVER=${MW_USB_DRV[$pick]%% *} ADAPTER_NAME=${MW_USB_NAME[$pick]}
  save_adapter
  ok "Alpine will use: $ADAPTER_NAME ($ADAPTER_ID, driver $ADAPTER_DRIVER)"
}

# wifi_options  - the choices when the Mac's own Wi-Fi doesn't work
wifi_options() {
  echo
  printf '          %sYour options without the built-in Wi-Fi:%s\n' "$B" "$N"
  why "1. USB Wi-Fi dongle + this setup (Alpine drives it, the Mac gets its internet). Needs a dongle Linux supports."
  why "2. Phone USB tethering: iPhone works directly; Android works through muta (installed by this setup)."
  why "3. USB-C Ethernet adapter, or a small travel router in 'client/WISP' mode with an Ethernet cable."
  why "4. Repair: on Apple silicon Macs the Wi-Fi chip is part of the main board, so Apple fixes it by replacing the board."
  why "Details: docs/WIFI-ADAPTERS.md"
}

# apply_adapter_to_vm  - makes VMware hand the chosen dongle to the Alpine machine
apply_adapter_to_vm() {
  [ -f "$VMX" ] || return 0
  local want; want=$(adapter_vmx_value)
  [ "$(vmx_get usb.autoConnect.device0)" = "$want" ] && { ok "The Alpine machine is already set to use this dongle"; return 0; }
  local was_running=no
  vm_running && was_running=yes
  if [ "$was_running" = yes ]; then info "Stopping Alpine for a moment to hand it the new dongle..."; vm_stop || return 1; fi
  vmx_set usb.autoConnect.device0 "$want"
  ok "VMware will now give '$ADAPTER_NAME' to Alpine automatically"
  if [ "$was_running" = yes ]; then vm_start && info "Alpine is starting again."; fi
}

check_wifi_main() {
  step "1. Can this Mac use its own Wi-Fi?"
  wifi_check_builtin
  wifi_report_builtin
  if wifi_builtin_offer_on; then
    ok "The built-in Wi-Fi works after switching it on - you don't need the dongle setup."
    return 0
  fi
  case "$MW_BUILTIN_STATE" in connected|on-idle) ;; *) wifi_options ;; esac

  step "2. USB Wi-Fi dongle"
  wifi_scan_usb
  if printf '%s\n' "${MW_USB_KIND[@]}" | grep -qx cdmode; then
    wifi_report_usb
    wifi_cdmode_help
  fi
  wifi_report_usb
  if wifi_choose_adapter; then apply_adapter_to_vm
  else warn "No usable dongle chosen; Alpine keeps using: $ADAPTER_NAME ($ADAPTER_ID)"; fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  check_wifi_main
  echo; ok "Check finished. Details are in $MW_LOG"
fi
