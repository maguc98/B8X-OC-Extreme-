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


## User capture: 2026-11-18 21:34:54–21:35:07

A user-provided diagnostic capture from a connected device named Flydigi B8X contains 14 consecutive 20-byte status frames. The final frame is:

`13 00 12 5C 3C 00 06 FF 03 2D 5C E9 39 00 FF 03 01 02 00 00`

Evidence and interpretation:
- Offset 8 varies through values such as 09, 07, 03 and is already decoded by this implementation as the cold-side temperature decimal digit. It must not be treated as an unassigned lighting field.
- Offset 7 and offset 8 jointly form the cold-side temperature reading under the existing decoder; offset 9 is the hot-side temperature integer.
- Offset 14 remains FF in this capture, consistent with the existing light-enabled flag.
- Offset 15 varies across the capture (observed values include 06, 0B, 11, 10, and 03). Its meaning remains unknown. This capture alone does not establish a relationship with lighting effects because it does not include a timestamped physical lighting-mode change boundary or a controlled before/after pair.
- The final decoded fan setting is 6000 RPM and measured fan RPM is 5700 RPM. The device reports the high-temperature protection message and a 6000 RPM fan request; do not infer from this log alone that the cooler physically reached the target.
- Device metadata is displayed as the literal labels `Model Number`, `Manufacturer Name`, and `Firmware Revision`, rather than actual values. Treat these as unresolved metadata-read/UI behavior, not verified model or firmware strings.

Next safe experiment: clear capture history, record a baseline frame, double-press the physical B8X key exactly once, then request/record a fresh status frame. Repeat the single action several times and compare all offsets. Until a repeatable correlation is observed, do not assign offset 15 a lighting meaning and do not send writes to unknown fields.


## User capture: 2026-11-18 21:37:32–21:38:02

A second user-provided capture contains 31 consecutive 20-byte status frames. Key observations:
- `byte[14]` remains `FF` throughout: the light-enabled state did not change in this capture.
- `byte[15]` varies repeatedly through values including `03`, `05`, `04`, `06`, `10`, `11`, and `0B`. Several values recur in a repeating-looking sequence, but there is no controlled timestamp marker for the physical double-press in the capture. Its meaning remains unknown; do not decode it as a lighting mode yet.
- `byte[8]` continues to vary from `00` to `09` and remains the cold-temperature fractional digit in the existing decoder.
- `byte[3]` is `FF` (255) throughout this capture, whereas the known normal control range documented by the reference is 92–175. The app's prior control validator mistakenly allowed 92–255 and could preserve/send this anomalous value in non-light control packets. This has now been tightened: telemetry still displays the raw value 255, but mode, wind, and cooling control commands are blocked when the current reported cooling value is outside 92–175; requested cooling values are also limited to 92–175. Light on/off remains available because its packet does not preserve cooling settings.
- `byte[9]` is `2A` (42°C) in the final frame. The high-temperature protection message can remain latched at 42°C because the current implementation clears that latch only below 42°C; the message is not proof that the final frame is at or above the 45°C trigger threshold.
- Fan target remains 6000 RPM and measured RPM 5700 RPM in the final frame.

This capture is not sufficient to prove that the physical button changed lighting mode or to identify a lighting write packet. For a valid correlation test, note the exact time of one physical double-press, capture at least 3 seconds before and after, and repeat the same single action. Avoid all fan/cooling/mode controls while `byte[3]` reports 255; do not attempt to normalize or rewrite this raw value without a verified device procedure.


### Follow-up confirmation: physical key action during 21:37–21:38 capture

The user confirmed that the physical B8X button was indeed double-pressed during the 2026-11-18 21:37:32–21:38:02 capture. This confirms that the capture window includes a real physical-button action, correcting the earlier uncertainty about whether any action occurred.

However, the capture does not contain an event timestamp identifying the exact frame at which the double-press occurred, nor does it isolate a before/after transition. Offset 15 remains a candidate for further investigation because it changes during the capture, but its cycling values cannot yet be attributed to the double-press or interpreted as lighting modes. Offset 14 remains FF, so the light-enabled flag did not change. Do not infer a lighting command or send writes based on this correlation alone.

Next experiment: clear the sample buffer, record a baseline, perform exactly one double-press while noting its wall-clock time, then immediately request a status frame; repeat at least three times with separate captures. Compare the frame immediately before and after each action. Continue to avoid cooling/mode controls while byte[3] is 255.
