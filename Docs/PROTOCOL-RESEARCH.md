# B8X protocol research notes

This document records the currently implemented protocol observations. It is not a claim that undocumented overclocking values are supported.

## GATT

| Item | UUID |
|---|---|
| Service | 0000FFE0-0000-1000-8000-00805F9B34FB |
| Write characteristic | 0000FFE1-0000-1000-8000-00805F9B34FB |
| Notify characteristic | 0000FFE4-0000-1000-8000-00805F9B34FB |

Status query: one byte 13.

## Status notification

The reference implementation expects a 20-byte frame beginning with 13. The iOS app currently decodes:

| Offset | Meaning in current implementation |
|---:|---|
| 0 | Frame marker, 13 |
| 2, high nibble | Mode: 0 automatic, 1 manual |
| 3 | Cooling raw setting |
| 4–5 | Fan setting: byte 4 × 100 + byte 5; byte 5 must be 0–99 |
| 7 | Signed cold-side temperature integer |
| 8 | Cold-side decimal digit (0–9) |
| 9 | Signed hot-side temperature integer |
| 12–13 | Measured fan RPM: byte 12 × 100 + byte 13; byte 13 must be 0–99 |
| 14 | Light state: 255 on, 0 off |

Byte 8 is validated as 0–9, and byte 14 must be either 0 or 255. Other bytes are retained in the raw frame and are not assigned undocumented meanings by this app. Telemetry parsing does not clamp the reported fan setting or measured RPM, so the diagnostic page can show the device's actual reported values even when the setting exceeds the new app control ceiling.

## Control packets currently implemented

- Light: 10 FF on, 10 00 off.
- General setting packet: 20 mode cold wind/100 wind%100 status[6] 5C 28 00.

The final three fixed bytes and preserved byte are reproduced from the public reference implementation. Their hardware meaning has not been independently established here.

The current app control limits are:

- Fan setting: 4000–6000 RPM with 100 RPM steps. The public B8X reference implementation validates the normal range only through 4500 RPM in 100 RPM increments; 4600–6000 RPM is an app-capped experimental extension and is not confirmed on this hardware. Applying a fixed fan target now sets mode 1 (manual) in the same command packet.
- If the device reports a current fan setting above 6000 RPM but no higher than 8000 RPM, the fan command path permits a new fan command within 4000–6000 RPM so the user can lower it. While the reported setting remains above 6000 RPM, mode and cooling changes are blocked because their packets would preserve that above-limit fan setting.
- Cooling raw setting: a single byte at offset 3. The reference implementation validates 92–175; the app now restricts the control slider and encoder to that range. Do not infer watts, temperature, or percentage from this raw value.
- Mode: 0 automatic, 1 manual.

The public reference project documents the B8X control protocol; the 6000 RPM application limit is a conservative app-side cap, not a claim that the hardware cannot report or otherwise support a higher value.

**Do not interpret the cooling raw setting as watts, temperature, or a percentage.** No temperature-protection bypass is implemented.

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

- Keep fan targets at or below the app's 6000 RPM ceiling. The 4600–6000 RPM extension is not validated by the public reference; do not treat it as a confirmed device capability.
- Do not bypass the cooler's firmware thermal limits.
- Stop testing if temperatures behave unexpectedly, the fan stalls, or the cooler becomes unstable.
- Cooling below the ambient dew point can cause condensation and damage the phone.


## B8X lighting and firmware research

The official Game Center App Store version history records B8X always-on lighting in version 5.1.39 (2025-06-10) and B8X co-branded skins in versions 5.1.39 / 5.2.0. The official B8X help page also documents double-pressing the physical button to switch lighting effects. The accompanying user-provided screenshot shows the Game Center lighting page exposing these effect labels: variable-speed rotation, flowing light, breathing, gradient, switching, multicolor rotation, jumping, and steady; it also shows color selection/favorites, speed and brightness controls.

The currently verified B8X BLE implementation in this repository still knows only:
- Light on: `10 FF`
- Light off: `10 00`
- Status byte 14: `FF` on / `00` off

The 20-byte B8X status decoder does not currently assign mode, RGB, speed, or brightness fields. No B8X-specific write packet for those settings has been established. Do not infer their packet structure from the UI alone.

A separate community protocol reference for Flydigi BS1 / BS2 / BS2 Pro describes a different BLE transport (service FFF0, write FFF2, notify FFF1, frame header 5A A5). B8X in this project uses service FFE0, write FFE1, notify FFE4 and a different 20-byte status frame. The BS1/BS2 protocol is therefore not interchangeable and must not be sent to a B8X.

No reliable B8X-specific firmware metadata read, DFU service, signed firmware resource, checksum/signature validation flow, or recovery mode has been identified yet. Firmware update must remain disabled until these are evidenced for B8X hardware specifically.


## Read-only device discovery and evidence capture

The iOS diagnostic page now enumerates all GATT services and their characteristic properties without writing to unknown services. It also attempts reads only for the standard Bluetooth Device Information service `180A`, and only for standard readable characteristics:
- `2A24`: Model Number String
- `2A26`: Firmware Revision String
- `2A29`: Manufacturer Name String

If these values are absent, the UI reports that the device did not publish them; this does not prove that a firmware version is not stored elsewhere internally. The app does not read arbitrary vendor-specific characteristics.

The app retains up to 64 consecutive 20-byte status notifications, timestamps them, computes changed byte offsets between consecutive frames, and can export the capture. This enables controlled comparison of the B8X status frame before and after using the physical double-press lighting shortcut documented in the B8X user guide. Refresh the status after each physical action if the cooler does not emit an unsolicited notification.

Suggested capture sequence:
1. Connect to B8X and open Diagnostics.
2. Clear samples, then request status once and export or note the initial frame.
3. Double-press the cooler's physical key once to change lighting mode.
4. Request status again; record changed byte offsets and the new raw frame.
5. Repeat several times, changing only the lighting effect using the physical key.
6. Export the full capture and share it for analysis.

This test can reveal whether lighting mode is represented in the existing status frame. It cannot, by itself, reveal RGB, speed, or brightness write packets.

## Firmware-update evidence status

The public B8X product help page documents button functions and lighting-effect switching, but the publicly indexed B8X-specific material reviewed so far does not document a firmware-update sequence, firmware image, bootloader/DFU service, or recovery method. The official Flydigi community firmware tutorial found during research is explicitly titled as a controller firmware-upgrade tutorial, not a B8X cooler firmware procedure.

Therefore:
- A discovered GATT service with an unfamiliar UUID is evidence only that the service is advertised; it is not proof that it is a DFU service.
- Standard Device Information firmware revision (2A26), if exposed, is safe to display as metadata but does not imply an update method.
- Do not send guessed DFU commands, switch the cooler into an unknown boot mode, or attempt firmware writes until a B8X-specific firmware package, target compatibility, checksum/signature requirements, packet/acknowledgement sequence, interruption behavior, and recovery path are independently established.
