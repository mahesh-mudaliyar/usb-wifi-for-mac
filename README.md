# Mac Wi-Fi (Alpine + USB Wi-Fi adapter)

This Mac's built-in Wi-Fi isn't used. Internet comes from one of two places:

1. **Wi-Fi** through a small **Realtek RTL8188EU USB Wi-Fi adapter** (`802.11n NIC`, USB id `0bda:8179`, 2.4 GHz only). The adapter is handed to a hidden **Alpine Linux** virtual machine in **VMware Fusion**. Alpine joins the Wi-Fi and shares it with the Mac.
2. **Phone USB tethering** as the backup, through `muta`.

A background switcher on the Mac uses Wi-Fi whenever it has internet, and falls back to the phone when it doesn't.

```
 Wi-Fi router ))) USB adapter ──► Alpine VM (wlan0) ──NAT──► eth0 192.168.235.100
                                                                │  VMware "Private to my Mac" (vmnet1)
                                                     Mac bridge 192.168.235.1 ──► Mac internet
 Phone ──USB tethering──► muta (utun) ───────────────────────────► backup
```

---

## Install or repair: one double-click

1. Plug in the **USB Wi-Fi adapter**. Make sure the Mac has **some internet** (phone tethering, a cable or a hotspot).
2. Double-click **`Install Mac Wi-Fi.command`**.
   - The first time, macOS may say it's from an unidentified developer. If so, **right-click → Open → Open**.
3. Press Return to start, and type your **Mac login password** once.
4. Wait. Each step explains what it's doing and has a time limit. You get a **notification** when it's done, when it needs you, or if something goes wrong.
5. At the end, pick your Wi-Fi network when asked.

The installer checks what's already there and only does what's missing:

| What it finds | What it does | Time |
|---|---|---|
| A working Alpine machine | Repairs the Mac side only: services, switcher, shortcuts | ~1 min |
| No machine, but a backup | Offers to **restore** the backup (or build a new one) | ~2 min |
| Nothing | **Builds a new Alpine machine by itself**, no typing needed | 5–25 min |
| A broken machine | Moves it aside (never deletes it), then restores or builds | — |

It's safe to run again at any time. If it stops halfway, run it again and it carries on from where it stopped.

### What the installer does, step by step

| # | Step | Why | Time limit |
|---|---|---|---|
| 1 | Check the Mac | Apple silicon, 3 GB free disk, internet. With no internet it waits and tells you how to connect. | 10 min wait for internet |
| 2 | Mac password | Needed for the background services and VMware's network settings. Asked once. | — |
| 3 | VMware Fusion | Runs the hidden Alpine machine. If it's missing, it opens the download page and waits. Broadcom needs a free account, so **this is the one thing you install by hand**. | 30 min |
| 4 | Homebrew, muta | Homebrew installs Rust and xorriso. muta is built from source and handles the phone's USB tethering. | 20–30 min |
| 5 | VMware private network | Makes sure "Private to my Mac" is `192.168.235.0`, the network the Mac and Alpine talk on. | 2 min |
| 6 | Pause auto-start | So nothing restarts Alpine while it's checked or built. Wi-Fi keeps working, and auto-start is always turned back on, even if something fails. | — |
| 7 | Alpine machine | Repair, restore or build (see below). | 25 + 20 + 4 min |
| 8 | Mac services | muta service, Wi-Fi/phone switcher (every 15 s), auto-start agent (every minute). | 3 min |
| 9 | Shortcuts | Copies the shortcuts to `~/Desktop/Mac Wi-Fi`. Old versions go to `old/`. | — |
| 10 | Turn Wi-Fi on | Starts Alpine and checks it can see the USB adapter. If not, it asks you to replug it. | 2.5 min |
| 11 | Pick a network | Runs "2 Change Wi-Fi network", then waits for the Mac to switch to Wi-Fi. | 2.5 min |

### How a new Alpine machine is built (no typing needed)

| Phase | Where | What happens |
|---|---|---|
| Prepare | Mac | Downloads Alpine 3.24.2 (~380 MB, checksum verified, cached for next time) and makes an SSH key. Adds a small auto-installer to the Alpine CD with `xorriso`. Creates the VM on VMware's **NAT** network, so Alpine can download packages during setup. |
| 1 | Alpine (from CD) | `setup-alpine` runs with an answer file: no questions, installs to the virtual disk, then powers off. |
| 2 | Alpine (from disk) | First boot: installs the **Wi-Fi driver firmware** (`linux-firmware-rtlwifi`), `iw`, `wpa_supplicant`, the Wi-Fi helpers, NAT and the keepalive job. Then it powers off. |
| 3 | Mac | Switches the VM to **Private to my Mac**, starts it, and checks over SSH that the driver, firmware, NAT, forwarding, keepalive and helpers are all present. If anything is missing, it restarts Alpine's services, and if needed repeats phase 2 once by itself. |

A test build took **3½ minutes** in total (phase 1 ≈ 2 min, phase 2 ≈ 30 s, phase 3 ≈ 30 s); slow internet makes it longer. While phases 1 and 2 run, Alpine's own messages appear in the installer window as `alpine| …`. Each phase has a time limit. If it's taking long, the installer tells you how to watch it: **open VMware Fusion and click the "Alpine WiFi" window**.

### The Wi-Fi driver (nothing to compile)

The RTL8188EU works with the **`rtl8xxxu`** driver that's already in Alpine's `linux-lts` kernel. It only needs the firmware file `rtlwifi/rtl8188eufw.bin`, from the **`linux-firmware-rtlwifi`** package, which phase 2 installs. To check it from the Mac:

```bash
ssh -F "$HOME/Virtual Machines.localized/Alpine WiFi.vmwarevm/sshcfg" alp 'dmesg | grep -iE "8188|rtl8xxxu"; iw dev'
```

---

## Everyday use (shortcuts in `~/Desktop/Mac Wi-Fi`)

| Shortcut | Use it when |
|---|---|
| `0 Which internet am I on` | You want to see what the Mac is using, the Wi-Fi name and signal, and whether the internet works |
| `1 Start Wi-Fi` | Wi-Fi is off or not working. It starts Alpine, joins Wi-Fi and waits for the Mac to switch, showing each step |
| `2 Change Wi-Fi network` | You're somewhere new. It searches, you pick a network and type the password. Every network is remembered, and the newest one is preferred |
| `3 Stop Wi-Fi and use phone` | You want to turn Wi-Fi off and use only the phone |
| `4 Use phone USB tethering` | You want to check the phone backup, or start it by hand |
| `5 Back up Wi-Fi machine` | Wi-Fi works and you want a safety copy. Do this once after setup |
| `Install Mac Wi-Fi` | Something is broken, or after a macOS update or reinstall. It repairs whatever is missing |

**At a new place:** plug in the adapter, run `1 Start Wi-Fi`, then `2 Change Wi-Fi network`.

### Backups

`5 Back up Wi-Fi machine` saves the whole Alpine machine, including your saved Wi-Fi networks, to **`~/Mac Wi-Fi Backups/`** and keeps the newest 3. Wi-Fi pauses for 1–2 minutes while it copies; the Mac uses the phone meanwhile, and Wi-Fi comes back by itself, even if the backup fails.

The backup contains your Wi-Fi passwords and the SSH key, so it's readable only by you. It's deliberately **not** in Documents, which may sync to iCloud. Copy it to a USB drive so it survives a Mac reset. To use it on a new Mac, put it back in `~/Mac Wi-Fi Backups/` and run the installer.

---

## When something is wrong

| Problem | Fix |
|---|---|
| Installer says **PROBLEM** | Read the "What to do" line under it, then run the installer again; finished steps are skipped. The full log is in `~/Library/Logs/mac-wifi-install.log`. |
| "Alpine can't see the Wi-Fi adapter" | Unplug the adapter, wait 5 s and plug it back in, then run `1 Start Wi-Fi`. Or in VMware Fusion: Virtual Machine > USB > connect **Realtek 802.11n NIC**. |
| Your network isn't in the list | The adapter only sees **2.4 GHz** networks. Use the router's 2.4 GHz name, or `h` for a hidden network. |
| "Joined but no internet" | The router is offline, or it's a hotel/café login page. Alpine can't open login pages, so use the phone. |
| Mac doesn't switch to Wi-Fi | Wait 30 s and run `0 Which internet am I on`. Running the installer again reinstalls the switcher. |
| Alpine won't start | Open VMware Fusion once to see the message. A lock left behind after a crash is cleared automatically. |

**Logs**
- Installer: `~/Library/Logs/mac-wifi-install.log`
- Wi-Fi/phone switcher: `/var/log/alpinewifi.log`
- Auto-start: `~/Library/Logs/alpinewifi-autostart.log`
- Inside Alpine: `/root/alpinewifi-install.log`, and `logread | grep wifi-keepalive`

---

## What's in this folder

```
Install Mac Wi-Fi.command      the one-click installer / repair
0-5 *.command                  the Desktop shortcuts
setup/
  install-all.sh               the installer's steps (called by Install Mac Wi-Fi.command)
  build-vm.sh                  builds a new Alpine machine unattended (phases 1-3)
  backup.sh / restore.sh       backup and restore of the Alpine machine
  lib.sh                       shared helpers: messages, time limits, notifications, VMware/SSH helpers
  mac/                         Mac side, copied into the VM folder by the installer
    wifi-failover.sh             the Wi-Fi/phone switcher (runs as root every 15 s)
    install-auto.sh              installs muta's service + the switcher (sudo)
    update-switcher.sh           reinstalls the switcher after editing it (sudo)
    autostart-vm.sh + .plist     keeps Alpine running hidden (login + every minute)
    sshcfg                       SSH settings template for reaching Alpine as "alp"
    push-alpine-setup.sh         re-runs the Alpine setup on an existing machine (needs Alpine's Wi-Fi online)
    Alpine WiFi.vmx.reference    the original working VM settings, for comparison
  alpine/
    install.sh                   inside Alpine: firmware/driver, helpers, network, NAT, keepalive
    files/                       wifi-join, wifi-scan-list, wifi-keepalive, interfaces, NAT rules
    auto/                        the unattended-install pieces used by build-vm.sh
```

The installer also copies this folder to `~/Library/Application Support/Mac Wi-Fi`, so the Desktop shortcuts can always find it.

**For testing changes** without touching the real machine:

```bash
MACWIFI_TEST=1 bash setup/build-vm.sh
```

This builds a separate "Alpine WiFi Test" machine at `192.168.235.101`. It doesn't attach the USB adapter and doesn't change any Mac services.

**Notes**
- Alpine's root account has no password, but SSH accepts only the key in the VM folder. The machine is reachable only from this Mac.
- The Wi-Fi country is set to `IN` in `wifi-join` and `install.sh`. Change it there if you move country.
