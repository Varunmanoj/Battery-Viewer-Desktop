import Foundation
import IOKit.ps

struct Reading: Equatable {
    var percent: Int?
    var status: String
    var onBattery: Bool?

    static let unavailable = Reading(status: "Battery information unavailable")
    static let absent = Reading(status: "No battery detected")

    var summary: String {
        guard let percent else { return status }
        return "Battery level \(percent) percent. \(status)."
    }

    static func current() -> Reading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return .unavailable
        }
        for item in list {
            guard let source = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  source[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  source[kIOPSIsPresentKey] as? Bool != false else { continue }
            return decode(source)
        }
        return .absent
    }

    static func decode(_ source: [String: Any]) -> Reading {
        var level: Int?
        if let current = (source[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue,
           let maximum = (source[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue,
           current >= 0, maximum > 0, current <= maximum {
            level = Int((current / maximum * 100).rounded())
        }
        let state = source[kIOPSPowerSourceStateKey] as? String
        let battery = state == kIOPSBatteryPowerValue
        let external = state == kIOPSACPowerValue
        let status: String
        if battery { status = "On battery power" }
        else if !external { status = "Power source unknown" }
        else if source[kIOPSIsChargingKey] as? Bool == true { status = "Charging" }
        else if level == 100 { status = "Fully charged" }
        else { status = "Connected to power" }
        return Reading(percent: level, status: level == nil ? "Battery level unavailable. " + status : status,
                       onBattery: battery || external ? battery : nil)
    }

    func shouldAnnounce(after old: Reading, power: Bool, lowThreshold: Int?) -> Bool {
        guard let onBattery, let wasOnBattery = old.onBattery else { return false }
        if power && wasOnBattery != onBattery { return true }
        guard onBattery, let lowThreshold, let percent, percent <= lowThreshold else { return false }
        return !wasOnBattery || old.percent.map { $0 > lowThreshold } == true
    }
}
