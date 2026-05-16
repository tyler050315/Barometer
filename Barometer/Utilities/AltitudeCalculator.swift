import Foundation

enum AltitudeCalculator {
    static func altitudeMeters(stationPressureHPa: Double, seaLevelPressureHPa: Double) -> Double {
        guard stationPressureHPa > 0, seaLevelPressureHPa > 0 else {
            return 0
        }

        return 44330.0 * (1.0 - pow(stationPressureHPa / seaLevelPressureHPa, 0.1903))
    }
}
