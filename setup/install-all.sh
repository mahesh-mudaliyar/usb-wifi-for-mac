#!/bin/bash
# The one-click Mac Wi-Fi installer. Double-click "Install Mac Wi-Fi.command" to run it.
# It works out what's missing and only does that, so it's also the "repair" button:
#   - healthy Alpine machine already there -> reinstall the Mac side only (about 1 min)
#   - no machine but a backup exists       -> restore it (about 2 min) or build a new one
#   - nothing                              -> build a new machine unattended (about 5-25 min)
# Every step says what it does and has a time limit. Log: ~/Library/Logs/mac-wifi-install.log

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
. "$MW_SETUP_DIR/build-vm.sh"
. "$MW_SETUP_DIR/restore.sh"
. "$MW_SETUP_DIR/check-wifi.sh"

APP_SUPPORT="$HOME/Library/Application Support/Mac Wi-Fi"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.alpinewifi.autostart.plist"

alp_has_wlan()  { alp -- '[ -e /sys/class/net/wlan0 ]' 2>/dev/null; }
alp_ready()     { alp -- '[ -x /usr/local/bin/wifi-join ] && modinfo rtl8xxxu >/dev/null 2>&1' 2>/dev/null; }
mac_on_wifi()   { [ "$(route -n get default 2>/dev/null | awk '/gateway/{print $2}')" = "$ALPINE_IP" ]; }
fusion_network_ready() { [ -f "$VMNET_CONF" ] && grep -q '^answer VNET_1_HOSTONLY_SUBNET' "$VMNET_CONF"; }

intro() {
  clear 2>/dev/null
  cat <<EOF
${B}Mac Wi-Fi installer${N}

This sets up internet for this Mac through the small USB Wi-Fi adapter, with the
phone's USB tethering as an automatic backup. It installs or repairs:

  - VMware Fusion check, Homebrew tools, and muta (phone USB tethering)
  - a check of this Mac's own Wi-Fi and of your USB Wi-Fi dongle (is there a Linux driver?)
  - "Alpine WiFi": a tiny hidden Linux machine that drives the USB Wi-Fi dongle
  - the Mac services that switch between Wi-Fi and the phone by themselves
  - the shortcuts in ~/Desktop/Mac Wi-Fi

Before you start:
  - plug in the USB Wi-Fi adapter
  - make sure the Mac has some internet (phone tethering is fine)
  - have your Mac login password ready

Repairing takes about 1 minute; a brand-new setup takes about 5-25 minutes, mostly
waiting. You can leave it running: you'll get a notification when it's done or
needs you. Everything is logged to: $MW_LOG
EOF
  echo
  ask_yes_no "Start?" y || { echo "Nothing was changed."; exit 0; }
  log "===== installer started (macOS $(sw_vers -productVersion), user $USER) ====="
}

check_mac() {
  step "Check this Mac"
  [ "$(uname -m)" = arm64 ] || fail "This setup is for Apple silicon Macs (M1 or newer)." "The Alpine machine here is built for ARM."
  ok "Apple silicon Mac, macOS $(sw_vers -productVersion)"
  local free; free=$(df -k "$HOME" | awk 'NR==2 {print int($4 / 1048576)}')
  [ "$free" -ge 3 ] || fail "Only ${free} GB free disk space; about 3 GB is needed." "Free up some space and run the installer again."
  ok "${free} GB free disk space"
  if internet_ok; then ok "Internet is working"; else
    warn "This Mac has no internet right now. It's needed to download Alpine and the tools."
    why "Connect it any way you can: the phone's USB tethering, a cable, or a hotspot."
    notify "Mac Wi-Fi setup needs internet - connect the phone or a cable." Ping
    wait_until 600 "internet" "Still nothing - check the phone's USB tethering is on." internet_ok \
      || fail "No internet after 10 minutes." "Connect the Mac to the internet, then run the installer again."
    ok "Internet is working"
  fi
}

check_wifi_hardware() {
  step "This Mac's own Wi-Fi"
  why "First: if the built-in Wi-Fi works, you don't need any of this."
  wifi_check_builtin
  wifi_report_builtin
  if wifi_builtin_offer_on; then MW_BUILTIN_STATE=connected; fi
  case "$MW_BUILTIN_STATE" in
    connected|on-idle)
      ask_yes_no "Set up the USB dongle anyway (for example as a second Wi-Fi)?" n 120 \
        || { echo; ok "Nothing was changed. Use the Wi-Fi menu in the menu bar."; exit 0; } ;;
    *) wifi_options ;;
  esac

  step "USB Wi-Fi dongle"
  why "Alpine's Linux gets the dongle; it needs a Linux driver for that exact dongle (checked against $(grep -vc '^#' "$USB_ID_TABLE") known IDs)."
  wifi_scan_usb
  if printf '%s\n' "${MW_USB_KIND[@]}" | grep -qx cdmode; then wifi_report_usb; wifi_cdmode_help; fi
  wifi_report_usb
  if wifi_choose_adapter; then return; fi
  if [ -f "$ADAPTER_CONF" ] || [ -f "$VMX" ]; then
    warn "Keeping the dongle chosen before: $ADAPTER_NAME ($ADAPTER_ID). (While Alpine is using it, macOS may not list it.)"
  else
    warn "No usable USB Wi-Fi dongle is plugged in."
    why "You can still install now (the phone backup works) and plug a dongle in later,"
    why "then double-click 'Check Wi-Fi hardware' to hand it to Alpine."
    ask_yes_no "Continue without a dongle for now?" y 120 || { echo "Nothing was changed."; exit 0; }
  fi
}

check_fusion() {
  step "VMware Fusion (runs the hidden Alpine machine)"
  if [ ! -x "$VMRUN" ]; then
    warn "VMware Fusion isn't installed. It's free, but Broadcom requires a (free) account to download it."
    why "Opening the download page now. Install it into Applications, open it once, then come back here."
    open "https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware%20Fusion" 2>/dev/null
    notify "Please install VMware Fusion - the installer is waiting." Ping
    wait_until 1800 "VMware Fusion to be installed" "" test -x "$VMRUN" \
      || fail "VMware Fusion still isn't installed after 30 minutes." "Install it, then run the installer again."
  fi
  ok "VMware Fusion $(defaults read "$FUSION/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null) is installed"
  if ! fusion_network_ready; then
    pause_for_user "Open VMware Fusion once, accept its license and allow anything macOS asks for, then quit Fusion."
    wait_until 120 "VMware's network settings to appear" "" fusion_network_ready \
      || fail "VMware Fusion's network isn't set up yet." "Open VMware Fusion once, then run the installer again."
  fi
  ok "VMware Fusion has been set up"
}

brew_install() {   # brew_install pkg...
  local p missing=""
  for p in "$@"; do brew list --versions "$p" >/dev/null 2>&1 || missing="$missing $p"; done
  [ -z "$missing" ] && return 0
  info "Installing with Homebrew:$missing (up to 20 min)..."
  # shellcheck disable=SC2086
  with_timeout 1200 brew install $missing >> "$MW_LOG" 2>&1 \
    || fail "Homebrew couldn't install:$missing" "See the log. Try 'brew update' in Terminal, then run the installer again."
  ok "Installed:$missing"
}

check_tools() {
  step "Homebrew and muta (phone USB tethering)"
  if ! command -v brew >/dev/null; then
    warn "Homebrew (the standard Mac tool installer) is missing; it's needed for Rust and xorriso."
    ask_yes_no "Install Homebrew now with its official installer? (it asks for your password)" y \
      || fail "Homebrew is needed." "Install it from https://brew.sh, then run the installer again."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || fail "The Homebrew installer failed." "Install it from https://brew.sh, then run the installer again."
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)"
    command -v brew >/dev/null || fail "Homebrew still isn't available."
  fi
  ok "Homebrew is installed"
  if [ -x "$MUTA" ]; then ok "muta is installed ($("$MUTA" --version 2>/dev/null))"; else
    why "muta lets the Mac use an Android phone's USB tethering. It's built from source with Rust."
    command -v cargo >/dev/null || brew_install rust
    info "Building muta (2-10 min)..."
    with_timeout 1800 cargo install muta >> "$MW_LOG" 2>&1 \
      || fail "Building muta failed." "See the log, then run the installer again."
    [ -x "$MUTA" ] || fail "muta was built but isn't at $MUTA."
    ok "muta installed"
  fi
}

fix_vmware_network() {
  step "VMware's private Mac-only network"
  why "Alpine and the Mac talk over 'Private to my Mac' at $HOST_SUBNET (Mac $HOST_IP, Alpine $ALPINE_IP)."
  local cur; cur=$(awk '$2 == "VNET_1_HOSTONLY_SUBNET" {print $3}' "$VMNET_CONF")
  if [ "$cur" = "$HOST_SUBNET" ]; then ok "Already $HOST_SUBNET"; return; fi
  info "It's '$cur'; changing it to $HOST_SUBNET..."
  sudo -n cp "$VMNET_CONF" "$VMNET_CONF.before-mac-wifi" 2>/dev/null
  sudo -n sed -i '' -e "s/^answer VNET_1_HOSTONLY_SUBNET .*/answer VNET_1_HOSTONLY_SUBNET $HOST_SUBNET/" \
                    -e "s/^answer VNET_1_HOSTONLY_NETMASK .*/answer VNET_1_HOSTONLY_NETMASK 255.255.255.0/" "$VMNET_CONF" \
    || fail "Couldn't change VMware's network settings."
  local a
  for a in --configure --stop --start; do
    with_timeout 120 sudo -n "$VMNETCLI" "$a" >> "$MW_LOG" 2>&1 || fail "VMware's network didn't restart ($a)." "Restart the Mac, then run the installer again."
  done
  ok "VMware's private network is now $HOST_SUBNET"
}

pause_autostart() {
  step "Pause the automatic Wi-Fi machine start"
  why "So nothing restarts the Alpine machine while it's being checked or built. Wi-Fi keeps working."
  MW_WAS_DISABLED=no
  [ -f "$DISABLED_FLAG" ] && MW_WAS_DISABLED=yes
  if launchctl print "gui/$(id -u)/com.alpinewifi.autostart" >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/com.alpinewifi.autostart" 2>/dev/null
    # turned back on at the end (step "Mac services"), or here if anything fails before that
    add_cleanup "[ -f '$LAUNCH_AGENT' ] && launchctl bootstrap gui/$(id -u) '$LAUNCH_AGENT'"
    ok "Paused (it's turned back on at the end, or if anything fails)"
  else
    ok "Auto-start isn't installed yet - nothing to pause"
  fi
}

vm_healthy() {
  [ -f "$VMX" ] && [ -f "$VM_DIR/claude-key" ] || return 1
  [ -f "$SSHCFG" ] || render "$MW_SETUP_DIR/mac/sshcfg" "$SSHCFG"
  vm_start || return 1
  wait_until 150 "Alpine to answer" "" alp_up || return 1
  alp_ready
}

setup_vm() {
  step "The Alpine Wi-Fi machine"
  local p; p=$(build_phase)
  if [ -d "$VM_DIR" ] && [ "$p" != none ] && [ "$p" != "done" ]; then
    warn "A build was interrupted earlier (finished: phase '$p') - carrying on from there."
    brew_install xorriso; build_vm; return
  fi
  if [ -d "$VM_DIR" ]; then
    info "Found '$VM_NAME' - checking it works..."
    if vm_healthy; then ok "The Alpine machine is healthy - keeping it (repair mode)"; return; fi
    local aside; aside="$VM_DIR.old-$(date +%Y%m%d-%H%M%S)"
    warn "The machine doesn't work properly. Moving it aside (not deleting it): $(basename "$aside")"
    vm_stop
    mv "$VM_DIR" "$aside" || fail "Couldn't move the broken machine aside." "Quit VMware Fusion, then run the installer again."
  fi
  local newest; newest=$(list_backups | head -1)
  if [ -n "$newest" ]; then
    why "A backup from $(backup_date "$newest") exists. Restoring takes about 2 minutes;"
    why "building a new machine takes 5-25 minutes and you'd have to pick your Wi-Fi network again."
    if ask_yes_no "Restore the backup? (n = build a new machine)" y 120; then
      restore_vm
      info "Checking the restored machine..."
      if vm_healthy; then ok "The restored machine works"; return; fi
      warn "The restored machine doesn't work. Moving it aside and building a new one instead."
      vm_stop; mv "$VM_DIR" "$VM_DIR.restored-broken-$(date +%Y%m%d-%H%M%S)"
    fi
  fi
  brew_install xorriso
  build_vm
}

install_mac_services() {
  step "Mac services: phone tethering, Wi-Fi/phone switcher, auto-start"
  why "These run in the background: muta handles the phone, the switcher checks every 15 s"
  why "and picks Wi-Fi when it has internet, and auto-start keeps Alpine running hidden."
  local f
  for f in autostart-vm.sh wifi-failover.sh install-auto.sh update-switcher.sh; do
    cp "$MW_SETUP_DIR/mac/$f" "$VM_DIR/$f" || fail "Couldn't copy $f into the machine folder."
  done
  chmod 755 "$VM_DIR/autostart-vm.sh" "$VM_DIR/install-auto.sh" "$VM_DIR/update-switcher.sh"
  render "$MW_SETUP_DIR/mac/sshcfg" "$SSHCFG"
  info "Installing the background services (needs the Mac password)..."
  with_timeout 180 sudo -n sh "$VM_DIR/install-auto.sh" 2>&1 | tee -a "$MW_LOG" | sed 's/^/          /'
  [ "${PIPESTATUS[0]}" = 0 ] || fail "Installing the background services failed." "See the messages above and the log."
  sudo -n launchctl print system/com.alpinewifi.failover >/dev/null 2>&1 || fail "The Wi-Fi/phone switcher isn't running."
  ok "Phone tethering service and Wi-Fi/phone switcher installed"
  mkdir -p "$(dirname "$LAUNCH_AGENT")"
  render "$MW_SETUP_DIR/mac/com.alpinewifi.autostart.plist" "$LAUNCH_AGENT"
  launchctl bootout "gui/$(id -u)/com.alpinewifi.autostart" 2>/dev/null
  sleep 1
  launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT" 2>>"$MW_LOG" || fail "Couldn't turn on the auto-start."
  ok "Auto-start installed (keeps Alpine running hidden, checks every minute)"
}

install_shortcuts() {
  step "Shortcuts in ~/Desktop/Mac Wi-Fi"
  local f name stamp; stamp=$(date +%Y%m%d-%H%M%S)
  mkdir -p "$SHORTCUT_DIR"
  for f in "$MW_PROJECT_DIR"/[0-9]*.command "$MW_PROJECT_DIR/Install Mac Wi-Fi.command" "$MW_PROJECT_DIR/Check Wi-Fi hardware.command"; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    if [ -f "$SHORTCUT_DIR/$name" ] && ! cmp -s "$f" "$SHORTCUT_DIR/$name"; then
      mkdir -p "$SHORTCUT_DIR/old" && mv "$SHORTCUT_DIR/$name" "$SHORTCUT_DIR/old/$name.$stamp"
    fi
    cp "$f" "$SHORTCUT_DIR/$name" && chmod 755 "$SHORTCUT_DIR/$name"
  done
  # a copy of the installer itself, so the Desktop shortcuts (backup, reinstall) always find it
  if [ "$MW_PROJECT_DIR" != "$APP_SUPPORT" ]; then
    mkdir -p "$APP_SUPPORT"
    rsync -a --delete --exclude '.git' "$MW_PROJECT_DIR/" "$APP_SUPPORT/" 2>>"$MW_LOG" || warn "Couldn't copy the installer to $APP_SUPPORT"
  fi
  xattr -dr com.apple.quarantine "$SHORTCUT_DIR" "$APP_SUPPORT" 2>/dev/null
  ok "Shortcuts updated (older versions kept in $SHORTCUT_DIR/old)"
}

# explain_adapter  - says why Alpine has no Wi-Fi interface, based on what Alpine itself sees
explain_adapter() {
  local s; s=$(alp -- '/usr/local/bin/wifi-adapter-info 2>/dev/null | tail -1' 2>/dev/null)
  log "adapter state: $s"
  case "$s" in
    "ADAPTER firmware"*) warn "Alpine has a driver for the dongle, but its firmware file is missing (${s#ADAPTER firmware })."
                         why "Run the installer again with internet available, or see 'Firmware missing' in docs/WIFI-ADAPTERS.md." ;;
    "ADAPTER nodriver"*) warn "Alpine sees a USB device (${s#ADAPTER nodriver }) but has no Linux driver for it."
                         why "This dongle won't work with this setup - see docs/WIFI-ADAPTERS.md for ones that do." ;;
    "ADAPTER none"*)     warn "Alpine doesn't see any USB Wi-Fi dongle: VMware hasn't handed it over."
                         why "Check it's plugged in, then double-click 'Check Wi-Fi hardware' to hand it to Alpine." ;;
    *)                   warn "Couldn't ask Alpine about the dongle${s:+ ($s)}." ;;
  esac
}

resume_wifi() {
  step "Turn Wi-Fi on"
  if [ "$MW_WAS_DISABLED" = yes ]; then
    warn "Wi-Fi was turned off with shortcut 3 before you started."
    ask_yes_no "Turn Wi-Fi back on now?" y 60 || { ok "Left off. Use shortcut 1 to turn it on later."; MW_LEAVE_OFF=yes; return; }
  fi
  rm -f "$DISABLED_FLAG"
  vm_start || fail "VMware couldn't start Alpine." "Double-click '1 Start Wi-Fi' to see why."
  wait_until 150 "Alpine to answer" "Open VMware Fusion to see if it's stuck." alp_up || fail "Alpine isn't answering." "Double-click '0 Which internet am I on' and check the log."
  ok "Alpine is running (hidden)"
  if ! wait_until 60 "the USB Wi-Fi dongle inside Alpine" "" alp_has_wlan; then
    explain_adapter
    pause_for_user "Plug in the USB Wi-Fi dongle ($ADAPTER_NAME). If it's already in: unplug it, wait 5 s, and plug it back in."
    if ! wait_until 90 "the USB Wi-Fi dongle" "In VMware Fusion: Virtual Machine > USB > connect '$ADAPTER_NAME'." alp_has_wlan; then
      explain_adapter
      warn "Everything else is installed. Fix the dongle as described, then use '1 Start Wi-Fi'."
      MW_NO_ADAPTER=yes; return
    fi
  fi
  local s; s=$(alp -- '/usr/local/bin/wifi-adapter-info | tail -1' 2>/dev/null)
  ok "USB Wi-Fi dongle working inside Alpine (${s#ADAPTER ok })"
}

pick_network() {
  if [ "${MW_LEAVE_OFF:-no}" = yes ] || [ "${MW_NO_ADAPTER:-no}" = yes ]; then return; fi
  step "Wi-Fi network"
  local saved def=n
  saved=$(alp -- 'grep -c "^network=" /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null' 2>/dev/null | tr -dc 0-9)
  saved=${saved:-0}
  if [ "$saved" -eq 0 ]; then why "No Wi-Fi network is saved yet."; def=y
  else why "$saved Wi-Fi network(s) already saved; Alpine joins whichever is in range."; fi
  if ask_yes_no "Choose a Wi-Fi network now?" "$def" 90; then
    bash "$MW_PROJECT_DIR/2 Change Wi-Fi network.command"
  fi
  if wait_until 150 "the Mac to switch to Wi-Fi" "The switcher needs Wi-Fi with working internet; a hotel login page won't do." mac_on_wifi; then
    ok "The Mac is using Wi-Fi ($(alp -- "iw dev wlan0 link | sed -n 's/^[[:space:]]*SSID: //p'" 2>/dev/null))"
  else
    warn "The Mac isn't on Wi-Fi yet. It switches by itself once Wi-Fi has internet."
    why "Use '2 Change Wi-Fi network' to pick a network, and '0 Which internet am I on' to check."
  fi
}

finish() {
  echo
  printf '%s[%s] ==> All done%s\n' "$B" "$(_el)" "$N"; log "DONE"
  if internet_ok; then ok "Internet works (now via $(route -n get default 2>/dev/null | awk '/interface/{print $2}'))"
  else warn "No internet right now - see the notes above."; fi
  cat <<EOF

  Your shortcuts are in ~/Desktop/Mac Wi-Fi:
    0 Which internet am I on      1 Start Wi-Fi             2 Change Wi-Fi network
    3 Stop Wi-Fi and use phone    4 Use phone USB tethering 5 Switch from phone to Wi-Fi
    6 Back up Wi-Fi machine       Check Wi-Fi hardware (built-in Wi-Fi + which dongle)
    Install Mac Wi-Fi (run again any time to repair)

  Tip: once Wi-Fi works, double-click "6 Back up Wi-Fi machine" so a future
  reinstall takes 2 minutes instead of 20.
EOF
  notify "Mac Wi-Fi setup finished." Glass
}

main() {
  if [ "${MACWIFI_TEST:-0}" = 1 ]; then
    echo "MACWIFI_TEST=1 is for setup/build-vm.sh only; the full installer always sets up the real machine."; exit 1
  fi
  intro
  check_mac
  check_wifi_hardware
  sudo_start "The Mac password is needed to install the background services and adjust VMware's network."
  check_fusion
  check_tools
  fix_vmware_network
  pause_autostart
  setup_vm
  apply_adapter_to_vm
  install_mac_services
  install_shortcuts
  resume_wifi
  pick_network
  finish
}

main "$@"
