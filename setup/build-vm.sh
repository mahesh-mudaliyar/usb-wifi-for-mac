#!/bin/bash
# Builds the Alpine Wi-Fi virtual machine from nothing, with no questions asked.
#   Prepare  (Mac):    download Alpine, make an SSH key, add our auto-installer to the Alpine CD,
#                      create the virtual machine (NAT network, so Alpine can download packages)
#   Phase 1 (Alpine):  install Alpine onto the virtual disk, then power off
#   Phase 2 (Alpine):  first boot from disk: Wi-Fi driver firmware + router setup, then power off
#   Phase 3 (Mac):     switch to the private Mac-only network, start, and check everything
# Safe to run again: it carries on from the last finished phase (".build-phase" in the VM folder).
# MACWIFI_TEST=1 builds a separate "Alpine WiFi Test" machine at .101 and never touches the real one.
# Run directly, or from install-all.sh (which sources this file and calls build_vm).

[ -n "${MW_SETUP_DIR:-}" ] || . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

PHASE1_LIMIT=1500   # 25 min: boot the CD + setup-alpine (which has its own 20 min limit) + copy
PHASE2_LIMIT=1200   # 20 min: package downloads on a slow connection
PHASE3_LIMIT=240    #  4 min: boot and answer on the private network

build_phase()     { cat "$VM_DIR/.build-phase" 2>/dev/null || echo none; }
set_build_phase() { echo "$1" > "$VM_DIR/.build-phase"; }

get_iso() {
  local iso="$ISO_DIR/$ALPINE_ISO_NAME" want have
  mkdir -p "$ISO_DIR"
  want=$(with_timeout 30 curl -fsS "$ALPINE_ISO_URL.sha256" 2>/dev/null | awk '{print $1}')
  [ -z "$want" ] && want=$(awk '{print $1}' "$iso.sha256" 2>/dev/null)
  [ -n "$want" ] || fail "Couldn't get the Alpine download checksum." "Check the Mac's internet, then run the installer again."
  echo "$want  $ALPINE_ISO_NAME" > "$iso.sha256"
  if [ -f "$iso" ]; then
    have=$(shasum -a 256 "$iso" | awk '{print $1}')
    [ "$have" = "$want" ] && { ok "Alpine $ALPINE_VERSION CD already downloaded (checksum OK)"; return 0; }
    warn "The saved Alpine CD is damaged or old - downloading it again"; rm -f "$iso"
  fi
  info "Downloading Alpine $ALPINE_VERSION (about 380 MB, up to 30 min; it resumes if interrupted)..."
  local n
  for n in 1 2 3; do
    with_timeout 1800 curl -fL --retry 3 --retry-delay 5 -C - --progress-bar -o "$iso.part" "$ALPINE_ISO_URL" && break
    warn "Download interrupted (try $n of 3)"; sleep 5
  done
  have=$(shasum -a 256 "$iso.part" 2>/dev/null | awk '{print $1}')
  if [ "$have" != "$want" ]; then
    rm -f "$iso.part"
    fail "The Alpine download didn't finish or is damaged." "Check the internet connection and run the installer again."
  fi
  mv "$iso.part" "$iso"
  ok "Alpine $ALPINE_VERSION downloaded and checked"
}

make_key() {
  if [ -f "$VM_DIR/claude-key" ] && [ -f "$VM_DIR/claude-key.pub" ]; then ok "SSH key already there"; return; fi
  ssh-keygen -q -t ed25519 -N "" -C "mac-wifi@$(hostname -s)" -f "$VM_DIR/claude-key" || fail "Couldn't create the SSH key."
  chmod 600 "$VM_DIR/claude-key"
  ok "Created the key the Mac uses to log in to Alpine"
}

make_installer_cd() {
  local stage tz key
  stage=$(mktemp -d "${TMPDIR:-/tmp}/alpinewifi-ovl.XXXXXX") || fail "Couldn't make a temporary folder."
  add_cleanup "rm -rf '$stage'"
  mkdir -p "$stage/etc/local.d" "$stage/etc/runlevels/default" "$stage/etc/apk" "$stage/etc/alpinewifi/setup"
  cp "$MW_SETUP_DIR/alpine/auto/alpinewifi-auto.start" "$stage/etc/local.d/"
  cp "$MW_SETUP_DIR/alpine/auto/alpinewifi-firstboot.start" "$stage/etc/alpinewifi/"
  chmod 755 "$stage/etc/local.d/alpinewifi-auto.start" "$stage/etc/alpinewifi/alpinewifi-firstboot.start"
  ln -s /etc/init.d/local "$stage/etc/runlevels/default/local"
  : > "$stage/etc/.default_boot_services"
  echo alpine-base > "$stage/etc/apk/world"
  tz=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||'); [ -n "$tz" ] || tz=UTC
  key=$(cat "$VM_DIR/claude-key.pub")
  sed -e "s|__TIMEZONE__|$tz|" -e "s|__ROOTSSHKEY__|$key|" "$MW_SETUP_DIR/alpine/auto/answers.tmpl" > "$stage/etc/alpinewifi/answers"
  cp "$VM_DIR/claude-key.pub" "$stage/etc/alpinewifi/key.pub"
  make_alpine_bundle "$stage/etc/alpinewifi/setup" || fail "Couldn't collect the Alpine setup files."
  COPYFILE_DISABLE=1 tar --format ustar --uid 0 --gid 0 --uname root --gname root \
    -czf "$stage/alpinewifi.apkovl.tar.gz" -C "$stage" etc || fail "Couldn't pack the auto-installer."
  rm -f "$VM_DIR/installer.iso"
  with_timeout 300 xorriso -indev "$ISO_DIR/$ALPINE_ISO_NAME" -outdev "$VM_DIR/installer.iso" \
    -map "$stage/alpinewifi.apkovl.tar.gz" /alpinewifi.apkovl.tar.gz -boot_image any replay >> "$MW_LOG" 2>&1 \
    || fail "Couldn't add the auto-installer to the Alpine CD (xorriso)." "See the log; make sure 'brew install xorriso' worked."
  ok "Alpine CD prepared with the auto-installer (timezone $tz)"
}

write_vmx() {
  local mac usb=""
  mac=$(printf '00:50:56:%02x:%02x:%02x' $((RANDOM % 64)) $((RANDOM % 256)) $((RANDOM % 256)))
  [ "${MACWIFI_TEST:-0}" = 1 ] || usb="usb.autoConnect.device0 = \"$ADAPTER_USB_ID\""
  cat > "$VMX" <<EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "22"
displayName = "$VM_NAME"
guestOS = "arm-other6xlinux-64"
firmware = "efi"
memsize = "512"
numvcpus = "2"
nvme0.present = "TRUE"
nvme0:0.present = "TRUE"
nvme0:0.fileName = "$VM_NAME.vmdk"
sata0.present = "TRUE"
sata0:1.present = "TRUE"
sata0:1.deviceType = "cdrom-image"
sata0:1.fileName = "installer.iso"
sata0:1.startConnected = "TRUE"
ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "vmxnet3"
ethernet0.addressType = "static"
ethernet0.address = "$mac"
ethernet0.linkStatePropagation.enable = "FALSE"
usb.present = "TRUE"
ehci.present = "FALSE"
usb_xhci.present = "TRUE"
$usb
tools.syncTime = "TRUE"
rtc.diffFromUTC = "0"
vmci0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
mks.enable3d = "FALSE"
uuid.action = "create"
msg.autoAnswer = "TRUE"
EOF
  ok "Virtual machine settings written (network: NAT for setup, address $mac)"
}

make_disk() {
  [ -f "$VM_DIR/$VM_NAME.vmdk" ] && rm -f "$VM_DIR/$VM_NAME.vmdk"
  with_timeout 60 "$VDISK" -c -s 2GB -a lsilogic -t 0 "$VM_DIR/$VM_NAME.vmdk" >> "$MW_LOG" 2>&1 \
    || fail "Couldn't create the virtual disk." "See the log."
  ok "2 GB virtual disk created"
}

# show_guest_lines TEXT  - prints Alpine's messages, without terminal codes, progress bars or blank lines
show_guest_lines() {
  printf '%s\n' "$1" | LC_ALL=C sed -E $'s/\x1b\\[[0-9;]*[A-Za-z]//g; s/\x1b[78]//g' | tr '\r' '\n' |
    grep -vE '^[[:space:]]*$|\[fetch |[0-9]+%[[:space:]]' |
    sed 's/^[0-9-]* [0-9:]* //; s/ boot=[0-9a-f-]*$//; s/^/          alpine| /'
}

# watch_phase N LIMIT GUEST-LOG
# Starts the machine (on VMware's NAT network) and follows its progress until it powers itself off.
# Progress is read over SSH from the log Alpine writes; the address comes from VMware's DHCP leases.
# Only markers from the current boot count (they carry Linux's boot id), so old logs can't fool it.
watch_phase() {
  local n=$1 limit=$2 glog=$3 start now el seen=0 next=30 hinted=no done=no contact=no
  local ip out boot total new mac
  mac=$(vmx_get ethernet0.address)
  vm_start || fail "VMware couldn't start '$VM_NAME'." "Open VMware Fusion once (allow anything it asks for), then run the installer again."
  start=$(date +%s)
  info "Machine started. Messages from inside Alpine appear below as 'alpine|'."
  while :; do
    sleep 5
    now=$(date +%s); el=$((now - start))
    ip=$(lease_ip "$mac")
    out=""
    # only complete lines are fetched (a progress bar without a line end waits until it's finished)
    [ -n "$ip" ] && out=$(alp -o HostName="$ip" -- \
      "cat /proc/sys/kernel/random/boot_id; t=\$(wc -l < $glog 2>/dev/null) || t=0; echo \$t;
       [ \"\$t\" -gt $seen ] && sed -n \"$((seen + 1)),\${t}p\" $glog; true" 2>/dev/null)
    if [ -n "$out" ]; then
      [ "$contact" = no ] && { contact=yes; ok "Connected to Alpine at $ip"; }
      boot=$(printf '%s\n' "$out" | sed -n 1p)
      total=$(printf '%s\n' "$out" | sed -n 2p | tr -dc 0-9); total=${total:-0}
      new=$(printf '%s\n' "$out" | sed -n '3,$p')
      if [ "$total" -lt "$seen" ]; then seen=0; continue; fi   # the log was started again
      if [ -n "$new" ]; then
        show_guest_lines "$new"
        printf '%s\n' "$new" >> "$MW_LOG"
        seen=$total
        next=$((el + 30))
        case "$new" in *"PHASE$n DONE boot=$boot"*) done=yes ;; esac
        case "$new" in *"PHASE$n FAILED"*"boot=$boot"*)
          fail "Phase $n failed inside Alpine: $(printf '%s\n' "$new" | grep "PHASE$n FAILED" | tail -1 | sed "s/.*PHASE$n FAILED: //; s/ boot=.*//")" \
               "Open VMware Fusion to look at the '$VM_NAME' window, then run the installer again." ;;
        esac
      fi
    fi
    if ! vm_running; then
      if [ "$done" = yes ]; then ok "Phase $n finished ($(fmt_dur "$el"))"
      else warn "The machine switched off before it could report back; the next step checks the result."; fi
      return 0
    fi
    [ "$el" -ge "$limit" ] && fail "Phase $n took longer than $(fmt_dur "$limit")." \
      "Open VMware Fusion and look at the '$VM_NAME' window to see where it stopped. The machine was left running."
    [ "$contact" = no ] && [ "$el" -ge 480 ] && fail "Couldn't reach Alpine during phase $n for 8 minutes." \
      "Open VMware Fusion and look at the '$VM_NAME' window (it may be stuck at boot), then run the installer again."
    if [ "$el" -ge "$next" ]; then info "working... $(fmt_dur "$el") (limit $(fmt_dur "$limit"))"; next=$((el + 30)); fi
    if [ "$hinted" = no ] && [ "$el" -ge $((limit / 2)) ]; then
      warn "This is taking a while. To watch it, open VMware Fusion and click the '$VM_NAME' window."
      notify "Alpine setup phase $n is still running - open VMware Fusion to watch." Ping; hinted=yes
    fi
  done
}

phase3_finish() {
  vmx_set ethernet0.connectionType hostonly
  vmx_set sata0:1.startConnected FALSE
  vmx_set sata0:1.present FALSE
  vmx_set memsize 192
  vmx_set numvcpus 1
  vm_start || fail "VMware couldn't start '$VM_NAME'." "Open VMware Fusion once, then run the installer again."
  wait_until "$PHASE3_LIMIT" "Alpine to answer at $ALPINE_IP" \
    "Still booting? Open VMware Fusion and look at the '$VM_NAME' window." alp_up \
    || fail "Alpine didn't answer at $ALPINE_IP after $(fmt_dur "$PHASE3_LIMIT")." \
            "Check VMware's private network is $HOST_SUBNET (the installer sets it), then run the installer again."
  ok "Alpine answers on the private Mac network ($ALPINE_IP)"
  alpine_check
  if [ "$MW_MISSING" != "" ]; then
    info "Not everything is running yet (missing:$MW_MISSING) - restarting Alpine's services..."
    alp -- 'rc-update -u >/dev/null 2>&1; openrc default >/dev/null 2>&1' 2>/dev/null
    alpine_check
  fi
  if [ "$MW_MISSING" = "" ]; then
    ok "Checked inside Alpine: Wi-Fi driver, Realtek firmware, NAT, forwarding, keepalive, helpers"; return 0
  fi
  warn "Alpine is still missing:$MW_MISSING"
  return 1
}

# alpine_check  - sets MW_MISSING to what's missing inside Alpine ("" = all good); retries for 30 s
alpine_check() {
  local res tries
  for tries in 1 2 3 4 5 6; do     # services may still be starting just after SSH answers
    # shellcheck disable=SC2016  # runs inside Alpine
    res=$(alp -- 'f=""; modinfo rtl8xxxu >/dev/null 2>&1 || f="$f driver";
      ls /lib/firmware/rtlwifi/rtl8188eufw.bin* >/dev/null 2>&1 || f="$f firmware";
      iptables -t nat -C POSTROUTING -o wlan0 -j MASQUERADE 2>/dev/null || f="$f NAT";
      [ "$(cat /proc/sys/net/ipv4/ip_forward)" = 1 ] || f="$f forwarding";
      grep -q wifi-keepalive /etc/crontabs/root || f="$f keepalive";
      for c in wifi-join wifi-scan-list wifi-keepalive; do [ -x /usr/local/bin/$c ] || f="$f $c"; done;
      [ -e /etc/local.d/alpinewifi-firstboot.start ] && f="$f setup-unfinished";
      echo "missing:$f"' 2>&1)
    [ "$res" = "missing:" ] && break
    sleep 5
  done
  log "Alpine check: $res (after $tries tries)"
  case "$res" in
    missing:*) MW_MISSING=${res#missing:} ;;
    *)         MW_MISSING=" (couldn't check: $res)" ;;
  esac
}

# redo_phase2  - puts the phase-2 script back so the next start repeats the Wi-Fi/router setup
redo_phase2() {
  ssh -F "$SSHCFG" -o ConnectTimeout=5 alp \
    'cat > /etc/local.d/alpinewifi-firstboot.start && chmod 755 /etc/local.d/alpinewifi-firstboot.start' \
    < "$MW_SETUP_DIR/alpine/auto/alpinewifi-firstboot.start" 2>>"$MW_LOG" || return 1
  vm_stop && set_build_phase 1
}

build_vm() {
  step "Build the Alpine Wi-Fi machine${MACWIFI_TEST:+ (TEST: $VM_NAME)}"
  why "Alpine is a tiny Linux that drives the USB Wi-Fi adapter and shares its internet with the Mac."
  why "It installs by itself in 3 phases (about 5-25 min in total, mostly downloads); you don't need to type anything."
  [ -x "$VMRUN" ] || fail "VMware Fusion isn't installed."
  command -v xorriso >/dev/null || fail "xorriso is missing." "Run: brew install xorriso"
  local p; p=$(build_phase)
  if [ -d "$VM_DIR" ] && [ "$p" = none ]; then
    fail "'$VM_DIR' already exists and wasn't made by this builder." "Move it somewhere else first (the installer does this for you)."
  fi
  if [ "$p" = "done" ]; then ok "Already built"; return 0; fi
  mkdir -p "$VM_DIR" || fail "Couldn't create $VM_DIR"
  render "$MW_SETUP_DIR/mac/sshcfg" "$SSHCFG"
  vm_running && { info "Stopping the half-built machine first..."; vm_stop; }

  if [ "$p" = none ] || [ "$p" = prepared ]; then
    step "Prepare: Alpine CD, key, virtual machine"
    get_iso
    make_key
    make_installer_cd
    write_vmx
    make_disk
    set_build_phase prepared
    step "Phase 1 of 3: install Alpine onto the virtual disk (limit $(fmt_dur $PHASE1_LIMIT))"
    why "Alpine boots from the CD, answers its own setup questions and installs itself."
    why "Progress shows here once Alpine's network and SSH are up (after about 1-2 min)."
    watch_phase 1 "$PHASE1_LIMIT" /root/alpinewifi-auto.log
    set_build_phase 1; p=1
  fi
  if [ "$p" = 1 ]; then
    step "Phase 2 of 3: Wi-Fi driver and router setup (limit $(fmt_dur $PHASE2_LIMIT))"
    why "First start from the new disk: downloads the Realtek firmware and Wi-Fi tools, sets up NAT."
    vmx_set sata0:1.startConnected FALSE
    vmx_set ethernet0.connectionType nat
    watch_phase 2 "$PHASE2_LIMIT" /root/alpinewifi-install.log
    set_build_phase 2; p=2
  fi
  if [ "$p" = 2 ]; then
    step "Phase 3 of 3: switch to the private Mac network and check (limit $(fmt_dur $PHASE3_LIMIT))"
    why "From now on Alpine is only reachable from this Mac, at $ALPINE_IP."
    if ! phase3_finish; then
      [ "${MW_PHASE2_RETRIED:-no}" = no ] || fail "Alpine's setup is incomplete (missing:$MW_MISSING), even after repeating it." \
        "Look at /root/alpinewifi-install.log inside Alpine (details in the log), or move the machine aside and run the installer again."
      warn "Repeating phase 2 once to repair it."
      redo_phase2 || fail "Couldn't prepare the repair." "Run the installer again."
      MW_PHASE2_RETRIED=yes
      build_vm; return
    fi
    rm -f "$VM_DIR/installer.iso"
    set_build_phase "done"
    ok "The Alpine Wi-Fi machine is built"
    notify "The Alpine Wi-Fi machine is built." Glass
  fi
}

# run directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  build_vm
  echo; ok "Done. Log: $MW_LOG"
fi
