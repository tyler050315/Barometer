import Foundation

struct MetarReport: Decodable {
    let icaoId: String
    let name: String?
    let rawText: String?
    let obsTime: Date?
    let lat: Double?
    let lon: Double?
    let altim: Double?
    let slp: Double?

    enum CodingKeys: String, CodingKey {
        case icaoId
        case stationId
        case name
        case site
        case rawText = "rawOb"
        case rawTextLegacy = "raw_text"
        case obsTime
        case observationTime = "observation_time"
        case lat
        case lon
        case altim
        case slp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        icaoId = try container.decodeFirstString(for: [.icaoId, .stationId]) ?? "----"
        name = try container.decodeFirstString(for: [.name, .site])
        rawText = try container.decodeFirstString(for: [.rawText, .rawTextLegacy])
        obsTime = try container.decodeFirstDate(for: [.obsTime, .observationTime])
        lat = try container.decodeFirstDouble(for: [.lat])
        lon = try container.decodeFirstDouble(for: [.lon])
        altim = try container.decodeFirstDouble(for: [.altim])
        slp = try container.decodeFirstDouble(for: [.slp])
    }

    var seaLevelPressureHPa: Double? {
        if let slp, slp > 800 {
            return slp
        }

        if let altim {
            return altim > 100 ? altim : altim * 33.8638866667
        }

        if let rawText {
            return Self.pressureFromRawMetar(rawText)
        }

        return nil
    }

    private static func pressureFromRawMetar(_ rawText: String) -> Double? {
        let tokens = rawText.split(separator: " ")

        for token in tokens {
            if token.hasPrefix("Q"), token.count == 5, let value = Double(token.dropFirst()) {
                return value
            }

            if token.hasPrefix("A"), token.count == 5, let value = Double(token.dropFirst()) {
                return value / 100.0 * 33.8638866667
            }
        }

        return nil
    }
}

private extension KeyedDecodingContainer where K == MetarReport.CodingKeys {
    func decodeFirstString(for keys: [K]) throws -> String? {
        for key in keys {
            if let value = try decodeIfPresent(String.self, forKey: key) {
                return value
            }
        }

        return nil
    }

    func decodeFirstDouble(for keys: [K]) throws -> Double? {
        for key in keys {
            if let value = try decodeIfPresent(Double.self, forKey: key) {
                return value
            }

            if let value = try decodeIfPresent(String.self, forKey: key), let number = Double(value) {
                return number
            }
        }

        return nil
    }

    func decodeFirstDate(for keys: [K]) throws -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        for key in keys {
            guard let value = try decodeIfPresent(String.self, forKey: key) else {
                continue
            }

            if let date = formatter.date(from: value) ?? fallbackFormatter.date(from: value) {
                return date
            }
        }

        return nil
    }
}
