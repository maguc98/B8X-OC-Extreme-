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

    /// The B8X reports mode 0 as automatic and mode 1 as manual.
    var isAutomaticMode: Bool { modeRaw == 0 }


    static func decode(_ data: Data) throws -> B8XStatus {
        let bytes = [UInt8](data)
        guard bytes.count == 20, bytes[0] == 0x13 else {
            throw B8XProtocolError.invalidFrame
        }
        guard bytes[5] <= 99, bytes[8] <= 9, bytes[13] <= 99,
              bytes[14] == 0 || bytes[14] == 255 else {
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

enum B8XThermalTargetMode: String, CaseIterable { case cooling, heating }

struct B8XDualTemperatureTargets: Equatable {
    let coldCelsius: Double
    let hotCelsius: Double
}

struct B8XAutomaticSettings: Equatable {
    let fanRPM: Int
    let coolingLevel: Int
    let reason: String
}

/// Conservative app-side closed-loop controller. It uses only the verified
/// combined 0x20 settings packet; it does not rely on undocumented LED fields.
enum B8XDualTemperatureController {
    static let coldTargetRange: ClosedRange<Double> = 10.0...25.0
    static let hotTargetRange: ClosedRange<Double> = 30.0...42.0
    static let minimumAutomaticFanRPM = 4000
    static let maximumAutomaticFanRPM = 6000
    static let minimumAutomaticCoolingLevel = 92
    static let maximumAutomaticCoolingLevel = 175

    // Ignore implausible telemetry rather than driving hardware from a bad sensor frame.
    static let plausibleColdTemperatureRange: ClosedRange<Double> = -20.0...60.0
    static let plausibleHotTemperatureRange: ClosedRange<Double> = -20.0...100.0

    static func nextSettings(
        from status: B8XStatus,
        targets: B8XDualTemperatureTargets,
        targetMode: B8XThermalTargetMode = .cooling,
        lowTemperatureProtectionEnabled: Bool = true,
        highTemperatureProtectionEnabled: Bool = true
    ) -> B8XAutomaticSettings? {
        guard coldTargetRange.contains(targets.coldCelsius),
              hotTargetRange.contains(targets.hotCelsius),
              plausibleColdTemperatureRange.contains(status.coldTemperature),
              plausibleHotTemperatureRange.contains(Double(status.hotTemperature)) else {
            return nil
        }

        // Keep the controller proportional in small, bounded steps. The B8X
        // cooling byte is not a calibrated temperature scale, so never infer
        // a linear °C-to-level conversion.
        let reportedCoolingIsPlausible =
            (minimumAutomaticCoolingLevel...maximumAutomaticCoolingLevel).contains(status.coldLevel)
        let currentCooling = reportedCoolingIsPlausible ? status.coldLevel : 110
        let currentFan = min(max(status.windLevel, minimumAutomaticFanRPM),
                             maximumAutomaticFanRPM)

        let coldError = status.coldTemperature - targets.coldCelsius
        var coolingDelta = 0
        var reasons: [String] = []

        if lowTemperatureProtectionEnabled && status.coldTemperature <= 5.0 {
            coolingDelta = minimumAutomaticCoolingLevel - currentCooling
            reasons.append("冷端低温保护")
        } else if targetMode == .cooling && coldError >= 6.0 {
            coolingDelta = 6
            reasons.append("冷端明显偏热，增加制冷")
        } else if targetMode == .cooling && coldError >= 3.0 {
            coolingDelta = 4
            reasons.append("冷端偏热，增加制冷")
        } else if targetMode == .cooling && coldError >= 1.5 {
            coolingDelta = 2
            reasons.append("冷端轻微偏热，微增制冷")
        } else if targetMode == .cooling && coldError <= -6.0 {
            coolingDelta = -6
            reasons.append("冷端明显偏冷，降低制冷")
        } else if targetMode == .cooling && coldError <= -3.0 {
            coolingDelta = -4
            reasons.append("冷端偏冷，降低制冷")
        } else if targetMode == .cooling && coldError <= -1.5 {
            coolingDelta = -2
            reasons.append("冷端轻微偏冷，微降制冷")
        }

        let hotError = Double(status.hotTemperature) - targets.hotCelsius
        var fanDelta = 0
        if highTemperatureProtectionEnabled && status.hotTemperature >= 45 {
            fanDelta = maximumAutomaticFanRPM - currentFan
            reasons.append("热端高温保护")
        } else if targetMode == .heating && hotError >= 6.0 {
            fanDelta = 600
            reasons.append("热端明显偏热，提高风扇")
        } else if targetMode == .heating && hotError >= 3.0 {
            fanDelta = 400
            reasons.append("热端偏热，提高风扇")
        } else if targetMode == .heating && hotError >= 1.5 {
            fanDelta = 200
            reasons.append("热端轻微偏热，微增风扇")
        } else if targetMode == .heating && hotError <= -6.0 {
            fanDelta = -600
            reasons.append("热端明显低于目标，降低风扇")
        } else if targetMode == .heating && hotError <= -3.0 {
            fanDelta = -400
            reasons.append("热端低于目标，降低风扇")
        } else if targetMode == .heating && hotError <= -1.5 {
            fanDelta = -200
            reasons.append("热端轻微低于目标，微降风扇")
        }

        let nextCooling = min(max(currentCooling + coolingDelta,
                                  minimumAutomaticCoolingLevel),
                              maximumAutomaticCoolingLevel)
        let nextFan = min(max(currentFan + fanDelta,
                              minimumAutomaticFanRPM),
                          maximumAutomaticFanRPM)

        // Do not issue a corrective write merely because a single telemetry
        // byte is anomalous. Wait until a real temperature error calls for it.
        guard nextCooling != currentCooling || nextFan != currentFan else { return nil }
        return B8XAutomaticSettings(
            fanRPM: nextFan,
            coolingLevel: nextCooling,
            reason: reasons.isEmpty ? "温度维持区间" : reasons.joined(separator: "；")
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
        case .invalidWindLevel: return "风扇设定必须在 1–6000 RPM 范围内"
        case .invalidColdLevel: return "制冷设定必须在 1–255 范围内"
        case .missingStatus: return "尚未读取设备状态"
        }
    }
}

enum B8XControl {
    case light(Bool)
    case mode(Int)
    case wind(Int)
    case cold(Int)
    case settings(wind: Int, cold: Int)

    private func validateCurrentSettings(_ status: B8XStatus, allowFanReductionFromAboveLimit: Bool = false) throws {
        guard status.modeRaw == 0 || status.modeRaw == 1 else {
            throw B8XProtocolError.unsupportedMode
        }
        let fanRange = allowFanReductionFromAboveLimit ? (1...8000) : (1...6000)
        guard fanRange.contains(status.windLevel) else {
            throw B8XProtocolError.invalidWindLevel
        }
        guard (1...255).contains(status.coldLevel) else {
            throw B8XProtocolError.invalidColdLevel
        }
    }

    func expectedStatus(from status: B8XStatus) throws -> B8XStatusExpectation {
        if case .light(let enabled) = self {
            return .light(enabled)
        }
        switch self {
        case .light(let enabled):
            return .light(enabled)
        case .mode(let mode):
            try validateCurrentSettings(status)
            guard mode == 0 || mode == 1 else { throw B8XProtocolError.unsupportedMode }
            return .mode(mode, wind: status.windLevel, cold: status.coldLevel)
        case .wind(let value):
            try validateCurrentSettings(status, allowFanReductionFromAboveLimit: true)
            guard (1...6000).contains(value) else {
                throw B8XProtocolError.invalidWindLevel
            }
            return .wind(value, mode: 1, cold: status.coldLevel)
        case .cold(let value):
            try validateCurrentSettings(status)
            guard (1...255).contains(value) else { throw B8XProtocolError.invalidColdLevel }
            return .cold(value, mode: status.modeRaw, wind: status.windLevel)
        case .settings(let wind, let cold):
            guard (1...6000).contains(wind) else {
                throw B8XProtocolError.invalidWindLevel
            }
            guard (1...255).contains(cold) else { throw B8XProtocolError.invalidColdLevel }
            return .settings(wind: wind, cold: cold)
        }
    }

    func packet(using status: B8XStatus) throws -> Data {
        _ = try expectedStatus(from: status)
        switch self {
        case .light(let enabled):
            return Data([0x10, enabled ? 0xff : 0x00])
        case .mode(let mode):
            return Data([0x20, UInt8(mode), UInt8(status.coldLevel),
                         UInt8(status.windLevel / 100), UInt8(status.windLevel % 100),
                         status.raw[6], 92, 40, 0])
        case .wind(let value):
            // A fixed RPM target is a manual-control operation; set mode=1 in the same packet.
            return Data([0x20, 1, UInt8(status.coldLevel),
                         UInt8(value / 100), UInt8(value % 100),
                         status.raw[6], 92, 40, 0])
        case .cold(let value):
            return Data([0x20, UInt8(status.modeRaw), UInt8(value),
                         UInt8(status.windLevel / 100), UInt8(status.windLevel % 100),
                         status.raw[6], 92, 40, 0])
        case .settings(let wind, let cold):
            return Data([0x20, 1, UInt8(cold),
                         UInt8(wind / 100), UInt8(wind % 100),
                         status.raw[6], 92, 40, 0])
        }
    }
}

enum B8XStatusExpectation {
    case light(Bool)
    case mode(Int, wind: Int, cold: Int)
    case wind(Int, mode: Int, cold: Int)
    case cold(Int, mode: Int, wind: Int)
    case settings(wind: Int, cold: Int)

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
        case .settings(let wind, let cold):
            return status.windLevel == wind && status.coldLevel == cold && status.modeRaw == 1
        }
    }
}
