import Foundation

enum MusicTransposer {
    private static let notes = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    private static let enharmonic = [
        "C#": "Db", "D#": "Eb", "F#": "Gb", "G#": "Ab", "A#": "Bb",
        "Cb": "B", "Fb": "E", "E#": "F", "B#": "C"
    ]

    static func transposeChord(_ chord: String, semitones: Int) -> String {
        guard semitones != 0, !chord.isEmpty else { return chord }
        let parts = chord.split(separator: "/", maxSplits: 1).map(String.init)
        let main = transposePart(parts[0], semitones: semitones)
        guard parts.count == 2 else { return main }
        return "\(main)/\(transposePart(parts[1], semitones: semitones))"
    }

    static func transposeKey(_ key: String, semitones: Int) -> String {
        guard semitones != 0, !key.isEmpty else { return key }
        let parts = key.split(separator: " ", maxSplits: 1).map(String.init)
        let root = transposeNote(parts[0], semitones: semitones)
        guard parts.count == 2 else { return root }
        return "\(root) \(parts[1])"
    }

    private static func transposePart(_ part: String, semitones: Int) -> String {
        guard let match = part.firstMatch(of: /^([A-G](?:b|#)?)(.*)$/) else { return part }
        return transposeNote(String(match.1), semitones: semitones) + String(match.2)
    }

    private static func transposeNote(_ note: String, semitones: Int) -> String {
        let normalized = enharmonic[note] ?? note
        guard let index = notes.firstIndex(of: normalized) else { return note }
        let next = (index + semitones % 12 + 12) % 12
        return notes[next]
    }
}
