import Foundation

struct SongProject: Codable, Identifiable {
    let schemaVersion: Int
    let id: String
    var song: SongInfo
    var analysis: Analysis
    var sections: [SongSection]
    var lyrics: [LyricLine]
    var chords: [ChordEvent]
    var bandNotes: [BandNote]
    var sources: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id
        case song
        case analysis
        case sections
        case lyrics
        case chords
        case bandNotes = "band_notes"
        case sources
    }
}

struct SongInfo: Codable {
    var title: String
    var artist: String
    var sourceURL: String?
    var audioPath: String?
    var previewPath: String?
    var artworkPath: String?
    var durationSec: Double?

    enum CodingKeys: String, CodingKey {
        case title
        case artist
        case sourceURL = "source_url"
        case audioPath = "audio_path"
        case previewPath = "preview_path"
        case artworkPath = "artwork_path"
        case durationSec = "duration_sec"
    }
}

struct Analysis: Codable {
    var bpm: Double?
    var key: String
}

struct SongSection: Codable, Identifiable {
    var id: String
    var label: String
    var start: Double
    var end: Double?
    var source: String?
}

struct LyricLine: Codable, Identifiable {
    var id: String { "\(start)-\(text)" }
    var start: Double
    var end: Double
    var text: String
    var source: String?
}

struct ChordEvent: Codable, Identifiable {
    var id: String { "\(time)-\(chord)" }
    var time: Double
    var chord: String
    var source: String?
    var confidence: Double?
}

struct BandNote: Codable, Identifiable {
    var id: String { "\(instrument)-\(time ?? -1)-\(label)" }
    var instrument: String
    var label: String
    var time: Double?
    var detail: String
    var source: String?
}

enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
