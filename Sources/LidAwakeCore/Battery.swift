import Foundation
import IOKit.ps

public struct BatteryStatus: Codable, Equatable, Sendable {
    /// 0–100, nil on Macs without a battery.
    public var percent: Int?
    public var onAC: Bool

    public init(percent: Int?, onAC: Bool) {
        self.percent = percent
        self.onAC = onAC
    }

    public static let desktop = BatteryStatus(percent: nil, onAC: true)
}

public enum Battery {
    public static func current() -> BatteryStatus {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return .desktop }
        let onAC = (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) == kIOPMACPowerKey
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return BatteryStatus(percent: Int((Double(current) / Double(max) * 100).rounded()), onAC: onAC)
        }
        return BatteryStatus(percent: nil, onAC: onAC)
    }
}
