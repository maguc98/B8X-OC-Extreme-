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
        coldLevel: UInt8 = 110
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

    func testControlPacketsRespectSixThousandRPMCeiling() throws {
        let status = try B8XStatus.decode(sampleFrame())
        XCTAssertEqual(try B8XControl.wind(6000).packet(using: status),
                       Data([0x20, 1, 110, 60, 0, 0, 92, 40, 0]))
        XCTAssertEqual(try B8XControl.cold(255).packet(using: status),
                       Data([0x20, 1, 255, 42, 0, 0, 92, 40, 0]))
        XCTAssertEqual(try B8XControl.light(false).packet(using: status),
                       Data([0x10, 0x00]))
    }

    func testRejectsFanSettingsAboveSixThousandRPM() throws {
        let status = try B8XStatus.decode(sampleFrame())
        XCTAssertNoThrow(try B8XControl.wind(4150).packet(using: status))
        XCTAssertNoThrow(try B8XControl.wind(6000).packet(using: status))
        XCTAssertThrowsError(try B8XControl.wind(6001).packet(using: status))
        XCTAssertNoThrow(try B8XControl.cold(255).packet(using: status))
        XCTAssertThrowsError(try B8XControl.cold(256).packet(using: status))
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
        let invalidCooling = try B8XStatus.decode(sampleFrame(coldLevel: 0))
        XCTAssertThrowsError(try B8XControl.mode(1).packet(using: invalidCooling))
    }

    func testStatusExpectationMatchesOnlyRequestedAndPreservedFields() throws {
        let before = try B8XStatus.decode(sampleFrame())
        let expectation = try B8XControl.wind(4300).expectedStatus(from: before)
        let matching = try B8XStatus.decode(sampleFrame(windHundreds: 43))
        let mismatching = try B8XStatus.decode(sampleFrame(windHundreds: 43, coldLevel: 111))
        XCTAssertTrue(expectation.matches(matching))
        XCTAssertFalse(expectation.matches(mismatching))
    }
}
