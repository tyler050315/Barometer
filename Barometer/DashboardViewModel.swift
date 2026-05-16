import CoreLocation
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    enum ReferenceMode: String, CaseIterable, Identifiable {
        case automatic = "自动"
        case manual = "手动"

        var id: String { rawValue }
    }

    @Published private(set) var currentPressureHPa: Double?
    @Published private(set) var altitudeMeters: Double?
    @Published private(set) var location: CLLocation?
    @Published private(set) var referenceAirport: AirportStation?
    @Published private(set) var statusText = "准备读取数据"
    @Published private(set) var statusSymbol = "circle"
    @Published private(set) var statusColor = Color.secondary
    @Published private(set) var isRefreshing = false
    @Published var referenceMode: ReferenceMode = .automatic
    @Published var manualICAO = ""
    @Published private(set) var lockedPressureHPa: Double?
    @Published private(set) var lockedAltitudeMeters: Double?
    @Published private(set) var lockedAt: Date?

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

    var lockText: String {
        guard let lockedPressureHPa, let lockedAt else {
            return "尚未锁定"
        }

        let altitudeText = UnitFormatter.altitude(lockedAltitudeMeters)
        return "\(UnitFormatter.pressure(lockedPressureHPa)) / \(altitudeText) / \(UnitFormatter.localTime(lockedAt))"
    }

    var relativeAltitudeText: String {
        UnitFormatter.signedAltitude(relativeAltitudeMeters)
    }

    var pressureTrendText: String {
        UnitFormatter.signedPressure(pressureDeltaHPa)
    }

    private var relativeAltitudeMeters: Double? {
        guard let lockedPressureHPa,
              let currentPressureHPa else {
            return nil
        }

        return AltitudeCalculator.altitudeMeters(
            stationPressureHPa: currentPressureHPa,
            seaLevelPressureHPa: lockedPressureHPa
        )
    }

    private var pressureDeltaHPa: Double? {
        guard let lockedPressureHPa,
              let currentPressureHPa else {
            return nil
        }

        return currentPressureHPa - lockedPressureHPa
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
            let airport: AirportStation
            if referenceMode == .manual {
                let icaoId = manualICAO.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard !icaoId.isEmpty else {
                    setStatus("请输入手动机场 ICAO 代码", symbol: "exclamationmark.triangle.fill", color: .orange)
                    return
                }

                airport = try await aviationWeatherService.airport(icaoId: icaoId, near: location)
                manualICAO = icaoId
            } else {
                airport = try await aviationWeatherService.nearestAirport(from: location)
            }

            referenceAirport = airport
            updateAltitude()
            setStatus("数据已更新", symbol: "checkmark.circle.fill", color: .green)
        } catch {
            setStatus(error.localizedDescription, symbol: "exclamationmark.triangle.fill", color: .orange)
        }
    }

    func lockCurrentPosition() {
        guard let currentPressureHPa else {
            setStatus("还没有可锁定的气压读数", symbol: "exclamationmark.triangle.fill", color: .orange)
            return
        }

        lockedPressureHPa = currentPressureHPa
        lockedAltitudeMeters = altitudeMeters
        lockedAt = Date()
        setStatus("已锁定当前位置", symbol: "lock.fill", color: .green)
    }

    func clearLock() {
        lockedPressureHPa = nil
        lockedAltitudeMeters = nil
        lockedAt = nil
        setStatus("已取消锁定", symbol: "lock.open.fill", color: .secondary)
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
