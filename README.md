# AR9271 Magisk Module Skill

Build `.ko` kernel modules (e.g. AR9271 / ath9k_htc USB WiFi) against the **running** Android kernel and package them as a Magisk module — **no full kernel rebuild required**.

Tested on: Moto G22 (hawaiip, MT6765/Helio G37, kernel 4.19.188) — but the flow works on any device with `CONFIG_MODULES=y` and `/proc/config.gz`.

**Status: VERIFIED WORKING** — AR9271 plug-and-play: firmware loads, HTC initializes (33 credits), interface `wlan1` comes up, EEPROM read. Monitor mode + injection test ready via Nethunter (`airmon-ng start wlan1` → `aireplay-ng --test mon0`).

## Why this approach

- Stock kernels usually don't ship ath9k_htc (or any external WiFi driver)
- A full custom kernel rebuild is risky on MediaTek devices (proprietary MTK drivers → bootloop)
- This method only compiles the missing driver as a `.ko` against the exact running kernel config and loads it at boot via a Magisk module — the kernel itself never changes

## The workflow (summary)

1. Check `CONFIG_MODULES=y` + `/proc/config.gz` on the device
2. Extract the exact running kernel config (watch out for CRLF from adb!)
3. Clone the kernel source, find the running commit (`uname -r` suffix `-g<hash>`)
4. Enable the driver as `=m`, remove problematic `select`s (`MAC80211_LEDS` is the classic trap)
5. Fix vermagic to match the running kernel exactly (`CONFIG_LOCALVERSION` + hide `.git`)
6. `modules_prepare` + `make M=<dir> modules`
7. Verify vermagic/CRCs against a stock `.ko` pulled from the device
8. Test live with `insmod` (no reboot needed)
9. Package into a Magisk module (module.prop + service.sh + system/)
10. Install, reboot, verify

## Files

- `SKILL.md` — full step-by-step guide with all 15 pitfalls we hit (CRLF, MAC80211_LEDS select, vermagic `+`, clang `-Werror`, insmod order, modversions CRC validation, MTK wmi.c + htc_hst.c double-frees, module_layout CRC check, stale .ko in module dir, ADB over Wi-Fi, first-plug reset timeout, live test, etc.)
- `templates/module.prop` — Magisk module metadata
- `templates/service.sh` — boot-time insmod in correct dependency order
- `scripts/build.sh` — downloads htc_9271.fw from the Debian firmware-atheros package
- `scripts/extract_crcs.py` — validates modversions CRCs against a stock .ko before flashing

## Quick verification after boot

```
lsmod | grep ath9k
dmesg | grep -iE "ath9k|htc"     # expect: "usbcore: registered new interface driver ath9k_htc"
ip link | grep wlan              # wlan1 = AR9271 (wlan0 is the built-in MTK wifi)
```

Then in Kali Nethunter:

```
bootkali
airmon-ng start wlan1
aireplay-ng --test mon0          # "Injection is working!" = monitor + injection OK
```

## License

MIT
