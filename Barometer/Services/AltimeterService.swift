import CoreMotion
import Foundation

final class AltimeterService {
    enum AltimeterError: LocalizedError {
        case unavailable
        case updateFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "此设备没有可用气压计"
            case .updateFailed(let message):
                return "气压计读取失败：\(message)"
            }
        }
    }

    private let altimeter = CMAltimeter()

    var isAvailable: Bool {
        CMAltimeter.isRelativeAltitudeAvailable()
    }

    func start(_ handler: @escaping (Result<BarometerReading, Error>) -> Void) {
        guard isAvailable else {
            handler(.failure(AltimeterError.unavailable))
            return
        }

        altimeter.startRelativeAltitudeUpdates(to: .main) { data, error in
            if let error {
                handler(.failure(AltimeterError.updateFailed(error.localizedDescription)))
                return
            }

            guard let data else {
                handler(.failure(AltimeterError.updateFailed("没有返回数据")))
                return
            }

            let reading = BarometerReading(
                pressureHPa: data.pressure.doubleValue * 10.0,
                relativeAltitudeMeters: data.relativeAltitude.doubleValue,
                timestamp: Date()
            )
            handler(.success(reading))
        }
    }

    func stop() {
        altimeter.stopRelativeAltitudeUpdates()
    }
}
