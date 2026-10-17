# Wi-Fi on a Mac without working Wi-Fi: check first, then pick an option

This guide covers three questions, in order:

1. **Can this Mac use its own Wi-Fi?** If it can, you don't need this project at all.
2. **If it can't, what are the options?** A USB Wi-Fi dongle is only one of them.
3. **If you use a USB dongle, will yours work?** It needs a Linux driver, and this guide explains how to check.

The quick way to answer all three is to double-click **`Check Wi-Fi hardware.command`**. The installer runs the same check automatically as its first step. The rest of this page explains what the check looks at, what its answers mean, and what to do about each one.

---

## 1. Can this Mac use its own Wi-Fi?

### What the check looks at

| Source | What it tells us |
|---|---|
| `networksetup -listallhardwareports` | Whether macOS has a **Wi-Fi port** at all (usually `en0` on a MacBook) |
| `system_profiler SPAirPortDataType` | The Wi-Fi card, whether it's on, the network it's joined, and how many networks it can see |
| `networksetup -getairportpower` | Whether Wi-Fi is switched on or off |

### What the answers mean

| The check says | What it means | What to do |
|---|---|---|
| **Works: connected to "…"** | The built-in Wi-Fi is fine | Nothing. Use the Wi-Fi menu. The installer stops here unless you ask it to continue. |
| **On, sees N networks, not connected** | The hardware is fine; you just haven't joined a network | Pick one from the Wi-Fi menu in the menu bar |
| **Switched OFF** | Wi-Fi is turned off in macOS | The check offers to switch it on, waits 20 s, and looks again |
| **On, but sees no networks at all** | The radio may be deaf: a faulty chip or antenna, or simply no Wi-Fi nearby | Check whether a phone sees Wi-Fi in the same spot. If it does, restart the Mac once and look again. If the Mac still sees nothing, treat it as broken. |
| **Can't find its own Wi-Fi hardware** | macOS has no Wi-Fi card at all. The Wi-Fi menu says "Wi-Fi: No hardware installed". | The chip has failed or isn't connected. See section 2. |
| **Has a Wi-Fi port, but no details** | macOS didn't report the card's state | Click the Wi-Fi icon in the menu bar. If it lists networks, the built-in Wi-Fi works. |

### Checking it yourself

- **Option-click** the Wi-Fi icon in the menu bar. It shows the card's details, or "No hardware installed".
- **System Information** (hold Option, then Apple menu → System Information) → **Network → Wi-Fi**. A working Mac lists an interface such as `en0`, with its card type and nearby networks. A Mac with failed Wi-Fi shows only software versions.
- **Apple Diagnostics**: shut down, then hold the power button until "Loading startup options" appears, and press **Command-D**. Wi-Fi faults often show up here as a reference code.

> On the Mac this project was built on (MacBook Pro, M4), System Information shows **no Wi-Fi interface at all**, and `en0` is a Thunderbolt port. That's the "can't find its own Wi-Fi hardware" case.

---

## 2. Your options when the built-in Wi-Fi doesn't work

| Option | Cost | Works with macOS directly? | Good for | Downsides |
|---|---|---|---|---|
| **Phone USB tethering** | free | iPhone: yes. Android: through `muta` (this project installs it) | Anywhere with mobile data | Uses mobile data, and the phone must stay plugged in |
| **USB-C Ethernet adapter** | low | Yes, no drivers needed | Desks with a network cable | Needs a cable |
| **Travel router in "client" / "WISP" mode + Ethernet** | low–medium | Yes: the Mac just sees Ethernet | Hotels and changing places; it can handle login pages | One more box to carry and power |
| **USB Wi-Fi dongle + this project** | low | **No**: macOS on Apple silicon has no drivers for USB Wi-Fi dongles, so this project runs a tiny Linux (Alpine) in VMware Fusion to drive the dongle | Real Wi-Fi with no cables, switching back and forth with the phone automatically | Needs VMware Fusion, and a dongle Linux supports (section 3) |
| **Repair** | high | — | A permanent fix | On Apple silicon the Wi-Fi chip is part of the main board, so Apple repairs it by replacing the board |

You can combine them. This project already uses **phone tethering as an automatic backup** for the dongle.

---

## 3. Which USB Wi-Fi dongles work?

### Why the chip matters, not the brand

The Linux inside the Alpine machine has to have a **driver** for the dongle's **chip**. The brand on the box (TP-Link, Netgear, ASUS, Edimax, no-name…) doesn't decide this, and the same model name can change chips between hardware versions. What decides it is the dongle's **USB ID**, written `vendor:product`, for example `0bda:8179`.

### How to find your dongle's USB ID

- **Easiest:** plug it in and double-click `Check Wi-Fi hardware.command`. It prints the ID, the chip, the driver and a rating.
- **By hand:** Apple menu → About This Mac → More Info → System Report → **USB**. Click the dongle and read *Vendor ID* and *Product ID*.
- **Or look it up:** [`setup/data/wifi-usb-ids.txt`](../setup/data/wifi-usb-ids.txt) lists all **1,128 USB IDs** that Alpine's kernel has a Wi-Fi driver for. Search it for your ID:
  ```bash
  grep '^0bda:8179' setup/data/wifi-usb-ids.txt
  ```
  If the ID is in the file, Linux has a driver for it. If it isn't, this setup can't drive it.

That list is generated from the drivers themselves, using [`setup/tools/make-usb-id-table.sh`](../setup/tools/make-usb-id-table.sh) (Alpine 3.24.2, kernel 6.18 LTS). It's not a hand-made guess.

### Supported chip families

The installer puts firmware for **all** of these onto the Alpine machine, about 55 MB, so you can swap dongles later without reinstalling. Run `Check Wi-Fi hardware` after swapping.

**Recommended (good):**

| Chip family | Linux driver | Bands | Known IDs | Notes |
|---|---|---|---:|---|
| Realtek RTL8188EU/ETV, RTL8188CU/RU, RTL8188FU, RTL8192CU/EU/FU, RTL8723BU | `rtl8xxxu` | 2.4 GHz | 121 | **Tested on real hardware** (RTL8188EU, `0bda:8179`) |
| Realtek RTL8812BU, RTL8822BU | `rtw88_8822bu` | 2.4 + 5 GHz | 35 | |
| Realtek RTL8812AU | `rtw88_8812au` | 2.4 + 5 GHz | 34 | |
| Realtek RTL8811AU, RTL8821AU | `rtw88_8821au` | 2.4 + 5 GHz | 26 | |
| Realtek RTL8811CU, RTL8821CU | `rtw88_8821cu` | 2.4 + 5 GHz | 15 | Often arrives in "driver CD" mode (below) |
| Realtek RTL8814AU | `rtw88_8814au` | 2.4 + 5 GHz | 14 | |
| Realtek RTL8822CU | `rtw88_8822cu` | 2.4 + 5 GHz | 7 | |
| Realtek RTL8832BU, RTL8852BU (Wi-Fi 6) | `rtw89_8852bu` | 2.4 + 5 GHz | 14 | |
| Realtek RTL8851BU (Wi-Fi 6) | `rtw89_8851bu` | 2.4 + 5 GHz | 4 | |
| MediaTek MT7612U | `mt76x2u` | 2.4 + 5 GHz | 16 | One of the best-supported chips on Linux |
| MediaTek MT7610U | `mt76x0u` | 2.4 + 5 GHz | 25 | |
| MediaTek MT7921AU (Wi-Fi 6E) | `mt7921u` | 2.4 + 5 + 6 GHz | 5 | |
| Atheros AR9271, AR7010 | `ath9k_htc` | 2.4 GHz (AR7010 also 5) | 27 | Open-source firmware, very reliable |

**Works, with limits (ok):**

| Chip family | Linux driver | Bands | Known IDs | Notes |
|---|---|---|---:|---|
| Ralink / MediaTek RT2870, RT3070, RT3072, RT3572, RT5370, RT5372, RT5572 | `rt2800usb` | 2.4 GHz (RT3572/RT5572 also 5) | 334 | Older but solid |
| MediaTek MT7601U | `mt7601u` | 2.4 GHz | 17 | Very common cheap "150 Mbps" dongle |
| Realtek RTL8188CUS, RTL8192CU | `rtl8192cu` | 2.4 GHz | 72 | Older driver for the same chips as `rtl8xxxu` |
| Realtek RTL8723DU | `rtw88_8723du` | 2.4 GHz | 2 | |
| Broadcom BCM43143 / 43236 / 43242 / 43569 | `brcmfmac` | depends | 9 | Rare as USB dongles |
| Marvell 8766 / 8797 / 8801 / 8997 | `mwifiex_usb` | 2.4 + 5 GHz | 8 | Its firmware (77 MB) is added only when you choose such a dongle |

**Very old hardware:** these work, but are slow (often 802.11b/g only):

`rt73usb` (Ralink RT2571W/RT2671), `rt2500usb` (RT2570), `zd1211rw` (ZyDAS ZD1211), `rtl8187` (Realtek RTL8187), `ar5523`, `carl9170` (Atheros AR9170), `ath6kl_usb` (AR6004), `usb8xxx` / `libertas_tf_usb` (Marvell 88W8388), `rsi_usb` (Redpine RS9113).

**Not working out of the box:**

| Chip | Why |
|---|---|
| Intersil / Conexant Prism54 USB (`p54usb`) | Alpine doesn't package its firmware |
| Qualcomm Atheros QCA USB (`ath10k_usb`) | The Linux USB support is experimental |
| **AIC8800** (many cheap "AX300 / AX900 / Wi-Fi 6" dongles) | No driver in the Linux kernel |
| MediaTek **MT7925U**, Realtek **RTL8852CU / RTL8832CU** | Alpine's kernel has no USB driver for them (yet) |
| Anything not in `wifi-usb-ids.txt` | No Linux driver claims that USB ID |

### Buying one

- Look up the **chip** (search the model number plus "chipset"), then check the tables above, or check the USB ID once you have it.
- Good picks: **MT7612U**, **MT7610U**, **RTL8812BU / RTL8822BU**, **RTL8821CU**, **RTL8812AU** (all dual band); **AR9271** (2.4 GHz, rock solid).
- A dongle that only does **2.4 GHz** won't see 5 GHz-only networks. If yours seems to "see nothing", check the router's band.

### "Driver CD" mode dongles

Many Realtek RTL8811CU/8821CU dongles, and some others, first appear as a small **CD drive** holding Windows drivers (for example USB ID `0bda:1a2b`). In that mode they aren't a Wi-Fi device yet. The check recognises this and asks you to **eject that CD in Finder**. The dongle then switches to Wi-Fi mode with a new USB ID, and the check looks again.

---

## 4. Using a different dongle

1. Plug the new dongle in. You can unplug the old one.
2. Double-click **`Check Wi-Fi hardware.command`**. It:
   - identifies the dongle and says whether Linux supports it;
   - saves the choice in `~/.alpinewifi-adapter`;
   - tells VMware to hand this dongle to the Alpine machine. If Alpine is running, it's restarted for a moment.
3. Double-click **`1 Start Wi-Fi`**, then **`2 Change Wi-Fi network`**. Shortcut 2 also shows which bands your dongle can use.

If you have several supported dongles plugged in, the check asks which one Alpine should use.

---

## 5. When the dongle doesn't work

`1 Start Wi-Fi`, the installer and `0 Which internet am I on` ask Alpine what *it* sees, using the `wifi-adapter-info` helper inside Alpine, and then explain the result:

| Message | Meaning | Fix |
|---|---|---|
| **Alpine doesn't see the dongle** (`ADAPTER none`) | VMware didn't hand the dongle over | Unplug it and plug it back in. Run `Check Wi-Fi hardware` so VMware knows which dongle to give Alpine. Or in VMware Fusion: Virtual Machine → USB → connect the dongle. |
| **No Linux driver** (`ADAPTER nodriver vvvv:pppp`) | Alpine sees the USB device, but no driver claims it | This dongle won't work here. Pick one from section 3. |
| **Firmware missing** (`ADAPTER firmware …`) | The driver loaded, but its firmware file isn't installed | Run `Install Mac Wi-Fi` again while the Mac has internet. It reinstalls the firmware packages. |
| **Working** (`ADAPTER ok wlan0 <driver> <bands>`) | All good | Use `2 Change Wi-Fi network` to join a network |

To see the full details yourself:

```bash
ssh -F "$HOME/Virtual Machines.localized/Alpine WiFi.vmwarevm/sshcfg" alp wifi-adapter-info
```

---

## What has actually been tested

- **Real hardware:** Realtek **RTL8188EU** (`0bda:8179`, driver `rtl8xxxu`) on a MacBook Pro M4 with no working built-in Wi-Fi. The check identified it, Alpine drove it, and it joined a 2.4 GHz network.
- **On a freshly built test machine:** all the firmware above is installed. Every listed driver has its firmware files present, except the "not working out of the box" ones, and Bluetooth-only files that Wi-Fi doesn't need.
- **Built-in Wi-Fi check:** tested on this Mac (no hardware), and with sample data for the connected, off, idle and "sees nothing" states.
- **Not tested on real hardware:** every other chip. They're expected to work because Alpine's kernel ships a driver for their exact USB ID, plus the firmware. If you try one, please report the result.
