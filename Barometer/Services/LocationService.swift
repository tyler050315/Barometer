import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum LocationError: LocalizedError {
        case denied
        case restricted
        case unavailable
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied:
                return "定位权限已拒绝，请在系统设置中允许 App 使用定位"
            case .restricted:
                return "当前设备限制了定位服务"
            case .unavailable:
                return "无法获取当前位置"
            case .failed(let message):
                return "定位失败：\(message)"
            }
        }
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            requestAuthorizationOrLocation()
        }
    }

    private func requestAuthorizationOrLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied:
            finish(.failure(LocationError.denied))
        case .restricted:
            finish(.failure(LocationError.restricted))
        @unknown default:
            finish(.failure(LocationError.unavailable))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            requestAuthorizationOrLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else {
                finish(.failure(LocationError.unavailable))
                return
            }

            finish(.success(location))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            finish(.failure(LocationError.failed(error.localizedDescription)))
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil

        switch result {
        case .success(let location):
            continuation.resume(returning: location)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
