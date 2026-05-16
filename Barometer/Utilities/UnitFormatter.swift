import Foundation

enum UnitFormatter {
    static func pressure(_ value: Double?) -> String {
        guard let value else {
            return "-- hPa"
        }

        return String(format: "%.1f hPa", value)
    }

    static func altitude(_ value: Double?) -> String {
        guard let value else {
            return "-- m"
        }

        return String(format: "%.0f m", value)
    }

    static func distance(_ value: Double) -> String {
        String(format: "%.1f km", value)
    }

    static func signedAltitude(_ value: Double?) -> String {
        guard let value else {
            return "-- m"
        }

        return String(format: "%+.1f m", value)
    }

    static func signedPressure(_ value: Double?) -> String {
        guard let value else {
            return "-- hPa"
        }

        return String(format: "%+.2f hPa", value)
    }

    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    static func localTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
