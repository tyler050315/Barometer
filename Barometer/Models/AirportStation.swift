import Foundation

struct AirportStation: Identifiable {
    let id: String
    let icaoId: String
    let name: String
    let latitude: Double
    let longitude: Double
    let distanceKilometers: Double
    let seaLevelPressureHPa: Double
    let observationTime: Date?
    let rawText: String?

    var observationText: String {
        guard let observationTime else {
            return "时间未知"
        }

        return UnitFormatter.dateTime(observationTime)
    }
}
