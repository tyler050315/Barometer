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

    func airport(icaoId: String, near location: CLLocation?) async throws -> AirportStation {
        let normalizedId = icaoId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let reports = try await fetchMetars(ids: [normalizedId], hours: 24)

        guard let report = reports.first,
              let pressureHPa = report.seaLevelPressureHPa else {
            throw WeatherError.noNearbyMetar
        }

        let knownStation = KnownMetarStation.station(icaoId: normalizedId)
        let latitude = report.lat ?? knownStation?.latitude ?? 0
        let longitude = report.lon ?? knownStation?.longitude ?? 0
        let distanceKilometers: Double

        if let location {
            let stationLocation = CLLocation(latitude: latitude, longitude: longitude)
            distanceKilometers = location.distance(from: stationLocation) / 1000.0
        } else {
            distanceKilometers = 0
        }

        return AirportStation(
            id: normalizedId,
            icaoId: normalizedId,
            name: report.name ?? knownStation?.name ?? "Manual Station",
            latitude: latitude,
            longitude: longitude,
            distanceKilometers: distanceKilometers,
            seaLevelPressureHPa: pressureHPa,
            observationTime: report.obsTime,
            rawText: report.rawText
        )
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
        let candidates = KnownMetarStation.all
            .map { station -> (station: KnownMetarStation, distance: CLLocationDistance) in
                let stationLocation = CLLocation(latitude: station.latitude, longitude: station.longitude)
                return (station, location.distance(from: stationLocation))
            }
            .filter { $0.distance <= 800_000 }
            .sorted { $0.distance < $1.distance }
            .prefix(12)

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

    static func station(icaoId: String) -> KnownMetarStation? {
        all.first { $0.icaoId == icaoId.uppercased() }
    }

    static let all = [
        KnownMetarStation(icaoId: "ZBAA", name: "Beijing Capital", latitude: 40.0801, longitude: 116.5846),
        KnownMetarStation(icaoId: "ZBAD", name: "Beijing Daxing", latitude: 39.5098, longitude: 116.4105),
        KnownMetarStation(icaoId: "ZBTJ", name: "Tianjin Binhai", latitude: 39.1244, longitude: 117.3462),
        KnownMetarStation(icaoId: "ZBSJ", name: "Shijiazhuang Zhengding", latitude: 38.2807, longitude: 114.6973),
        KnownMetarStation(icaoId: "ZYHB", name: "Harbin Taiping", latitude: 45.6234, longitude: 126.2503),
        KnownMetarStation(icaoId: "ZYCC", name: "Changchun Longjia", latitude: 43.9962, longitude: 125.6853),
        KnownMetarStation(icaoId: "ZYTX", name: "Shenyang Taoxian", latitude: 41.6398, longitude: 123.4834),
        KnownMetarStation(icaoId: "ZYTL", name: "Dalian Zhoushuizi", latitude: 38.9657, longitude: 121.5386),
        KnownMetarStation(icaoId: "ZSPD", name: "Shanghai Pudong", latitude: 31.1443, longitude: 121.8083),
        KnownMetarStation(icaoId: "ZSSS", name: "Shanghai Hongqiao", latitude: 31.1979, longitude: 121.3363),
        KnownMetarStation(icaoId: "ZSHC", name: "Hangzhou Xiaoshan", latitude: 30.2295, longitude: 120.4345),
        KnownMetarStation(icaoId: "ZSNJ", name: "Nanjing Lukou", latitude: 31.7420, longitude: 118.8620),
        KnownMetarStation(icaoId: "ZSQD", name: "Qingdao Jiaodong", latitude: 36.3619, longitude: 120.0885),
        KnownMetarStation(icaoId: "ZUCK", name: "Chongqing Jiangbei", latitude: 29.7192, longitude: 106.6417),
        KnownMetarStation(icaoId: "ZUUU", name: "Chengdu Shuangliu", latitude: 30.5785, longitude: 103.9471),
        KnownMetarStation(icaoId: "ZLXY", name: "Xi'an Xianyang", latitude: 34.4471, longitude: 108.7516),
        KnownMetarStation(icaoId: "ZHHH", name: "Wuhan Tianhe", latitude: 30.7838, longitude: 114.2081),
        KnownMetarStation(icaoId: "ZGHA", name: "Changsha Huanghua", latitude: 28.1892, longitude: 113.2196),
        KnownMetarStation(icaoId: "ZJHK", name: "Haikou Meilan", latitude: 19.9349, longitude: 110.4589),
        KnownMetarStation(icaoId: "ZPPP", name: "Kunming Changshui", latitude: 25.1019, longitude: 102.9292),
        KnownMetarStation(icaoId: "ZLXN", name: "Xining Caojiabao", latitude: 36.5275, longitude: 102.0430),
        KnownMetarStation(icaoId: "ZLIC", name: "Yinchuan Hedong", latitude: 38.4819, longitude: 106.0092),
        KnownMetarStation(icaoId: "ZBHH", name: "Hohhot Baita", latitude: 40.8514, longitude: 111.8241),
        KnownMetarStation(icaoId: "ZWWW", name: "Urumqi Diwopu", latitude: 43.9071, longitude: 87.4742),
        KnownMetarStation(icaoId: "ZLLL", name: "Lanzhou Zhongchuan", latitude: 36.5152, longitude: 103.6208),
        KnownMetarStation(icaoId: "ZGSZ", name: "Shenzhen Bao'an", latitude: 22.6393, longitude: 113.8107),
        KnownMetarStation(icaoId: "VHHH", name: "Hong Kong International", latitude: 22.3080, longitude: 113.9185),
        KnownMetarStation(icaoId: "VMMC", name: "Macau International", latitude: 22.1496, longitude: 113.5916),
        KnownMetarStation(icaoId: "ZGGG", name: "Guangzhou Baiyun", latitude: 23.3924, longitude: 113.2990),
        KnownMetarStation(icaoId: "ZGKL", name: "Guilin Liangjiang", latitude: 25.2181, longitude: 110.0392),
        KnownMetarStation(icaoId: "ZGNN", name: "Nanning Wuxu", latitude: 22.6083, longitude: 108.1725),
        KnownMetarStation(icaoId: "ZGOW", name: "Jieyang Chaoshan", latitude: 23.5520, longitude: 116.5033)
    ]
}
