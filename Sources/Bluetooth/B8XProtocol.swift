import Foundation

struct B8XStatus: Equatable {
    let coldTemperature: Double
    let hotTemperature: Int
    let fanRPM: Int
    let lightEnabled: Bool
    let windLevel: Int
    let coldLevel: Int
    let modeRaw: Int
    let raw: [UInt8]

    static func decode(_ data: Data) throws -> B8XStatus {
        let bytes = [UInt8](data)
        guard bytes.count == 20, bytes[0] == 0x13 else {
            throw B8XProtocolError.invalidFrame
        }
        guard bytes[8] <= 9, bytes[14] == 0 || bytes[14] == 255 else {
            throw B8XProtocolError.invalidFields
        }
        let signedCold = Int(Int8(bitPattern: bytes[7]))
        let signedHot = Int(Int8(bitPattern: bytes[9]))
        return B8XStatus(
            coldTemperature: Double(signedCold) + Double(bytes[8]) / 10.0,
            hotTemperature: signedHot,
            fanRPM: Int(bytes[12]) * 100 + Int(bytes[13]),
            lightEnabled: bytes[14] == 255,
            windLevel: Int(bytes[4]) * 100 + Int(bytes[5]),
            coldLevel: Int(bytes[3]),
            modeRaw: Int(bytes[2] >> 4),
            raw: bytes
        )
    }
}

enum B8XProtocolError: LocalizedError {
    case invalidFrame
    case invalidFields
    case unsupportedMode
    case invalidWindLevel
    case invalidColdLevel
    case missingStatus

    var errorDescription: String? {
        switch self {
        case .invalidFrame: return "收到的状态帧格式不正确"
        case .invalidFields: return "状态帧包含无效字段"
        case .unsupportedMode: return "设备返回了未验证的运行模式"
        case .invalidWindLevel: return "风扇设定超出已验证范围（4000–4500 RPM）"
        case .invalidColdLevel: return "制冷设定超出已验证范围（92–175）"
        case .missingStatus: return "尚未读取设备状态"
        }
    }
}

enum B8XControl {
    case light(Bool)
    case mode(Int)
    case wind(Int)
    case cold(Int)

    func expectedStatus(from status: B8XStatus) throws -> B8XStatusExpectation {
        if case .light = self {
            // The light command is independent of the mode fields.
        } else if status.modeRaw != 0 && status.modeRaw != 1 {
            throw B8XProtocolError.unsupportedMode
        }
        switch self {
        case .light(let enabled):
            return .light(enabled)
        case .mode(let mode):
            guard mode == 0 || mode == 1 else { throw B8XProtocolError.unsupportedMode }
            return .mode(mode, wind: status.windLevel, cold: status.coldLevel)
        case .wind(let value):
            guard (4000...4500).contains(value), value % 100 == 0 else {
                throw B8XProtocolError.invalidWindLevel
            }
            return .wind(value, mode: status.modeRaw, cold: status.coldLevel)
        case .cold(let value):
            guard (92...175).contains(value) else { throw B8XProtocolError.invalidColdLevel }
            return .cold(value, mode: status.modeRaw, wind: status.windLevel)
        }
    }

    func packet(using status: B8XStatus) throws -> Data {
        switch self {
        case .light(let enabled):
            return Data([0x10, enabled ? 0xff : 0x00])
        case .mode(let mode):
            guard mode == 0 || mode == 1 else { throw B8XProtocolError.unsupportedMode }
            return Data([0x20, UInt8(mode), UInt8(status.coldLevel),
                         UInt8(status.windLevel / 100), UInt8(status.windLevel % 100),
                         status.raw[6], 92, 40, 0])
        case .wind(let value):
            guard (4000...4500).contains(value), value % 100 == 0 else {
                throw B8XProtocolError.invalidWindLevel
            }
            return Data([0x20, UInt8(status.modeRaw), UInt8(status.coldLevel),
                         UInt8(value / 100), UInt8(value % 100),
                         status.raw[6], 92, 40, 0])
        case .cold(let value):
            guard (92...175).contains(value) else { throw B8XProtocolError.invalidColdLevel }
            return Data([0x20, UInt8(status.modeRaw), UInt8(value),
                         UInt8(status.windLevel / 100), UInt8(status.windLevel % 100),
                         status.raw[6], 92, 40, 0])
        }
    }
}

enum B8XStatusExpectation {
    case light(Bool)
    case mode(Int, wind: Int, cold: Int)
    case wind(Int, mode: Int, cold: Int)
    case cold(Int, mode: Int, wind: Int)

    func matches(_ status: B8XStatus) -> Bool {
        switch self {
        case .light(let enabled):
            return status.lightEnabled == enabled
        case .mode(let mode, let wind, let cold):
            return status.modeRaw == mode && status.windLevel == wind && status.coldLevel == cold
        case .wind(let wind, let mode, let cold):
            return status.windLevel == wind && status.modeRaw == mode && status.coldLevel == cold
        case .cold(let cold, let mode, let wind):
            return status.coldLevel == cold && status.modeRaw == mode && status.windLevel == wind
        }
    }
}
