import CoreLocation
import Foundation

final class AviationWeatherService {
    enum WeatherError: LocalizedError {
        case invalidURL
        case badResponse(Int)
        case noNearbyMetar

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "气象数据请求地址无效"
            case .badResponse(let statusCode):
                return "机场气象服务返回错误：\(statusCode)"
            case .noNearbyMetar:
                return "附近没有可用的机场海平面气压"
            }
        }
    }

    private let session: URLSession
    private let resolver = AirportResolver()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func nearestAirport(from location: CLLocation) async throws -> AirportStation {
        let searchRadiiDegrees = [0.5, 1.0, 2.0, 4.0]

        for radius in searchRadiiDegrees {
            let reports = try await fetchMetars(near: location.coordinate, radiusDegrees: radius)
            if let airport = resolver.nearestAirport(from: reports, to: location) {
                return airport
            }
        }

        if let airport = try await fetchKnownNearbyAirport(from: location) {
            return airport
        }

        throw WeatherError.noNearbyMetar
    }

    private func fetchMetars(near coordinate: CLLocationCoordinate2D, radiusDegrees: Double) async throws -> [MetarReport] {
        var components = URLComponents(string: "https://aviationweather.gov/api/data/metar")
        let minLat = max(coordinate.latitude - radiusDegrees, -90)
        let maxLat = min(coordinate.latitude + radiusDegrees, 90)
        let minLon = max(coordinate.longitude - radiusDegrees, -180)
        let maxLon = min(coordinate.longitude + radiusDegrees, 180)
        let bbox = "\(minLat),\(minLon),\(maxLat),\(maxLon)"

        components?.queryItems = [
            URLQueryItem(name: "bbox", value: bbox),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "hours", value: "6")
        ]

        guard let url = components?.url else {
            throw WeatherError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Barometer/1.0 personal iOS app", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeatherError.badResponse(-1)
        }

        if httpResponse.statusCode == 204 {
            return []
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw WeatherError.badResponse(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode([MetarReport].self, from: data)
    }

    private func fetchKnownNearbyAirport(from location: CLLocation) async throws -> AirportStation? {
        let candidates = KnownMetarStation.southChina
            .map { station -> (station: KnownMetarStation, distance: CLLocationDistance) in
                let stationLocation = CLLocation(latitude: station.latitude, longitude: station.longitude)
                return (station, location.distance(from: stationLocation))
            }
            .filter { $0.distance <= 300_000 }
            .sorted { $0.distance < $1.distance }

        for candidate in candidates {
            let reports = try await fetchMetars(ids: [candidate.station.icaoId], hours: 24)
            if let report = reports.first,
               let pressureHPa = report.seaLevelPressureHPa {
                return AirportStation(
                    id: candidate.station.icaoId,
                    icaoId: candidate.station.icaoId,
                    name: report.name ?? candidate.station.name,
                    latitude: report.lat ?? candidate.station.latitude,
                    longitude: report.lon ?? candidate.station.longitude,
                    distanceKilometers: candidate.distance / 1000.0,
                    seaLevelPressureHPa: pressureHPa,
                    observationTime: report.obsTime,
                    rawText: report.rawText
                )
            }
        }

        return nil
    }

    private func fetchMetars(ids: [String], hours: Int) async throws -> [MetarReport] {
        var components = URLComponents(string: "https://aviationweather.gov/api/data/metar")
        components?.queryItems = [
            URLQueryItem(name: "ids", value: ids.joined(separator: ",")),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "hours", value: String(hours))
        ]

        guard let url = components?.url else {
            throw WeatherError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Barometer/1.0 personal iOS app", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeatherError.badResponse(-1)
        }

        if httpResponse.statusCode == 204 {
            return []
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw WeatherError.badResponse(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode([MetarReport].self, from: data)
    }
}

private struct KnownMetarStation {
    let icaoId: String
    let name: String
    let latitude: Double
    let longitude: Double

    static let southChina = [
        KnownMetarStation(icaoId: "ZGSZ", name: "Shenzhen Bao'an", latitude: 22.6393, longitude: 113.8107),
        KnownMetarStation(icaoId: "VHHH", name: "Hong Kong International", latitude: 22.3080, longitude: 113.9185),
        KnownMetarStation(icaoId: "VMMC", name: "Macau International", latitude: 22.1496, longitude: 113.5916),
        KnownMetarStation(icaoId: "ZGGG", name: "Guangzhou Baiyun", latitude: 23.3924, longitude: 113.2990),
        KnownMetarStation(icaoId: "ZGOW", name: "Jieyang Chaoshan", latitude: 23.5520, longitude: 116.5033)
    ]
}
