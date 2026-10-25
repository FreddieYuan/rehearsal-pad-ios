import Foundation

// 和弦符號 → 音。用來畫鍵盤提示圖。
// 全庫掃過只有 17 種後綴（m m7 7 maj7 add9 sus4 sus2 9 6 m6 m11 7sus4 dim aug
// m7b5 madd9 加分數和弦低音），是封閉集合，所以這裡用查表而不是通用解析器。

struct ChordShape {
    /// 根音的音級（0 = C）。
    let root: Int
    /// 分數和弦的低音音級，例如 C/G 的 G。
    let bass: Int?
    /// 各組成音距離根音的半音數，由低到高。
    let intervals: [Int]
    /// 沒認出來的後綴，畫圖時要標示「這個我不確定」。
    let isRecognised: Bool

    /// 所有組成音的音級（含低音）。
    var pitchClasses: [Int] {
        var result = intervals.map { (root + $0) % 12 }
        if let bass, !result.contains(bass) { result.append(bass) }
        return result
    }

    /// 音名，由低到高；分數和弦的低音排最前面。
    var noteNames: [String] {
        var names: [String] = []
        if let bass { names.append(ChordShape.noteName(bass)) }
        for interval in intervals {
            let name = ChordShape.noteName((root + interval) % 12)
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    private static let flatNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    static func noteName(_ pitchClass: Int) -> String {
        flatNames[((pitchClass % 12) + 12) % 12]
    }

    private static let pitchClassByName: [String: Int] = [
        "C": 0, "B#": 0,
        "C#": 1, "Db": 1,
        "D": 2,
        "D#": 3, "Eb": 3,
        "E": 4, "Fb": 4,
        "F": 5, "E#": 5,
        "F#": 6, "Gb": 6,
        "G": 7,
        "G#": 8, "Ab": 8,
        "A": 9,
        "A#": 10, "Bb": 10,
        "B": 11, "Cb": 11,
    ]

    /// 後綴 → 距離根音的半音數。維持由低到高。
    private static let intervalsByQuality: [String: [Int]] = [
        "": [0, 4, 7],
        "m": [0, 3, 7],
        "min": [0, 3, 7],
        "m7": [0, 3, 7, 10],
        "7": [0, 4, 7, 10],
        "maj7": [0, 4, 7, 11],
        "M7": [0, 4, 7, 11],
        "6": [0, 4, 7, 9],
        "m6": [0, 3, 7, 9],
        "9": [0, 4, 7, 10, 14],
        "maj9": [0, 4, 7, 11, 14],
        "m9": [0, 3, 7, 10, 14],
        "m11": [0, 3, 7, 10, 14, 17],
        "11": [0, 4, 7, 10, 14, 17],
        "13": [0, 4, 7, 10, 14, 21],
        "add9": [0, 4, 7, 14],
        "madd9": [0, 3, 7, 14],
        "sus4": [0, 5, 7],
        "sus2": [0, 2, 7],
        "7sus4": [0, 5, 7, 10],
        "sus": [0, 5, 7],
        "dim": [0, 3, 6],
        "dim7": [0, 3, 6, 9],
        "m7b5": [0, 3, 6, 10],
        "aug": [0, 4, 8],
        "+": [0, 4, 8],
        "5": [0, 7],
    ]

    /// 解析 "Am7"、"C/G"、"F#m7b5" 這類符號。認不出來就退回大三和弦並標記。
    static func parse(_ symbol: String) -> ChordShape? {
        let text = symbol.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        var body = text
        var bass: Int?
        if let slash = body.lastIndex(of: "/") {
            let bassText = String(body[body.index(after: slash)...])
            if let pitchClass = pitchClassByName[bassText] {
                bass = pitchClass
                body = String(body[..<slash])
            }
        }

        guard let match = body.range(of: "^[A-G](b|#)?", options: .regularExpression) else { return nil }
        let rootText = String(body[match])
        guard let root = pitchClassByName[rootText] else { return nil }

        let quality = String(body[match.upperBound...])
        if let intervals = intervalsByQuality[quality] {
            return ChordShape(root: root, bass: bass, intervals: intervals, isRecognised: true)
        }
        return ChordShape(root: root, bass: bass, intervals: [0, 4, 7], isRecognised: false)
    }
}
