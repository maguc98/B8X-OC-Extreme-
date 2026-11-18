# B8X OC · Extreme

Unofficial iOS BLE controller and protocol research app for the Flydigi B8X phone cooler.

## Current implementation

- Scan nearby Bluetooth Low Energy peripherals and connect to a selected device.
- Discover the B8X GATT service and characteristics.
- Subscribe to status notifications and decode the 20-byte status frame.
- Display cold-side and hot-side temperatures, measured fan RPM, light state, mode, and the raw frame in hexadecimal.
- Read the latest status before each control write.
- Wait for a matching device notification before reporting a control as confirmed.
- Run protocol unit tests with SwiftPM in GitHub Actions before the Xcode iOS build and unsigned IPA packaging.

## Current protocol reference

Implementation is based on the public reference project: https://github.com/shaoyou11/ha-flydigi-b8x

- Service: FFE0
- Write characteristic: FFE1
- Notify characteristic: FFE4
- Status query byte: 13
- Status frame: 20 bytes, starting with 13

The reference project documents these normal control ranges:

- Fan setting: 4000–8000 RPM, encoded as base-100 plus remainder; the iOS slider uses 1 RPM steps. The expanded range is a test interface and has not been verified on all B8X firmware revisions.
- Cooling setting: one-byte raw protocol value 92–255. This is not a wattage, temperature, or percentage. A value of 300 cannot fit the currently decoded one-byte field and is not sent.
- Modes: automatic and manual.

These are the only control ranges exposed by this build. Measured fan RPM is reported separately from the fan setting.

See [protocol research notes](Docs/PROTOCOL-RESEARCH.md) for the currently decoded byte offsets, packet format, unknown fields, and a practical capture procedure.

## GitHub Actions IPA build

Source or test changes automatically trigger the Build iOS IPA workflow.

1. Open the [Actions tab](https://github.com/maguc98/B8X-OC-Extreme-/actions).
2. Select the latest Build iOS IPA run.
3. Wait for the protocol tests and macOS build to complete.
4. Download the `B8X-OC-Extreme-unsigned-IPA` artifact.

The artifact is unsigned and is not directly installable until signed with a valid Apple development or distribution certificate and provisioning profile. No signing keys are stored in this repository or workflow.

## Local build

Requires Swift 5.9+, macOS, Xcode, and XcodeGen.

    swift test
    brew install xcodegen
    xcodegen generate
    xcodebuild -project B8XOC.xcodeproj -scheme B8XOC -configuration Release -sdk iphoneos build

## Safety and limitations

- No undocumented overclock values are written.
- No firmware update, factory reset, or thermal-protection bypass is implemented.
- The reference project has not established that higher fan or cooling values are supported by all B8X firmware revisions.
- Keep the cooler's original thermal protections enabled.
- Watch for condensation when cooling below the ambient dew point.

## License

No license has been selected yet.
