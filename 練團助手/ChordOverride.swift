import Foundation
import Combine

/// 手改和弦。
///
/// 譜上的和弦是 BTC 模型直接從音訊辨識的，沒有人工校對，偶爾會聽錯 ——
/// 借用和弦、掛留、轉位這幾類最常錯。這裡存「哪一拍改成什麼」，蓋在上游資料上，
/// 不回寫 project.json（上游重跑時不會被洗掉，也不會假裝模型變準了）。
///
/// key 用「時間」而不是陣列索引：上游重匯時分段數可能變，索引會整排位移，
/// 但一顆和弦落在第幾秒幾乎不會動。取兩位小數就夠 —— BTC 最短段是 0.4 秒。
final class ChordOverrideStore: ObservableObject {
    private static let defaultsKey = "chordOverrides.v1"
    private let defaults: UserDefaults
    private var symbols: [String: String]

    /// 改一顆和弦會影響整份譜（段落重複判定、和弦一覽、鍵盤提示都要跟著變），
    /// 所以用版本號讓 SongDetailView 整個重建，而不是只換那一顆字。
    @Published private(set) var version = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.symbols = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }

    private func key(projectID: String, time: Double) -> String {
        String(format: "%@|%.2f", projectID, time)
    }

    func symbol(projectID: String, time: Double) -> String? {
        symbols[key(projectID: projectID, time: time)]
    }

    func isCustom(projectID: String, time: Double) -> Bool {
        symbol(projectID: projectID, time: time) != nil
    }

    /// 傳 nil 代表改回原本。
    func setSymbol(_ symbol: String?, projectID: String, time: Double) {
        let storageKey = key(projectID: projectID, time: time)
        if let symbol, !symbol.isEmpty {
            symbols[storageKey] = symbol
        } else {
            symbols.removeValue(forKey: storageKey)
        }
        defaults.set(symbols, forKey: Self.defaultsKey)
        DeviceSync.markChanged("chordOverrides.v1", defaults: defaults)
        version += 1
    }

    /// 把覆蓋套上去。整條鏈都吃這個結果，所以段落重複判定看到的也是改過的和弦。
    func apply(to chords: [ChordEvent], projectID: String) -> [ChordEvent] {
        guard !symbols.isEmpty else { return chords }
        return chords.map { event in
            guard let replacement = symbol(projectID: projectID, time: event.time) else { return event }
            var corrected = event
            corrected.chord = replacement
            corrected.source = "manual"
            corrected.confidence = nil
            return corrected
        }
    }
}

/// 選和弦時給的選項。
///
/// 故意只列 ChordShape 認得的後綴 —— 挑得出來卻畫不出鍵盤圖的和弦，
/// 對鍵盤手來說等於沒改到。
enum ChordChoice {
    static let roots = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    /// (顯示, 後綴)。順序照常用度排，不是照理論排。
    static let qualities: [(label: String, suffix: String)] = [
        ("大三", ""),
        ("m", "m"),
        ("7", "7"),
        ("m7", "m7"),
        ("maj7", "maj7"),
        ("sus4", "sus4"),
        ("sus2", "sus2"),
        ("add9", "add9"),
        ("6", "6"),
        ("m6", "m6"),
        ("9", "9"),
        ("maj9", "maj9"),
        ("m9", "m9"),
        ("madd9", "madd9"),
        ("7sus4", "7sus4"),
        ("m7b5", "m7b5"),
        ("dim", "dim"),
        ("dim7", "dim7"),
        ("aug", "aug"),
        ("5", "5"),
    ]

    /// 拆成 (根音, 後綴, 低音)。認不出來就回 nil，讓畫面退回預設值。
    static func split(_ symbol: String) -> (root: String, quality: String, bass: String)? {
        var body = symbol.trimmingCharacters(in: .whitespaces)
        var bass = ""
        if let slash = body.lastIndex(of: "/") {
            bass = String(body[body.index(after: slash)...])
            body = String(body[..<slash])
        }
        guard let match = body.range(of: "^[A-G](b|#)?", options: .regularExpression) else { return nil }
        return (String(body[match]), String(body[match.upperBound...]), bass)
    }

    static func compose(root: String, quality: String, bass: String) -> String {
        bass.isEmpty || bass == root ? root + quality : "\(root)\(quality)/\(bass)"
    }
}
