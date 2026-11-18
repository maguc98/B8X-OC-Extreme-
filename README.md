# B8X OC · Extreme

Unofficial iOS BLE companion for the Flydigi B8X phone cooler.

## Current stage

This repository starts with a safe protocol-discovery app:

- Scan nearby Bluetooth Low Energy peripherals.
- Connect to a selected peripheral.
- Enumerate GATT services and characteristics.
- Display characteristic properties for protocol research.
- No unknown control writes, firmware updates, or protection bypasses.

The B8X protocol reference is https://github.com/shaoyou11/ha-flydigi-b8x. Its documented ranges are evidence for that implementation, not proof that undocumented values or higher limits are supported by every B8X firmware revision.

## Build an IPA with GitHub Actions

1. Open Actions in this repository.
2. Select Build iOS IPA.
3. Choose Run workflow.
4. Download the B8X-OC-Extreme-unsigned-IPA artifact from the completed run.

The artifact is an unsigned IPA. It is not directly installable until signed with a valid Apple development or distribution certificate and provisioning profile. No signing keys are stored in this repository or workflow.

## Local build

Requires macOS, Xcode, and XcodeGen.

    brew install xcodegen
    xcodegen generate
    xcodebuild -project B8XOC.xcodeproj -scheme B8XOC -sdk iphoneos build

## Safety

The app does not claim unverified fan RPM or cooling-power limits. Do not bypass the cooler's thermal protections. Condensation can damage a phone when cooling below the ambient dew point.

## License

No license has been selected yet.
