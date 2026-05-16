import CoreLocation
import Foundation

struct AirportResolver {
    func nearestAirport(from reports: [MetarReport], to location: CLLocation) -> AirportStation? {
        reports.compactMap { report -> AirportStation? in
            guard let latitude = report.lat,
                  let longitude = report.lon,
                  let pressureHPa = report.seaLevelPressureHPa else {
                return nil
            }

            let stationLocation = CLLocation(latitude: latitude, longitude: longitude)
            let distanceKilometers = location.distance(from: stationLocation) / 1000.0

            return AirportStation(
                id: report.icaoId,
                icaoId: report.icaoId,
                name: report.name ?? "Unknown Station",
                latitude: latitude,
                longitude: longitude,
                distanceKilometers: distanceKilometers,
                seaLevelPressureHPa: pressureHPa,
                observationTime: report.obsTime,
                rawText: report.rawText
            )
        }
        .sorted { $0.distanceKilometers < $1.distanceKilometers }
        .first
    }
}
