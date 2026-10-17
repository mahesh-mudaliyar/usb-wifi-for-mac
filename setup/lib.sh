#!/bin/bash
# Shared helpers for the Mac Wi-Fi installer. Source it, don't run it.
# Written for the bash that ships with macOS (3.2): no associative arrays, no mapfile.
# shellcheck disable=SC2034  # variables here are used by the scripts that source this file

# Homebrew's tools, even when Terminal's PATH doesn't include them
PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.cargo/bin:$PATH"

# ---------- names and places ----------
MW_SETUP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MW_PROJECT_DIR=$(cd "$MW_SETUP_DIR/.." && pwd)
VMS_DIR="$HOME/Virtual Machines.localized"
ISO_DIR="$VMS_DIR/VMWIsoImages"
FUSION="/Applications/VMware Fusion.app"
VMRUN="$FUSION/Contents/Library/vmrun"
VDISK="$FUSION/Contents/Library/vmware-vdiskmanager"
VMNETCLI="$FUSION/Contents/Library/vmnet-cli"
VMNET_CONF="/Library/Preferences/VMware Fusion/networking"
MUTA="$HOME/.cargo/bin/muta"
DISABLED_FLAG="$HOME/.alpinewifi-disabled"
BACKUP_DIR="$HOME/Mac Wi-Fi Backups"
SHORTCUT_DIR="$HOME/Desktop/Mac Wi-Fi"

ALPINE_VERSION=3.24.2
ALPINE_BRANCH=v${ALPINE_VERSION%.*}
ALPINE_ISO_NAME="alpine-standard-$ALPINE_VERSION-aarch64.iso"
ALPINE_ISO_URL="https://dl-cdn.alpinelinux.org/alpine/$ALPINE_BRANCH/releases/aarch64/$ALPINE_ISO_NAME"

HOST_IP=192.168.235.1          # the Mac's side of VMware's "Private to my Mac" network (vmnet1)
HOST_SUBNET=192.168.235.0

# MACWIFI_TEST=1 builds a separate test machine that never touches the real one.
if [ "${MACWIFI_TEST:-0}" = 1 ]; then
  VM_NAME="Alpine WiFi Test"; ALPINE_IP=192.168.235.101
else
  VM_NAME="Alpine WiFi";      ALPINE_IP=192.168.235.100
fi
VM_DIR="$VMS_DIR/$VM_NAME.vmwarevm"
VMX="$VM_DIR/$VM_NAME.vmx"
SSHCFG="$VM_DIR/sshcfg"

# ---------- output and logging ----------
MW_LOG="${MW_LOG:-$HOME/Library/Logs/mac-wifi-install.log}"
mkdir -p "$(dirname "$MW_LOG")"
MW_START=$(date +%s)
MW_STEP=""
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'; else B=; G=; Y=; R=; N=; fi

fmt_dur() { local s=$1; if [ "$s" -ge 60 ]; then printf '%dm%02ds' $((s/60)) $((s%60)); else printf '%ds' "$s"; fi; }
_el()  { local s=$(( $(date +%s) - MW_START )); printf '%02d:%02d' $((s/60)) $((s%60)); }
log()  { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$MW_LOG"; }
step() { MW_STEP="$*"; echo; printf '%s[%s] ==> %s%s\n' "$B" "$(_el)" "$*" "$N"; log "STEP $*"; }
why()  { printf '          %s\n' "$*"; log "  $*"; }
ok()   { printf '[%s] %sOK%s    %s\n' "$(_el)" "$G" "$N" "$*"; log "OK $*"; }
info() { printf '[%s] ...   %s\n' "$(_el)" "$*"; log "... $*"; }
warn() { printf '[%s] %sNOTE%s  %s\n' "$(_el)" "$Y" "$N" "$*"; log "NOTE $*"; }

# notify "message" [sound]   - macOS notification; never fails
notify() {
  osascript -e 'on run argv' \
            -e 'display notification (item 1 of argv) with title "Mac Wi-Fi Setup" sound name (item 2 of argv)' \
            -e 'end run' "$1" "${2:-Glass}" >/dev/null 2>&1 || true
}

# fail "what went wrong" ["what to do"]   - explains, notifies, and exits (cleanup runs via the EXIT trap)
fail() {
  MW_FAILED=1
  echo
  printf '[%s] %sPROBLEM%s %s\n' "$(_el)" "$R" "$N" "$1"; log "PROBLEM $1"
  [ -n "${2:-}" ] && { printf '          What to do: %s\n' "$2"; log "  todo: $2"; }
  [ -n "$MW_STEP" ] && printf '          (Step: %s)\n' "$MW_STEP"
  printf '          Full log: %s\n' "$MW_LOG"
  printf '          It is safe to run the installer again - finished steps are skipped.\n'
  notify "Problem: $1" Basso
  exit 1
}

# ---------- timeouts and waiting ----------
# with_timeout SECS cmd args...  - runs cmd; stops it (and anything it started) after SECS.
# Returns cmd's exit code, or 124 on timeout. Don't use it for commands that read the keyboard.
with_timeout() {
  local secs=$1; shift
  perl -e '
    use POSIX ":sys_wait_h";
    my $t = shift @ARGV;
    my $pid = fork; die "fork failed\n" unless defined $pid;
    if ($pid == 0) { setpgrp(0, 0); exec @ARGV or exit 127; }
    my $stop = sub {   # polite stop, up to 2 s, then force - for everything it started
      kill "TERM", -$pid;
      for (1 .. 20) { last if waitpid($pid, WNOHANG) > 0; select(undef, undef, undef, 0.1); }
      kill "KILL", -$pid; waitpid($pid, 0);
    };
    $SIG{INT}  = sub { $stop->(); exit 130 };
    $SIG{TERM} = sub { $stop->(); exit 143 };
    $SIG{ALRM} = sub { $stop->(); exit 124 };
    alarm $t;
    waitpid($pid, 0);
    alarm 0;
    exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
  ' "$secs" "$@"
}

# wait_until SECS "what" "hint shown halfway (or empty)" check-cmd args...
# Re-runs check-cmd every 3 s until it succeeds (0) or SECS pass (1). Prints progress every 30 s.
wait_until() {
  local secs=$1 what=$2 hint=$3; shift 3
  local start now el next=30 hinted=no
  start=$(date +%s)
  "$@" >/dev/null 2>&1 && return 0
  info "Waiting for $what (up to $(fmt_dur "$secs"))..."
  while :; do
    sleep 3
    "$@" >/dev/null 2>&1 && return 0
    now=$(date +%s); el=$((now - start))
    [ "$el" -ge "$secs" ] && return 1
    if [ "$el" -ge "$next" ]; then info "still waiting for $what - $(fmt_dur "$el") of $(fmt_dur "$secs")"; next=$((next + 30)); fi
    if [ "$hinted" = no ] && [ -n "$hint" ] && [ "$el" -ge $((secs / 2)) ]; then warn "$hint"; hinted=yes; fi
  done
}

# ---------- questions ----------
# ask_yes_no "question" y|n [timeout-seconds]  - Return/timeout picks the default. 0 = yes.
ask_yes_no() {
  local q=$1 def=$2 t=${3:-0} ans hint
  [ "$def" = y ] && hint="Y/n" || hint="y/N"
  [ "$t" -gt 0 ] && hint="$hint, $(fmt_dur "$t") = ${def}"
  while :; do
    ans=""
    if [ "$t" -gt 0 ]; then
      read -r -t "$t" -p "          $q [$hint] " ans || { echo; ans=$def; }
    else
      read -r -p "          $q [$hint] " ans || ans=$def
    fi
    [ -z "$ans" ] && ans=$def
    log "  asked: $q -> $ans"
    case "$ans" in [Yy]*) return 0 ;; [Nn]*) return 1 ;; esac
    echo "          Please type y or n."
  done
}

# pause_for_user "what to do"  - notifies and waits for Return.
pause_for_user() {
  notify "Action needed: $1" Ping
  printf '\n          %s>>> %s%s\n' "$B" "$1" "$N"; log "WAIT USER $1"
  read -r -p "          Press Return when done. " _ || true
}

# ---------- cleanup on exit ----------
MW_CLEANUPS=()
add_cleanup() { MW_CLEANUPS[${#MW_CLEANUPS[@]}]="$1"; }
_mw_on_exit() {
  local i
  for (( i=${#MW_CLEANUPS[@]}-1; i>=0; i-- )); do eval "${MW_CLEANUPS[$i]}" >/dev/null 2>&1 || true; done
  if [ "${MW_FAILED:-0}" = 1 ]; then
    echo; echo "---- last lines of the log ----"; tail -20 "$MW_LOG" 2>/dev/null | sed 's/^/  /'
  fi
}
trap _mw_on_exit EXIT
trap 'echo; MW_STEP="stopped by you (Ctrl-C)"; fail "Stopped by you (Ctrl-C)." "Run the installer again whenever you are ready."' INT

# ---------- sudo ----------
# sudo_start "why it's needed"  - asks for the Mac password once and keeps it fresh while we run.
sudo_start() {
  sudo -n true 2>/dev/null || { why "$1"; why "Type your Mac login password (nothing shows while you type)."; }
  sudo -v || fail "The Mac password wasn't accepted." "Run the installer again and type your Mac login password."
  ( while kill -0 $$ 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 50; done ) &
  add_cleanup "kill $! 2>/dev/null"
}

# ---------- VMware and Alpine ----------
vm_running() { [ -x "$VMRUN" ] && "$VMRUN" list 2>/dev/null | grep -qxF "$VMX"; }

# alp [-o HostName=IP] -- remote-command   - SSH to the Alpine machine with a short connect timeout
alp() {
  local opts=()
  while [ "$1" != "--" ] && [ $# -gt 0 ]; do opts[${#opts[@]}]=$1; shift; done
  [ "$1" = "--" ] && shift
  ssh -n -F "$SSHCFG" -o ConnectTimeout=4 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 ${opts[@]+"${opts[@]}"} alp "$@"
}
alp_up() { alp "$@" -- true 2>/dev/null; }

# lease_ip MAC  - newest DHCP address VMware's NAT network gave this MAC address
lease_ip() {
  awk -v mac="$(echo "$1" | tr 'A-F' 'a-f')" '
    /^lease /             { ip = $2 }
    /hardware ethernet/   { m = $3; sub(";", "", m); if (m == mac) found = ip }
    END                   { if (found != "") print found }
  ' /var/db/vmware/vmnet-dhcpd-vmnet8.leases 2>/dev/null
}

internet_ok() { curl -s -o /dev/null --max-time 6 https://www.apple.com || curl -s -o /dev/null --max-time 6 https://1.1.1.1; }

# ---------- the USB Wi-Fi dongle Alpine uses ----------
# Saved in ~/.alpinewifi-adapter (ID=, DRIVER=, NAME= lines) by check-wifi.sh.
# Without that file: the RTL8188EU this setup was first built for.
ADAPTER_CONF="$HOME/.alpinewifi-adapter"
load_adapter() {
  ADAPTER_ID=0bda:8179 ADAPTER_DRIVER=rtl8xxxu ADAPTER_NAME="Realtek 802.11n NIC (RTL8188EU)"
  [ -f "$ADAPTER_CONF" ] || return 0
  local id drv name
  id=$(sed -n 's/^ID=//p' "$ADAPTER_CONF" | head -1)
  drv=$(sed -n 's/^DRIVER=//p' "$ADAPTER_CONF" | head -1)
  name=$(sed -n 's/^NAME=//p' "$ADAPTER_CONF" | head -1)
  if printf '%s' "$id" | grep -qE '^[0-9a-f]{4}:[0-9a-f]{4}$' && printf '%s' "$drv" | grep -qE '^[a-z0-9_]+$'; then
    ADAPTER_ID=$id ADAPTER_DRIVER=$drv ADAPTER_NAME=${name:-$id}
  else
    log "ignored a damaged $ADAPTER_CONF"
  fi
}
save_adapter() { printf 'ID=%s\nDRIVER=%s\nNAME=%s\n' "$ADAPTER_ID" "$ADAPTER_DRIVER" "$ADAPTER_NAME" > "$ADAPTER_CONF"; }
adapter_vmx_value() { printf 'vid:0x%s pid:0x%s' "${ADAPTER_ID%%:*}" "${ADAPTER_ID##*:}"; }
load_adapter

# make_alpine_bundle DIR  - puts install.sh + files/ (with this machine's address and dongle) in DIR
make_alpine_bundle() {
  mkdir -p "$1/files" || return 1
  cp "$MW_SETUP_DIR/alpine/install.sh" "$1/" && cp "$MW_SETUP_DIR/alpine/files/"* "$1/files/" || return 1
  cp "$MW_SETUP_DIR/data/wifi-drivers.txt" "$1/files/" || return 1
  printf 'ALPINE_IP=%s\nHOST_NET=%s/24\nADAPTER_ID=%s\nADAPTER_DRIVER=%s\n' \
    "$ALPINE_IP" "$HOST_SUBNET" "$ADAPTER_ID" "$ADAPTER_DRIVER" > "$1/files/alpinewifi.env"
  chmod 755 "$1/install.sh" "$1/files/"wifi-*
}

# vm_start  - starts the machine with no window (closes Fusion's window again if it wasn't open)
vm_start() {
  local gui=no out
  vm_running && return 0
  # clear a lock left behind by a crash or restart
  if ! pgrep -f "Contents/Library/vmware-vmx" >/dev/null && [ -d "$VMX.lck" ]; then
    mkdir -p "$VM_DIR/old" && mv "$VMX.lck" "$VM_DIR/old/lock-$(date +%s)" && log "cleared a stale VM lock"
  fi
  pgrep -x "VMware Fusion" >/dev/null && gui=yes
  out=$(with_timeout 120 "$VMRUN" -T fusion start "$VMX" nogui 2>&1)
  sleep 6
  [ "$gui" = no ] && pkill -x "VMware Fusion" 2>/dev/null
  vm_running && return 0
  log "vmrun start: $out"
  # VMware writes the real reason (e.g. a settings problem) to the machine's own log
  local why_vm; why_vm=$(grep -A1 'Msg_Post: Error' "$VM_DIR/vmware.log" 2>/dev/null | tail -1 | sed 's/.*\] //')
  [ -n "$why_vm" ] && warn "VMware says: $why_vm"
  return 1
}

# vm_stop  - asks Alpine to shut down over SSH (up to 45 s), then forces it off.
# (VMware's own "soft" stop needs VMware Tools, which Alpine doesn't have.)
vm_stopped() { ! vm_running; }
vm_stop() {
  vm_running || return 0
  alp -- poweroff >/dev/null 2>&1
  wait_until 45 "Alpine to shut down" "" vm_stopped && return 0
  info "Alpine didn't shut down by itself - switching it off"
  with_timeout 30 "$VMRUN" -T fusion stop "$VMX" hard >/dev/null 2>&1
  vm_stopped
}

# vmx_set KEY VALUE  - sets one line in the .vmx (only while the machine is off)
vmx_set() {
  local t; t=$(mktemp "$VM_DIR/.vmx.XXXXXX") || return 1
  awk -v k="$1 = " 'index($0, k) != 1' "$VMX" > "$t" && printf '%s = "%s"\n' "$1" "$2" >> "$t" && mv "$t" "$VMX"
}
vmx_get() { awk -v k="$1 = " 'index($0, k) == 1 { v = substr($0, length(k) + 1); gsub(/"/, "", v); print v }' "$VMX" 2>/dev/null; }

# render SRC DEST  - copies a template, filling in the __PLACEHOLDERS__
render() {
  sed -e "s|__USER_HOME__|$HOME|g" -e "s|__VM_DIR__|$VM_DIR|g" -e "s|__ALPINE_IP__|$ALPINE_IP|g" \
      -e "s|__HOST_IP__|$HOST_IP|g" "$1" > "$2"
}
