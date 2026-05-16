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
            URLQueryItem(name: "hours", value: "2")
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
