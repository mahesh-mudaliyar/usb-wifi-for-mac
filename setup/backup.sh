#!/bin/bash
# Backs up the working Alpine Wi-Fi machine to ~/Mac Wi-Fi Backups and keeps the newest 3.
# Wi-Fi pauses for 1-2 minutes while the machine is copied; the Mac uses the phone meanwhile.
# The backup holds your saved Wi-Fi passwords and the SSH key, so it's readable only by you.
# Run directly (shortcut 6) or source it and call backup_vm.

[ -n "${MW_SETUP_DIR:-}" ] || . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

backup_vm() {
  local slug name need free was_running=no we_paused=no
  step "Back up the Alpine Wi-Fi machine"
  why "Makes a copy you can restore in about 2 minutes if the Mac is reset or the machine breaks."
  [ -f "$VMX" ] || fail "There's no Alpine Wi-Fi machine at '$VM_DIR' to back up."
  [ -x "$VMRUN" ] || fail "VMware Fusion isn't installed."
  if ! mkdir -p "$BACKUP_DIR" || ! chmod 700 "$BACKUP_DIR"; then fail "Couldn't create '$BACKUP_DIR'."; fi
  need=$(du -sk "$VM_DIR" | awk '{print $1}')
  free=$(df -k "$BACKUP_DIR" | awk 'NR==2 {print $4}')
  [ "$free" -gt $((need + 1048576)) ] || fail "Not enough free disk space for a backup (need about $((need / 1024 + 1024)) MB)."

  if [ "${MACWIFI_TEST:-0}" != 1 ] && [ ! -f "$DISABLED_FLAG" ]; then
    touch "$DISABLED_FLAG"; we_paused=yes
    add_cleanup "rm -f '$DISABLED_FLAG'"       # Wi-Fi comes back even if the backup fails
  fi
  if vm_running; then
    was_running=yes
    add_cleanup "vm_start"
    info "Shutting Alpine down so its disk can be copied safely (up to 90 s)..."
    vm_stop || fail "Alpine didn't shut down." "Try again in a minute."
    ok "Alpine is off (the Mac uses the phone for now)"
  fi

  slug=$(echo "$VM_NAME" | tr ' ' '-')
  name="$slug-$(date +%Y-%m-%d-%H%M%S).tar.gz"
  info "Copying and compressing the machine (about 400 MB, up to 15 min)..."
  with_timeout 900 tar -czf "$BACKUP_DIR/$name.part" \
      --exclude '*.log' --exclude '*.lck' --exclude '*.scoreboard' --exclude installer.iso \
      --exclude "$VM_NAME.vmwarevm/old" --exclude "$VM_NAME.vmwarevm/caches" \
      -C "$VMS_DIR" "$VM_NAME.vmwarevm" 2>>"$MW_LOG" \
    || { rm -f "$BACKUP_DIR/$name.part"; fail "Making the backup failed." "See the log; check free disk space."; }
  chmod 600 "$BACKUP_DIR/$name.part"
  info "Checking the backup..."
  local list; list=$(with_timeout 300 tar -tzf "$BACKUP_DIR/$name.part" 2>>"$MW_LOG")
  if ! printf '%s\n' "$list" | grep -qxF "$VM_NAME.vmwarevm/$VM_NAME.vmx" \
     || ! printf '%s\n' "$list" | grep -qxF "$VM_NAME.vmwarevm/claude-key"; then
    rm -f "$BACKUP_DIR/$name.part"; fail "The backup is incomplete (it can't be read back)." "Try again."
  fi
  mv "$BACKUP_DIR/$name.part" "$BACKUP_DIR/$name"
  ok "Backup saved: $BACKUP_DIR/$name ($(du -h "$BACKUP_DIR/$name" | awk '{print $1}'))"

  # keep the newest 3 of this machine's backups
  local old
  find "$BACKUP_DIR" -maxdepth 1 -name "$slug-20*.tar.gz" -print 2>/dev/null | sort -r | tail -n +4 |
    while IFS= read -r old; do rm -f "$old" && log "removed old backup $old"; done

  if [ "$was_running" = yes ]; then
    info "Starting Alpine again..."
    vm_start || warn "Alpine didn't start - double-click '1 Start Wi-Fi'."
  fi
  [ "$we_paused" = yes ] && rm -f "$DISABLED_FLAG"
  if [ "$was_running" = yes ]; then
    if wait_until 150 "Alpine to be back" "" alp_up; then ok "Alpine is running again; the Mac switches back to Wi-Fi within a minute"
    else warn "Alpine is slow to come back - check with '0 Which internet am I on' in a minute."; fi
  fi
  why "Tip: copy the backup to a USB drive too, so it survives if this Mac is erased."
  notify "Wi-Fi machine backed up." Glass
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  backup_vm
fi
