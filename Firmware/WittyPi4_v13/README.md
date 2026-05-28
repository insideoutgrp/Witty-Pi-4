# Witty Pi 4 Firmware — Revision 13

Shippable Arduino sketch folder for flashing onto Witty Pi 4 hardware.

## What's in here

| File | Purpose |
|------|---------|
| `WittyPi4_v13.ino` | The Rev 13 firmware source (~1040 lines) |
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

## Rev 13 highlights

| Area | Change |
|---|---|
| **Reliability** | `sleep()` moved out of Timer1 ISR (deferred to `loop()` via `pendingSleep` flag) — eliminates SRAM stack-nesting risk |
| **Reliability** | `internalBusBusy` mutex guards the softWireMaster between WDT ISR and Pi I²C transactions |
| **Reliability** | Alarm overdue window widened from 4s to 86400s (1 day) to absorb jitter / interrupted writes |
| **Power** | `DEFAULT_ON=1` enforced every boot in `initializeRegisters()` — overrides any persisted EEPROM value. Any DC applied → Pi wakes |
| **Power** | `RECOVERY_VOLTAGE` default = 30 (3.0V) so brand-new units recover from LV-shutdown on any reasonable DC input |
| **Button safety** | Physical button shutdown removed entirely. Firmware never drives PIN_BUTTON. Accidental knocks / shorts on the shared button/GPIO-4 line cannot affect a running Pi |
| **Button** | Manual wake from sleep preserved as a maintenance override |
| **Flash** | Temperature-action shutdown code removed (registers 43–46 reserved). Sleep-loop LED blink removed (saves battery) |
| **FW Revision** | `I2C_FW_REVISION` = 0x0D (13) |

## After flashing

Deploy the matching Pi-side software with:

```bash
curl -sSL https://raw.githubusercontent.com/insideoutgrp/Witty-Pi-4/firmware-rev13/Software/deploy.sh | sudo bash
```

The deploy script does a pre-flight `i2cget` and refuses to install on devices running firmware < Rev 13 — so you can't accidentally cross-deploy.
