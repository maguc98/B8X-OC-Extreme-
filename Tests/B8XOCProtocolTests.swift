import XCTest
@testable import B8XOC

final class B8XOCProtocolTests: XCTestCase {
    private func sampleFrame(
        mode: UInt8 = 0x10,
        coldInteger: UInt8 = 24,
        coldFraction: UInt8 = 5,
        hot: UInt8 = 38,
        windHundreds: UInt8 = 42,
        windRemainder: UInt8 = 0,
        fanHundreds: UInt8 = 41,
        fanRemainder: UInt8 = 25,
        light: UInt8 = 255,
        coldLevel: UInt8 = 110,
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0] = 0x13
        bytes[2] = mode
        bytes[3] = coldLevel
        bytes[4] = windHundreds
        bytes[5] = windRemainder
        bytes[7] = coldInteger
        bytes[8] = coldFraction
        bytes[9] = hot
        bytes[12] = fanHundreds
        bytes[13] = fanRemainder
        bytes[14] = light
        return Data(bytes)
    }

    func testDecodesTelemetryAndRawFrame() throws {
        let frame = sampleFrame()
        let status = try B8XStatus.decode(frame)
        XCTAssertEqual(status.coldTemperature, 24.5, accuracy: 0.001)
        XCTAssertEqual(status.hotTemperature, 38)
        XCTAssertEqual(status.windLevel, 4200)
        XCTAssertEqual(status.fanRPM, 4125)
        XCTAssertTrue(status.lightEnabled)
        XCTAssertEqual(status.modeRaw, 1)
        XCTAssertEqual(status.coldLevel, 110)
        XCTAssertEqual(status.raw, [UInt8](frame))
    }


    func testLightControlPacketsMatchB8XReferenceAndConfirmReportedState() throws {
        let before = try B8XStatus.decode(sampleFrame(light: 255))
        let turnOff = B8XControl.light(false)
        XCTAssertEqual(try turnOff.packet(using: before), Data([0x10, 0x00]))
        let afterOff = try B8XStatus.decode(sampleFrame(light: 0))
        XCTAssertTrue(try turnOff.expectedStatus(from: before).matches(afterOff))

        let beforeOff = try B8XStatus.decode(sampleFrame(light: 0))
        let turnOn = B8XControl.light(true)
        XCTAssertEqual(try turnOn.packet(using: beforeOff), Data([0x10, 0xFF]))
        let afterOn = try B8XStatus.decode(sampleFrame(light: 255))
        XCTAssertTrue(try turnOn.expectedStatus(from: beforeOff).matches(afterOn))
    }

    func testAutomaticModeDetectionForThermalProtection() throws {
        let automatic = try B8XStatus.decode(sampleFrame(mode: 0x00))
        let manual = try B8XStatus.decode(sampleFrame(mode: 0x10))
        XCTAssertTrue(automatic.isAutomaticMode)
        XCTAssertFalse(manual.isAutomaticMode)
    }

    func testDecodesNegativeColdTemperature() throws {
        let status = try B8XStatus.decode(sampleFrame(coldInteger: 0xFF, coldFraction: 3))
        XCTAssertEqual(status.coldTemperature, -0.7, accuracy: 0.001)
    }

    func testRejectsWrongFrameLengthAndCommand() {
        XCTAssertThrowsError(try B8XStatus.decode(Data([0x13])))
        var bytes = [UInt8](sampleFrame())
        bytes[0] = 0x20
        XCTAssertThrowsError(try B8XStatus.decode(Data(bytes)))
    }

    func testRejectsInvalidFields() {
        XCTAssertThrowsError(try B8XStatus.decode(sampleFrame(coldFraction: 10)))
        XCTAssertThrowsError(try B8XStatus.decode(sampleFrame(light: 1)))
        XCTAssertThrowsError(try B8XStatus.decode(sampleFrame(windRemainder: 100)))
        XCTAssertThrowsError(try B8XStatus.decode(sampleFrame(fanRemainder: 100)))
    }

    func testControlPacketsRespectSixThousandRPMAndByteCoolingRange() throws {
        let status = try B8XStatus.decode(sampleFrame())
        XCTAssertEqual(try B8XControl.wind(6000).packet(using: status),
                       Data([0x20, 1, 110, 60, 0, 0, 92, 40, 0]))
        XCTAssertEqual(try B8XControl.wind(1).packet(using: status),
                       Data([0x20, 1, 110, 0, 1, 0, 92, 40, 0]))
        XCTAssertEqual(try B8XControl.cold(1).packet(using: status),
                       Data([0x20, 1, 1, 42, 0, 0, 92, 40, 0]))
        XCTAssertEqual(try B8XControl.cold(255).packet(using: status),
                       Data([0x20, 1, 255, 42, 0, 0, 92, 40, 0]))
        XCTAssertEqual(try B8XControl.light(false).packet(using: status),
                       Data([0x10, 0x00]))
    }

    func testCombinedSettingsWriteBothTargetsAndReplaceAnomalousCoolingTelemetry() throws {
        let anomalous = try B8XStatus.decode(sampleFrame(windHundreds: 60, coldLevel: 255))
        let control = B8XControl.settings(wind: 5200, cold: 120)
        XCTAssertEqual(try control.packet(using: anomalous),
                       Data([0x20, 1, 120, 52, 0, 0, 92, 40, 0]))
        let expected = try control.expectedStatus(from: anomalous)
        let confirmed = try B8XStatus.decode(sampleFrame(mode: 0x10, windHundreds: 52, coldLevel: 120))
        XCTAssertTrue(expected.matches(confirmed))
        XCTAssertEqual(try B8XControl.settings(wind: 5210, cold: 120).packet(using: anomalous),
                       Data([0x20, 1, 120, 52, 10, 0, 92, 40, 0]))
        XCTAssertThrowsError(try B8XControl.settings(wind: 6001, cold: 120).packet(using: anomalous))
        XCTAssertThrowsError(try B8XControl.settings(wind: 5200, cold: 256).packet(using: anomalous))
    }

    func testRejectsFanSettingsAboveSixThousandRPM() throws {
        let status = try B8XStatus.decode(sampleFrame())
        XCTAssertNoThrow(try B8XControl.wind(1).packet(using: status))
        XCTAssertNoThrow(try B8XControl.wind(4100).packet(using: status))
        XCTAssertNoThrow(try B8XControl.wind(4150).packet(using: status))
        XCTAssertNoThrow(try B8XControl.wind(6000).packet(using: status))
        XCTAssertThrowsError(try B8XControl.wind(6001).packet(using: status))
        XCTAssertNoThrow(try B8XControl.cold(1).packet(using: status))
        XCTAssertNoThrow(try B8XControl.cold(255).packet(using: status))
        XCTAssertThrowsError(try B8XControl.cold(256).packet(using: status))
    }

    func testWindControlSwitchesToManualAndAllowsSingleRPMResolution() throws {
        let automatic = try B8XStatus.decode(sampleFrame(mode: 0x00))
        let control = B8XControl.wind(4300)
        XCTAssertEqual(try control.packet(using: automatic),
                       Data([0x20, 1, 110, 43, 0, 0, 92, 40, 0]))
        let manualAfter = try B8XStatus.decode(sampleFrame(mode: 0x10, windHundreds: 43))
        XCTAssertTrue(try control.expectedStatus(from: automatic).matches(manualAfter))
        XCTAssertNoThrow(try B8XControl.wind(4310).packet(using: automatic))
    }

    func testFanCanBeReducedWhenDeviceCurrentlyReportsAboveNewCeiling() throws {
        let status = try B8XStatus.decode(sampleFrame(windHundreds: 65))
        XCTAssertNoThrow(try B8XControl.wind(6000).packet(using: status))
        XCTAssertThrowsError(try B8XControl.cold(120).packet(using: status))
        XCTAssertThrowsError(try B8XControl.mode(0).packet(using: status))
    }

    func testUnknownModeAllowsOnlyLightControl() throws {
        let status = try B8XStatus.decode(sampleFrame(mode: 0x20))
        XCTAssertNoThrow(try B8XControl.light(true).packet(using: status))
        XCTAssertThrowsError(try B8XControl.wind(4200).packet(using: status))
        XCTAssertThrowsError(try B8XControl.cold(110).packet(using: status))
    }

    func testModeChangeCannotPreserveUnverifiedCurrentSettings() throws {
        let invalidFan = try B8XStatus.decode(sampleFrame(windHundreds: 61))
        XCTAssertThrowsError(try B8XControl.mode(1).packet(using: invalidFan))
        let maxCooling = try B8XStatus.decode(sampleFrame(coldLevel: 255))
        XCTAssertNoThrow(try B8XControl.mode(1).packet(using: maxCooling))
        XCTAssertNoThrow(try B8XControl.cold(255).packet(using: maxCooling))
    }

    func testStatusExpectationMatchesOnlyRequestedAndPreservedFields() throws {
        let before = try B8XStatus.decode(sampleFrame())
        let expectation = try B8XControl.wind(4300).expectedStatus(from: before)
        let matching = try B8XStatus.decode(sampleFrame(windHundreds: 43))
        let mismatching = try B8XStatus.decode(sampleFrame(windHundreds: 43, coldLevel: 111))
        XCTAssertTrue(expectation.matches(matching))
        XCTAssertFalse(expectation.matches(mismatching))
    }

    func testCoolingModeOnlyAdjustsCoolingOutput() throws {
        let status = try B8XStatus.decode(sampleFrame(coldInteger: 24, coldFraction: 5, hot: 42, windHundreds: 42, coldLevel: 110))
        let targets = B8XDualTemperatureTargets(coldCelsius: 15, hotCelsius: 40)
        let next = try XCTUnwrap(B8XDualTemperatureController.nextSettings(from: status, targets: targets, targetMode: .cooling))
        XCTAssertEqual(next.coolingLevel, 122)
        XCTAssertEqual(next.fanRPM, 4800)
    }

    func testHeatingModeOnlyAdjustsFanOutput() throws {
        let status = try B8XStatus.decode(sampleFrame(coldInteger: 24, coldFraction: 5, hot: 42, windHundreds: 42, coldLevel: 110))
        let targets = B8XDualTemperatureTargets(coldCelsius: 15, hotCelsius: 40)
        let next = try XCTUnwrap(B8XDualTemperatureController.nextSettings(from: status, targets: targets, targetMode: .heating))
        XCTAssertEqual(next.coolingLevel, 110)
        XCTAssertEqual(next.fanRPM, 4400)
    }

    func testDualTemperatureControllerHoldsInsideDeadband() throws {
        let status = try B8XStatus.decode(
            sampleFrame(coldInteger: 15, coldFraction: 0, hot: 40, windHundreds: 42, coldLevel: 110)
        )
        let targets = B8XDualTemperatureTargets(coldCelsius: 15, hotCelsius: 40)
        XCTAssertNil(B8XDualTemperatureController.nextSettings(from: status, targets: targets))
    }

    func testDualTemperatureControllerAppliesBothTemperatureSafetyLimits() throws {
        let status = try B8XStatus.decode(
            sampleFrame(coldInteger: 4, coldFraction: 9, hot: 45, windHundreds: 42, coldLevel: 130)
        )
        let targets = B8XDualTemperatureTargets(coldCelsius: 15, hotCelsius: 40)
        let next = try XCTUnwrap(B8XDualTemperatureController.nextSettings(from: status, targets: targets))
        XCTAssertEqual(next.coolingLevel, 1)
        XCTAssertEqual(next.fanRPM, 6000)
        XCTAssertTrue(next.reason.contains("冷端低温保护"))
        XCTAssertTrue(next.reason.contains("热端高温保护"))
    }

    func testDualTemperatureControllerNormalizesAnomalousCoolingTelemetry() throws {
        let status = try B8XStatus.decode(
            sampleFrame(coldInteger: 24, coldFraction: 5, hot: 38, windHundreds: 42, coldLevel: 255)
        )
        let targets = B8XDualTemperatureTargets(coldCelsius: 24.5, hotCelsius: 38)
        XCTAssertNil(B8XDualTemperatureController.nextSettings(from: status, targets: targets))
    }

    func testDualTemperatureControllerUsesSmallerStepsNearTarget() throws {
        let status = try B8XStatus.decode(
            sampleFrame(coldInteger: 17, coldFraction: 0, hot: 42, windHundreds: 42, coldLevel: 110)
        )
        let targets = B8XDualTemperatureTargets(coldCelsius: 15, hotCelsius: 40)
        let next = try XCTUnwrap(B8XDualTemperatureController.nextSettings(from: status, targets: targets))
        XCTAssertEqual(next.coolingLevel, 112)
        XCTAssertEqual(next.fanRPM, 4400)
    }

    func testDualTemperatureControllerRejectsImplausibleTemperatureTelemetry() throws {
        let coldInvalid = try B8XStatus.decode(sampleFrame(coldInteger: 80, coldFraction: 0))
        let hotInvalid = try B8XStatus.decode(sampleFrame(hot: 110))
        let targets = B8XDualTemperatureTargets(coldCelsius: 15, hotCelsius: 40)
        XCTAssertNil(B8XDualTemperatureController.nextSettings(from: coldInvalid, targets: targets))
        XCTAssertNil(B8XDualTemperatureController.nextSettings(from: hotInvalid, targets: targets))
    }

    func testDualTemperatureControllerDoesNotOvershootOutputLimits() throws {
        let status = try B8XStatus.decode(
            sampleFrame(coldInteger: 24, coldFraction: 0, hot: 42, windHundreds: 60, coldLevel: 174)
        )
        let targets = B8XDualTemperatureTargets(coldCelsius: 15, hotCelsius: 40)
        let next = try XCTUnwrap(B8XDualTemperatureController.nextSettings(from: status, targets: targets))
        XCTAssertEqual(next.coolingLevel, 186)
        XCTAssertEqual(next.fanRPM, 6000)
    }

    func testDualTemperatureControllerRejectsOutOfRangeTargets() throws {
        let status = try B8XStatus.decode(sampleFrame())
        XCTAssertNil(B8XDualTemperatureController.nextSettings(
            from: status,
            targets: B8XDualTemperatureTargets(coldCelsius: 5, hotCelsius: 50)
        ))
    }


}
