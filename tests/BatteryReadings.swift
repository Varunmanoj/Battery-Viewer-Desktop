import IOKit.ps

@main
struct BatteryTests {
    static func main() {
        let plugged = Reading.decode([kIOPSCurrentCapacityKey: 40, kIOPSMaxCapacityKey: 50,
                                      kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargingKey: false])
        precondition(plugged.percent == 80 && plugged.status == "Connected to power")
        let charging = Reading.decode([kIOPSCurrentCapacityKey: 12, kIOPSMaxCapacityKey: 100,
                                       kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargingKey: true])
        precondition(charging.status == "Charging")
        let missing = Reading.decode([kIOPSCurrentCapacityKey: 5, kIOPSMaxCapacityKey: 0])
        precondition(missing.percent == nil && missing.onBattery == nil)
        precondition(Reading.absent.summary == "No battery detected")
        let high = Reading(percent: 21, status: "On battery power", onBattery: true)
        let low = Reading(percent: 20, status: "On battery power", onBattery: true)
        precondition(low.shouldAnnounce(after: high, power: false, lowThreshold: 20))
        precondition(!low.shouldAnnounce(after: low, power: true, lowThreshold: 20))
        precondition(!low.shouldAnnounce(after: high, power: false, lowThreshold: nil))
        precondition(low.shouldAnnounce(after: plugged, power: true, lowThreshold: nil))
        precondition(!plugged.shouldAnnounce(after: .unavailable, power: true, lowThreshold: 20))
        let aboveCustom = Reading(percent: 36, status: "On battery power", onBattery: true)
        let belowCustom = Reading(percent: 33, status: "On battery power", onBattery: true)
        precondition(belowCustom.shouldAnnounce(after: aboveCustom, power: false, lowThreshold: 35))
        precondition(!belowCustom.shouldAnnounce(after: aboveCustom, power: false, lowThreshold: 20))
        precondition(!low.shouldAnnounce(after: belowCustom, power: false, lowThreshold: 35))
        precondition(belowCustom.shouldAnnounce(after: plugged, power: false, lowThreshold: 35))
        precondition(!charging.shouldAnnounce(after: plugged, power: false, lowThreshold: 35))
        print("Battery state checks passed. Current reading: " + Reading.current().summary)
    }
}
