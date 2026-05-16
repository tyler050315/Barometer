import CoreLocation
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var currentPressureHPa: Double?
    @Published private(set) var altitudeMeters: Double?
    @Published private(set) var location: CLLocation?
    @Published private(set) var referenceAirport: AirportStation?
    @Published private(set) var statusText = "准备读取数据"
    @Published private(set) var statusSymbol = "circle"
    @Published private(set) var statusColor = Color.secondary
    @Published private(set) var isRefreshing = false

    private let altimeterService = AltimeterService()
    private let locationService = LocationService()
    private let aviationWeatherService = AviationWeatherService()
    private var hasStarted = false

    var locationText: String {
        guard let coordinate = location?.coordinate else {
            return "等待定位"
        }

        return String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        startAltimeter()
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        setStatus("正在定位", symbol: "location", color: .blue)

        do {
            let location = try await locationService.currentLocation()
            self.location = location

            setStatus("正在获取附近机场气压", symbol: "antenna.radiowaves.left.and.right", color: .blue)
            let airport = try await aviationWeatherService.nearestAirport(from: location)
            referenceAirport = airport
            updateAltitude()
            setStatus("数据已更新", symbol: "checkmark.circle.fill", color: .green)
        } catch {
            setStatus(error.localizedDescription, symbol: "exclamationmark.triangle.fill", color: .orange)
        }
    }

    private func startAltimeter() {
        guard altimeterService.isAvailable else {
            setStatus("此设备没有可用气压计", symbol: "exclamationmark.triangle.fill", color: .orange)
            return
        }

        altimeterService.start { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let reading):
                    self?.currentPressureHPa = reading.pressureHPa
                    self?.updateAltitude()
                case .failure(let error):
                    self?.setStatus(error.localizedDescription, symbol: "exclamationmark.triangle.fill", color: .orange)
                }
            }
        }
    }

    private func updateAltitude() {
        guard let stationPressureHPa = currentPressureHPa,
              let seaLevelPressureHPa = referenceAirport?.seaLevelPressureHPa else {
            return
        }

        altitudeMeters = AltitudeCalculator.altitudeMeters(
            stationPressureHPa: stationPressureHPa,
            seaLevelPressureHPa: seaLevelPressureHPa
        )
    }

    private func setStatus(_ text: String, symbol: String, color: Color) {
        statusText = text
        statusSymbol = symbol
        statusColor = color
    }
}
