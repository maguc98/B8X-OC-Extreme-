# B8X protocol research notes

This document records the currently implemented protocol observations. It is not a claim that undocumented overclocking values are supported.

## GATT

| Item | UUID |
|---|---|
| Service | `0000FFE0-0000-1000-8000-00805F9B34FB` |
| Write characteristic | `0000FFE1-0000-1000-8000-00805F9B34FB` |
| Notify characteristic | `0000FFE4-0000-1000-8000-00805F9B34FB` |

Status query: one byte `13`.

## Status notification

The reference implementation expects a 20-byte frame beginning with `13`. The iOS app currently decodes:

| Offset | Meaning in current implementation |
|---:|---|
| 0 | Frame marker, `13` |
| 2, high nibble | Mode: 0 automatic, 1 manual |
| 3 | Cooling raw setting |
| 4–5 | Fan setting: byte 4 × 100 + byte 5 |
| 7 | Signed cold-side temperature integer |
| 8 | Cold-side decimal digit (0–9) |
| 9 | Signed hot-side temperature integer |
| 12–13 | Measured fan RPM: byte 12 × 100 + byte 13 |
| 14 | Light state: 255 on, 0 off |

Other bytes are retained in the raw frame and are not assigned undocumented meanings by this app.

## Control packets currently implemented

- Light: `10 FF` on, `10 00` off.
- General setting packet: `20 mode cold wind/100 wind%100 status[6] 5C 28 00`.

The final three fixed bytes and preserved byte are reproduced from the public reference implementation. Their hardware meaning has not been independently established here.

The public reference documents only these normal settings:

- Fan setting: 4000–4500 RPM in steps of 100.
- Cooling raw setting: 92–175.
- Mode: 0 automatic, 1 manual.

**Do not interpret the cooling raw setting as watts, temperature, or a percentage.** This repository deliberately rejects values outside the reference ranges. No evidence currently establishes a safe or supported overclock range.

## How to capture useful device evidence

When testing with a real B8X:

1. Connect the phone to the cooler and wait until the app reports that status notifications are subscribed.
2. Copy the displayed 20-byte raw status frame before changing anything.
3. Record the visible app settings and measured fan RPM at the same time.
4. Change only one normal setting by one step, wait for the device's confirmation notification, then copy the new frame.
5. Repeat at a few ordinary settings, keeping the phone workload, ambient conditions, and cooler placement as consistent as practical.
6. Include the B8X hardware/firmware version if the official app exposes it.

Please redact Bluetooth identifiers or other personal identifiers before sharing captures. A single frame is useful for checking parsing; paired before/after frames are much more useful for identifying field changes.

## Safety boundaries

- Do not send guessed values above the documented ranges.
- Do not bypass the cooler's firmware thermal limits.
- Stop testing if temperatures behave unexpectedly, the fan stalls, or the cooler becomes unstable.
- Cooling below the ambient dew point can cause condensation and damage the phone.
