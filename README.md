# B8X OC · Extreme

Unofficial iOS BLE controller and protocol research app for the Flydigi B8X phone cooler.

## Current implementation

- Four redesigned app sections: Overview, Controls, Devices, and Diagnostics.
- Scan nearby Bluetooth Low Energy peripherals and connect to a selected device.
- Discover the B8X GATT service and characteristics.
- Subscribe to status notifications and decode the 20-byte status frame.
- Display cold-side and hot-side temperatures, measured fan RPM, light state, mode, and the raw frame in hexadecimal.
- Read the latest status before each control write and wait for a matching device notification before reporting success.
- Fan target range is 1–6,000 RPM with 1 RPM resolution and no fixed slider step. The public reference validates ordinary settings only through 4,500 RPM; values below 4,000 RPM and above 4,500 RPM are experimental and need hardware verification. Applying a fixed RPM target also selects manual mode.
- Cooling target range is 1–255 raw levels with 1-level resolution. The public reference validates 92–175; values outside that range are experimental and are not guaranteed across B8X firmware revisions. Slider movement provides rate-limited haptic feedback.
- Run protocol unit tests with SwiftPM in GitHub Actions before the Xcode iOS build and unsigned IPA packaging.

## Current protocol reference

Implementation is based on the public reference project: https://github.com/shaoyou11/ha-flydigi-b8x

- Service: FFE0
- Write characteristic: FFE1
- Notify characteristic: FFE4
- Status query byte: 13
- Status frame: 20 bytes, starting with 13
- Fan setting: 1–6000 RPM, encoded as base-100 plus remainder. The app accepts integer RPM values; device support for the full range and 1 RPM changes must be verified on hardware.
- Cooling setting: app target range 1–255, encoded as one byte. The public reference validates 92–175; values outside it are experimental. This is not a wattage, temperature, or percentage.
- Modes: automatic and manual.

The app permits reducing an already-reported fan setting above 6,000 RPM to 6,000 RPM or less. Other controls are blocked while the reported fan setting remains above the app's new ceiling, so another control cannot silently preserve an above-limit fan setting.

See the protocol research notes for decoded byte offsets, packet format, unknown fields, and a practical capture procedure.

## GitHub Actions IPA build

Source or test changes automatically trigger the Build iOS IPA workflow.

1. Open the Actions tab at https://github.com/maguc98/B8X-OC-Extreme-/actions.
2. Select the latest Build iOS IPA run.
3. Wait for protocol tests and the iOS build to complete.
4. Download the B8X-OC-Extreme-unsigned-IPA artifact.

The artifact is unsigned and is not directly installable until signed with a valid Apple development or distribution certificate and provisioning profile. No signing keys are stored in this repository or workflow.

## Local build

Requires Swift 5.9+, macOS, Xcode, and XcodeGen.

    swift test
    brew install xcodegen
    xcodegen generate
    xcodebuild -project B8XOC.xcodeproj -scheme B8XOC -configuration Release -sdk iphoneos build

## Safety and limitations

- Fan settings outside the public reference's ordinary range (below 4000 or above 4500 RPM) are experimental; the app-side limits are 1–6000 RPM.
- Cooling settings outside the reference-validated 92–175 range are experimental; the app-side limits are 1–255.
- No firmware update, factory reset, or thermal-protection bypass is implemented.
- The reference project has not established that the full fan or cooling ranges are supported by all B8X firmware revisions.
- Keep the cooler's original thermal protections enabled.
- Watch for condensation when cooling below the ambient dew point.

## License

No license has been selected yet.
