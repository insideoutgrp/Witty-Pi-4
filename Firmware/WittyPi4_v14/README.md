# Witty Pi 4 Firmware — Revision 14

Shippable Arduino sketch folder for flashing onto Witty Pi 4 hardware.

## What's in here

| File | Purpose |
|------|---------|
| `WittyPi4_v14.ino` | The Rev 14 firmware source (~1040 lines) |
| `SoftIICMaster.h`, `SoftWireMaster.h` | Software I²C master headers used by the firmware |

This is a snapshot of `Firmware/WittyPi4/WittyPi4.ino` packaged in an Arduino-compatible sketch folder (folder name must match the `.ino` name).

## Build settings

- **Board:** ATtiny841 (Internal 8 MHz) via [ATtinyCore](https://github.com/SpenceKonde/ATTinyCore)
- **Programmer:** any USBasp / Arduino-as-ISP / similar
- Cache clearing tip (macOS, after edits):
  ```bash
  rm -rf ~/Library/Caches/arduino/sketches/*/
  ```

Detailed engineering context, register map, and pin map are in `../PROJECT_CONTEXT.md`.

## What changed (vs Rev 12)

### Rev 14 (final) — Physical button shutdown removed
| Area | Change |
|---|---|
| **Button safety** | Physical button shutdown removed entirely. Firmware never drives PIN_BUTTON. Accidental knocks, shorts, or EMI on the shared button/GPIO-4 line cannot affect a running Pi |
| **Button** | Manual wake from sleep preserved as a maintenance override (`!powerIsOn` path in PCINT1) |
| **Alarm wake** | Uses `wakeupByWatchdog = false` directly instead of pulsing PIN_BUTTON |
| **Shutdown** | Alarm2 / LV shutdowns drive `turningOff` + Timer1 directly, no PIN_BUTTON pulse |
| **Removed** | `emulateButtonClick()` function and `isButtonClickEmulated` flag |

### Rev 13 — Field reliability + any-power-input-wakes
| Area | Change |
|---|---|
| **Reliability** | `sleep()` moved out of Timer1 ISR (deferred to `loop()` via `pendingSleep` flag) — eliminates SRAM stack-nesting risk |
| **Reliability** | `internalBusBusy` mutex guards the softWireMaster between WDT ISR and Pi I²C transactions |
| **Reliability** | Alarm overdue window widened from 4s to 86400s (1 day) to absorb jitter / interrupted writes |
| **Power** | `DEFAULT_ON=1` enforced every boot in `initializeRegisters()` — overrides any persisted EEPROM value. Any DC applied → Pi wakes |
| **Power** | `RECOVERY_VOLTAGE` default = 30 (3.0V) so brand-new units recover from LV-shutdown on any reasonable DC input |
| **Flash** | Temperature-action shutdown code removed (registers 43–46 reserved). Sleep-loop LED blink removed (saves battery) |

`I2C_FW_REVISION` = `0x0E` (14).

## After flashing

Deploy the matching Pi-side software with:

```bash
curl -sSL https://raw.githubusercontent.com/insideoutgrp/Witty-Pi-4/firmware-rev14/Software/deploy.sh | sudo bash
```

The deploy script does a pre-flight `i2cget` and refuses to install on devices running firmware < Rev 14 — so you can't accidentally cross-deploy.
