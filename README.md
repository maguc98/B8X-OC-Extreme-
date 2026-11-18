# B8X OC · Extreme

Unofficial iOS BLE controller and protocol research app for the Flydigi B8X phone cooler.

## Implemented in the first development stage

- Scan nearby Bluetooth Low Energy peripherals.
- Connect to a selected peripheral.
- Discover the verified B8X GATT service and characteristics.
- Subscribe to B8X status notifications.
- Decode the 20-byte status frame into cold-side temperature, hot-side temperature, measured fan RPM, light state, wind setting, cooling setting, and mode.
- Read the latest status before every control write.
- Send supported light, mode, fan-setting, and cooling-setting commands.
- Wait for a matching device status notification before reporting a control as confirmed.

## Verified protocol reference

Protocol implementation is based on https://github.com/shaoyou11/ha-flydigi-b8x

- Service: FFE0
- Write characteristic: FFE1
- Notify characteristic: FFE4
- Status query byte: 13
- Status frame: 20 bytes, starting with 13

The reference project documents these normal control ranges:

- Fan setting: 4000–4500 RPM, step 100.
- Cooling setting: raw protocol value 92–175. This is not a wattage, temperature, or percentage.
- Modes: automatic and manual.

These are the only control ranges exposed by this build. Measured fan RPM is reported separately from the fan setting.

## GitHub Actions IPA build

Source changes automatically trigger the Build iOS IPA workflow.

1. Open the Actions tab.
2. Select the latest Build iOS IPA run.
3. Wait for the macOS build to complete.
4. Download the B8X-OC-Extreme-unsigned-IPA artifact.

The artifact is an unsigned IPA. It is not directly installable until signed with a valid Apple development or distribution certificate and provisioning profile. No signing keys are stored in this repository or workflow.

You can also start the workflow manually from Actions using Run workflow.

## Local build

Requires macOS, Xcode, and XcodeGen.

    brew install xcodegen
    xcodegen generate
    xcodebuild -project B8XOC.xcodeproj -scheme B8XOC -sdk iphoneos build

## Safety and limitations

- No undocumented overclock values are written.
- No firmware update, factory reset, or thermal-protection bypass is implemented.
- The reference project has not established that higher fan or cooling values are supported by all B8X firmware revisions.
- Keep the cooler's original thermal protections enabled.
- Watch for condensation when cooling below the ambient dew point.

## License

No license has been selected yet.
