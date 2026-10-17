#!/bin/bash
# Restores the Alpine Wi-Fi machine from a backup made by shortcut 5 (backup.sh).
# Usage: restore.sh [backup-file]   - without a file it offers the backups in ~/Mac Wi-Fi Backups.
# The machine folder must not exist yet (install-all.sh moves a broken one aside first).
# Source it and call restore_vm, or run it directly.

[ -n "${MW_SETUP_DIR:-}" ] || . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# list_backups  - newest first, one path per line
list_backups() { find "$BACKUP_DIR" -maxdepth 1 -name "$(echo "$VM_NAME" | tr ' ' '-')-20*.tar.gz" -print 2>/dev/null | sort -r; }

# backup_date FILE  - "2026-10-17 11:42" from the file name
backup_date() { basename "$1" | sed -E 's/.*-([0-9]{4}-[0-9]{2}-[0-9]{2})-([0-9]{2})([0-9]{2})[0-9]{2}\.tar\.gz/\1 \2:\3/'; }

# choose_backup  - prints the chosen file (asks only when there is more than one)
choose_backup() {
  local files n i=0 pick f
  files=$(list_backups); n=$(printf '%s\n' "$files" | grep -c .)
  [ "$n" -eq 0 ] && return 1
  if [ "$n" -eq 1 ]; then printf '%s\n' "$files"; return 0; fi
  echo "          Backups found:" >&2
  while IFS= read -r f; do i=$((i + 1)); echo "            $i) $(backup_date "$f")  ($(du -h "$f" | awk '{print $1}'))" >&2; done <<< "$files"
  read -r -t 120 -p "          Which one? [1 = newest, 2 min = 1] " pick || pick=1
  case "$pick" in ''|*[!0-9]*) pick=1 ;; esac
  [ "$pick" -ge 1 ] && [ "$pick" -le "$n" ] || pick=1
  printf '%s\n' "$files" | sed -n "${pick}p"
}

restore_vm() {
  local file=${1:-} tmp src vmx
  step "Restore the Alpine Wi-Fi machine from a backup"
  why "Puts back an exact copy of a working machine, including your saved Wi-Fi networks."
  [ -n "$file" ] || file=$(choose_backup) || fail "No backups found in '$BACKUP_DIR'."
  [ -f "$file" ] || fail "Backup file not found: $file"
  [ -e "$VM_DIR" ] && fail "'$VM_DIR' already exists." "Move it aside first (the installer does this for you)."
  info "Using the backup from $(backup_date "$file")"
  mkdir -p "$VMS_DIR"
  tmp=$(mktemp -d "$VMS_DIR/.restore.XXXXXX") || fail "Couldn't make a temporary folder in '$VMS_DIR'."
  add_cleanup "rm -rf '$tmp'"
  info "Unpacking (up to 10 min)..."
  with_timeout 600 tar -xzf "$file" -C "$tmp" 2>>"$MW_LOG" || fail "The backup couldn't be unpacked (it may be damaged)." "Try an older backup."
  src=$(find "$tmp" -maxdepth 1 -name '*.vmwarevm' -type d | head -1)
  vmx=$(find "$src" -maxdepth 1 -name '*.vmx' | head -1)
  [ -n "$src" ] && [ -n "$vmx" ] && [ -f "$src/claude-key" ] || fail "The backup doesn't contain a complete machine."
  if [ "$(basename "$vmx")" != "$VM_NAME.vmx" ]; then      # restoring under another name (test mode)
    mv "$vmx" "$src/$VM_NAME.vmx"
    sed -i '' -e "s/^displayName = .*/displayName = \"$VM_NAME\"/" -e '/^usb.autoConnect/d' "$src/$VM_NAME.vmx"
  fi
  chmod 600 "$src/claude-key"
  mv "$src" "$VM_DIR" || fail "Couldn't move the restored machine into place."
  [ -f "$VM_DIR/.build-phase" ] || echo "done" > "$VM_DIR/.build-phase"
  render "$MW_SETUP_DIR/mac/sshcfg" "$SSHCFG"
  ok "Machine restored to '$VM_DIR'"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  restore_vm "$@"
fi
