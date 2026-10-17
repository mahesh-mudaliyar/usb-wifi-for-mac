# Mac Wi-Fi (Alpine + USB Wi-Fi dongle)

For Apple silicon Macs whose built-in Wi-Fi doesn't work. Internet comes from one of two places:

1. **Wi-Fi** through a **USB Wi-Fi dongle**. macOS on Apple silicon has no drivers for USB Wi-Fi dongles, so the dongle is handed to a hidden **Alpine Linux** virtual machine in **VMware Fusion**. Alpine's Linux drives the dongle, joins the Wi-Fi and shares it with the Mac. **Any dongle Linux has a driver for works**: 1,128 USB IDs across all the common Realtek, MediaTek/Ralink and Atheros chips.
2. **Phone USB tethering** as the backup. Android phones work through [`muta`](https://crates.io/crates/muta), which the installer sets up and which was tested. An iPhone's USB Personal Hotspot is built into macOS and should work as the backup too, but that hasn't been tested.

A background switcher on the Mac uses Wi-Fi whenever it has internet, and falls back to the phone when it doesn't. When Wi-Fi comes back, it switches back by itself.

```
 Wi-Fi router ))) USB dongle ──► Alpine VM (wlan0)  ──NAT──► eth0 192.168.235.100
                                                                │  VMware "Private to my Mac" (vmnet1)
                                                     Mac bridge 192.168.235.1 ──► Mac internet
 Phone ──USB tethering──► muta (utun) ───────────────────────────► backup
```

> **First, check whether you need this at all.** Double-click **`Check Wi-Fi hardware.command`**. It tells you whether the Mac's own Wi-Fi works, and whether your dongle is supported. The full guide, including the other options (phone, Ethernet, travel router, repair) and which dongles work: **[docs/WIFI-ADAPTERS.md](docs/WIFI-ADAPTERS.md)**.

---

## What you need

| | |
|---|---|
| **Mac** | Apple silicon (M1 or newer). The installer refuses Intel Macs, because the Alpine machine is built for ARM. |
| **VMware Fusion** | Free for personal use. Broadcom needs a free account to download it, so this is the one thing you install by hand. The installer opens the page and waits. |
| **USB Wi-Fi dongle** | One with a Linux driver: see [docs/WIFI-ADAPTERS.md](docs/WIFI-ADAPTERS.md). You can install without one and add it later. Most dongles are USB-A, so you may need a USB-C adapter. |
| **Internet during install** | Any kind: a phone, a cable or a hotspot. It downloads Alpine (~380 MB), firmware (~50 MB) and tools. |
| **Disk space** | About 3 GB free |
| **Your Mac login password** | For the background services and VMware's network settings |

**Tested on:** MacBook Pro (M4) with failed built-in Wi-Fi, macOS 27.0.1, VMware Fusion 26.0.1, Alpine 3.24.2, Realtek RTL8188EU dongle (`0bda:8179`), and an Android phone with muta 0.1.4. Other Macs, macOS versions and dongles are expected to work but haven't been tried.

### Getting it onto your Mac

- **With git:**
  ```bash
  git clone https://github.com/mahesh-mudaliyar/usb-wifi-for-mac.git
  ```
- **Without git:** on the GitHub page, click **Code → Download ZIP**, then unzip it.

The first time you open one of the `.command` files, macOS may refuse because it's "from an unidentified developer". Then open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**. On older macOS, right-click the file → **Open** → **Open** also works. Or allow all of them at once by running this on the downloaded folder:

```bash
xattr -dr com.apple.quarantine ~/Downloads/usb-wifi-for-mac-main
```

---

## Install or repair: one double-click

1. Plug in the **USB Wi-Fi dongle**. Make sure the Mac has **some internet**.
2. Double-click **`Install Mac Wi-Fi.command`**.
3. Press Return to start. Type your **Mac login password** when asked. If Homebrew has to be installed, its own installer may ask for it again.
4. Wait. Each step explains what it's doing and has a time limit. You get a **notification** when it's done, when it needs you, or if something goes wrong.
5. At the end, pick your Wi-Fi network when asked.

The installer checks what's already there and only does what's missing:

| What it finds | What it does | Time |
|---|---|---|
| The Mac's own Wi-Fi works | Tells you so and stops: you don't need this | ~30 s |
| A working Alpine machine | Repairs the Mac side only: services, switcher, shortcuts | ~1 min |
| No machine, but a backup | Offers to **restore** the backup (or build a new one) | ~2 min |
| Nothing | **Builds a new Alpine machine by itself**, no typing needed | 5–25 min |
| A broken machine | Moves it aside (never deletes it), then restores or builds | — |

It's safe to run again at any time. If it stops halfway, run it again and it carries on from where it stopped.

### What the installer does, step by step

| # | Step | Why | Time limit |
|---|---|---|---|
| 1 | Check the Mac | Apple silicon, 3 GB free disk, internet. With no internet it waits and tells you how to connect. | 10 min wait for internet |
| 2 | **The Mac's own Wi-Fi** | If the built-in Wi-Fi works, it says so and stops, unless you ask it to continue. If it's off, it offers to switch it on and test it. | ~1 min |
| 3 | **USB Wi-Fi dongle** | Finds the dongle, looks up its USB ID in Alpine's driver list, and saves the choice in `~/.alpinewifi-adapter`. It walks you through "driver CD" mode dongles. Without a dongle you can continue and add one later. | — |
| 4 | Mac password | Asked once, and kept fresh while the installer runs | — |
| 5 | VMware Fusion | Runs the hidden Alpine machine. If it's missing, it opens the download page and waits. | 30 min |
| 6 | Homebrew, muta | muta (Android tethering) is built from source; Homebrew installs **Rust** only for that. **xorriso** is installed only when a new Alpine machine has to be built. | 20–30 min |
| 7 | VMware private network | Makes sure "Private to my Mac" is `192.168.235.0`, the network the Mac and Alpine talk on | 2 min |
| 8 | Pause auto-start | So nothing restarts Alpine while it's checked or built. Wi-Fi keeps working, and auto-start is always turned back on, even if something fails. | — |
| 9 | Alpine machine | Repair, restore or build (see below), then tell VMware to hand it the chosen dongle | 25 + 20 + 4 min |
| 10 | Mac services | muta's service, the Wi-Fi/phone switcher (every 15 s) and the auto-start agent (every minute; also restarts Alpine if the dongle stops working) | 3 min |
| 11 | Shortcuts | Copies the shortcuts to `~/Desktop/Mac Wi-Fi` (old versions go to `old/`), and a copy of this folder to `~/Library/Application Support/Mac Wi-Fi` | — |
| 12 | Turn Wi-Fi on | Starts Alpine and checks it can use the dongle. If not, it says exactly why (not handed over, no driver, missing firmware) and asks you to replug it. | 2.5 min |
| 13 | Pick a network | Runs "2 Change Wi-Fi network", then waits for the Mac to switch to Wi-Fi | 2.5 min |

### How a new Alpine machine is built (no typing needed)

| Phase | Where | What happens |
|---|---|---|
| Prepare | Mac | Downloads Alpine 3.24.2 (~380 MB, checksum verified, cached for next time) and makes an SSH key. Adds a small auto-installer to the Alpine CD with `xorriso`. Creates the VM on VMware's **NAT** network, so Alpine can download packages during setup. |
| 1 | Alpine (from CD) | `setup-alpine` runs with an answer file: no questions, installs to the virtual disk, then powers off |
| 2 | Alpine (from disk) | First boot: installs **firmware for every common USB Wi-Fi chip** (Realtek rtlwifi/rtw88/rtw89, MediaTek, Atheros, Ralink and more, about 50 MB), `iw`, `wpa_supplicant`, the Wi-Fi helpers, NAT and the keepalive job. Then it powers off. |
| 3 | Mac | Switches the VM to **Private to my Mac**, starts it, and checks over SSH that the driver, firmware, NAT, forwarding, keepalive and helpers are all present. If anything is missing, it restarts Alpine's services, and if needed repeats phase 2 once by itself. |

The latest test build took **about 4 minutes** in total (phase 1 ≈ 2 min, phase 2 ≈ 1 min, phase 3 ≈ 30 s). Slow internet makes it longer.

While phases 1 and 2 run, Alpine's own messages appear in the installer window as `alpine| …`. Each phase has a time limit. If one is taking long, the installer tells you how to watch it: **open VMware Fusion and click the "Alpine WiFi" window**.

### The Wi-Fi driver (nothing to compile)

Alpine's `linux-lts` kernel already contains the Wi-Fi drivers. The installer adds the **firmware** they need. The list of supported dongles comes from the drivers themselves: [`setup/data/wifi-usb-ids.txt`](setup/data/wifi-usb-ids.txt) has 1,128 USB IDs across 31 drivers. To see what Alpine makes of your dongle:

```bash
ssh -F "$HOME/Virtual Machines.localized/Alpine WiFi.vmwarevm/sshcfg" alp wifi-adapter-info
```

It shows the USB device, which driver took it, the Wi-Fi interface and its bands, and any firmware problem. Details and the full chip list: [docs/WIFI-ADAPTERS.md](docs/WIFI-ADAPTERS.md).

---

## Everyday use (shortcuts in `~/Desktop/Mac Wi-Fi`)

| Shortcut | Use it when |
|---|---|
| `0 Which internet am I on` | You want to see what the Mac is using (Wi-Fi or phone), the Wi-Fi name and signal, whether the dongle is working, whether the internet works, and the last switches |
| `1 Start Wi-Fi` | Wi-Fi is off or not working. It turns Wi-Fi back on if shortcut 3 had turned it off, starts Alpine, joins Wi-Fi and waits for the Mac to switch, showing each step. If the dongle has a problem, it explains what's wrong. |
| `2 Change Wi-Fi network` | You're somewhere new. It shows which bands your dongle can use, searches, and you pick a network and type the password. Every network is remembered, and the newest one is preferred. |
| `3 Stop Wi-Fi and use phone` | You want to use only the phone. It first checks the phone is connected (otherwise it changes nothing), waits until the Mac is on the phone, and only then shuts Alpine down, so there's no gap. Wi-Fi stays off until shortcut 5 or 1. |
| `4 Use phone USB tethering` | You want to check the phone backup, or start it by hand |
| `5 Switch from phone to Wi-Fi` | You're on the phone and want Wi-Fi now. It turns Wi-Fi back on if shortcut 3 had turned it off, and switches on the first good check instead of waiting for two. |
| `6 Back up Wi-Fi machine` | Wi-Fi works and you want a safety copy. Do this once after setup. |
| `Check Wi-Fi hardware` | You want to know whether the Mac's own Wi-Fi works, or you plugged in a **different dongle**. It checks the dongle and hands it to Alpine. |
| `Install Mac Wi-Fi` | Something is broken, or after a macOS update or reinstall. It repairs whatever is missing. |

**At a new place:** plug in the dongle, run `1 Start Wi-Fi`, then `2 Change Wi-Fi network`.

### What runs by itself

- **Wi-Fi/phone switcher** (every 15 s, as root): uses Wi-Fi when it really has internet. It tests with an encrypted connection to an IP address, which a hotel login page can't fake. After two failed checks it moves the Mac to the phone, and it moves back when Wi-Fi recovers. Each run is limited to 40 s, so it can never hang.
- **Auto-start** (at login and every minute): keeps Alpine running hidden, with no window and no Dock icon. If Alpine's Wi-Fi has failed 3 checks in a row and the dongle sees no networks at all (or has failed 10 checks even though it does see networks), it restarts Alpine, at most once every 10 minutes. A fresh USB connection revives a stuck dongle.
- **Keepalive inside Alpine** (every minute): reconnects Wi-Fi, and resets the dongle in software if it stays down.

### Backups

`6 Back up Wi-Fi machine` saves the whole Alpine machine, including your saved Wi-Fi networks, to **`~/Mac Wi-Fi Backups/`** and keeps the newest 3. Wi-Fi pauses for 1–2 minutes while it copies. The Mac uses the phone meanwhile, and Wi-Fi comes back by itself, even if the backup fails.

The backup contains your Wi-Fi passwords and the SSH key, so it's readable only by you. It's deliberately **not** in Documents, which may sync to iCloud. Copy it to a USB drive so it survives a Mac reset. To use it on a new Mac, put it back in `~/Mac Wi-Fi Backups/` and run the installer: it offers to restore it.

---

## When something is wrong

| Problem | Fix |
|---|---|
| Installer says **PROBLEM** | Read the "What to do" line under it, then run the installer again; finished steps are skipped. The full log is in `~/Library/Logs/mac-wifi-install.log`. |
| A dongle problem | `1 Start Wi-Fi` asks Alpine what it sees and explains it: not handed over, no Linux driver, or firmware missing. Fixes for each are in [docs/WIFI-ADAPTERS.md](docs/WIFI-ADAPTERS.md#5-when-the-dongle-doesnt-work). |
| You changed dongles | Run `Check Wi-Fi hardware` so VMware hands the new one to Alpine |
| Your network isn't in the list | Many dongles only see **2.4 GHz** networks. `2 Change Wi-Fi network` shows which bands yours can use. Use the router's 2.4 GHz name, or `h` for a hidden network. |
| "Joined but no internet" | The router is offline, or it's a hotel/café login page. Alpine can't open login pages, so use the phone. |
| Mac stays on the phone | Run `5 Switch from phone to Wi-Fi`. If it still doesn't switch, run `0 Which internet am I on`: the "Why not Wi-Fi" line says what's wrong. |
| Shortcut 3 says the phone isn't connected | Plug the phone in and turn on USB tethering first. Without it the Mac would have no internet, so nothing is changed. |
| Wi-Fi keeps dropping | The keepalive and auto-start repair it by themselves. Check `~/Library/Logs/alpinewifi-autostart.log` to see how often. A powered USB hub or a short extension cable often helps weak dongles. |
| Alpine won't start | Open VMware Fusion once to see the message. A lock left behind after a crash is cleared automatically. |

**Logs**
- Installer: `~/Library/Logs/mac-wifi-install.log`
- Wi-Fi/phone switcher: `/var/log/alpinewifi.log`
- Auto-start and self-healing: `~/Library/Logs/alpinewifi-autostart.log`
- Inside Alpine: `/root/alpinewifi-install.log`, and `logread | grep wifi-keepalive`

---

## What it changes on your Mac

| What | Where |
|---|---|
| The Alpine machine | `~/Virtual Machines.localized/Alpine WiFi.vmwarevm`, which also holds the SSH key and your saved Wi-Fi networks |
| Wi-Fi/phone switcher (root) | `/Library/LaunchDaemons/com.alpinewifi.failover.plist`, `/usr/local/libexec/alpinewifi-failover.sh`, log `/var/log/alpinewifi.log` |
| Phone tethering service (root) | `/Library/LaunchDaemons/com.github.jost-s.muta.plist`, `/usr/local/libexec/muta/`, and `~/.cargo/bin/muta` |
| Auto-start (your user) | `~/Library/LaunchAgents/com.alpinewifi.autostart.plist` |
| VMware's private network | `/Library/Preferences/VMware Fusion/networking`, set to `192.168.235.0`. The original is kept as `networking.before-mac-wifi` if it had to be changed. |
| Homebrew packages | `rust` (only to build muta) and `xorriso` (only to build a new machine) |
| Small settings files | `~/.alpinewifi-adapter` (the chosen dongle), `~/.alpinewifi-disabled` (while Wi-Fi is turned off), `~/.alpinewifi-switchnow` (briefly, from shortcut 5), `~/Library/Caches/alpinewifi-lastheal` |
| Shortcuts and copies | `~/Desktop/Mac Wi-Fi`, `~/Library/Application Support/Mac Wi-Fi`, `~/Mac Wi-Fi Backups`, `~/Library/Logs/mac-wifi-install.log` |
| Network settings | While Wi-Fi is in use, the switcher adds a temporary "AlpineWiFi" entry to macOS's live network state (`scutil`), so the Mac prefers it. This isn't saved in System Settings and is gone after a restart. |

## Uninstall

Run these one at a time in Terminal. Each removes one piece, and they're safe to run even if that piece is already gone.

1. Stop the auto-start:
   ```bash
   launchctl bootout gui/$(id -u)/com.alpinewifi.autostart; rm -f ~/Library/LaunchAgents/com.alpinewifi.autostart.plist
   ```
2. Stop and remove the Wi-Fi/phone switcher:
   ```bash
   sudo launchctl bootout system/com.alpinewifi.failover; sudo rm -f /Library/LaunchDaemons/com.alpinewifi.failover.plist /usr/local/libexec/alpinewifi-failover.sh
   ```
3. Remove the switcher's live network setting:
   ```bash
   printf 'remove State:/Network/Service/AlpineWiFi/IPv4\nremove State:/Network/Service/AlpineWiFi/DNS\n' | sudo scutil
   ```
4. Shut Alpine down:
   ```bash
   "/Applications/VMware Fusion.app/Contents/Library/vmrun" -T fusion stop "$HOME/Virtual Machines.localized/Alpine WiFi.vmwarevm/Alpine WiFi.vmx" hard
   ```
5. Only if you no longer want Android phone tethering:
   ```bash
   sudo ~/.cargo/bin/muta uninstall
   ```
6. Then, in Finder, move these to the Trash:
   - the `Alpine WiFi.vmwarevm` folder, in `~/Virtual Machines.localized`
   - `~/Desktop/Mac Wi-Fi`
   - `~/Library/Application Support/Mac Wi-Fi`
   - the `~/.alpinewifi-*` files. Press **Command-Shift-.** in your home folder to see hidden files.
   - `~/Mac Wi-Fi Backups`, if you don't need the backups any more

VMware's network setting can stay as it is; it's harmless. Restart the Mac afterwards to clear any routes the switcher left behind.

---

## What's in this folder

```
Install Mac Wi-Fi.command      the one-click installer / repair
Check Wi-Fi hardware.command   is the built-in Wi-Fi OK? which dongle, is it supported? (also run by the installer)
0-6 *.command                  the Desktop shortcuts
docs/WIFI-ADAPTERS.md          the guide: built-in Wi-Fi check, your options, supported dongles
setup/
  install-all.sh               the installer's steps (called by Install Mac Wi-Fi.command)
  build-vm.sh                  builds a new Alpine machine unattended (phases 1-3)
  backup.sh / restore.sh       backup and restore of the Alpine machine
  check-wifi.sh                the built-in Wi-Fi check + USB dongle detection and choice
  lib.sh                       shared helpers: messages, time limits, notifications, VMware/SSH helpers
  data/wifi-usb-ids.txt        every USB Wi-Fi ID Alpine's kernel supports (generated)
  data/wifi-drivers.txt        what each driver is for: chips, firmware package, rating, bands
  tools/make-usb-id-table.sh   regenerates wifi-usb-ids.txt from Alpine's kernel
  mac/                         Mac side, copied into the VM folder by the installer
    wifi-failover.sh             the Wi-Fi/phone switcher (runs as root every 15 s)
    install-auto.sh              installs muta's service + the switcher (sudo)
    update-switcher.sh           reinstalls the switcher after editing it (sudo)
    autostart-vm.sh + .plist     keeps Alpine running hidden and self-heals the dongle (login + every minute)
    sshcfg                       SSH settings template for reaching Alpine as "alp"
    push-alpine-setup.sh         re-runs the Alpine setup on an existing machine (needs Alpine's Wi-Fi online)
    Alpine WiFi.vmx.reference    the original working VM settings, for comparison
  alpine/
    install.sh                   inside Alpine: firmware, helpers, network, NAT, keepalive
    files/                       wifi-join, wifi-scan-list, wifi-keepalive, wifi-adapter-info, interfaces, NAT rules
    auto/                        the unattended-install pieces used by build-vm.sh
```

**For testing changes** without touching the real machine:

```bash
MACWIFI_TEST=1 bash setup/build-vm.sh
```

This builds a separate "Alpine WiFi Test" machine at `192.168.235.101`. It doesn't attach the USB dongle and doesn't change any Mac services. Add `MACWIFI_TEST_ADAPTER=1` to hand it the dongle. That's refused while the real machine is running, so the real one never loses it. Delete the test machine's folder when you're done.

**Notes**
- Alpine's root account has no password, but SSH accepts only the key in the VM folder. The machine is reachable only from this Mac.
- The Wi-Fi country is set to `IN` in `wifi-join` and `install.sh`. Change it there if you move country.
- Alpine and its firmware come from the official Alpine Linux mirrors; muta comes from crates.io.
