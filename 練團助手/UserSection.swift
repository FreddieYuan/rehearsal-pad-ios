import Foundation
import Combine

/// 自己標的段落。
///
/// 自動偵測的段落常常不只是偏一點，而是整個錯 —— 《你要的愛》的切點
/// （30/80/140 秒）直接切穿副歌，而副歌其實一模一樣出現三次。
/// 這種錯用「往前移一行」救不了，只能自己標。
///
/// 一旦這首歌有自訂段落，就**完全**以自訂的為準，不再混用自動偵測的結果 ——
/// 混用只會讓人搞不清楚眼前這條線是誰畫的。第一次新增時會把當下的自動切點
/// 先抄進來當底稿，所以不會一按就把整首歌的結構清空。
final class UserSectionStore: ObservableObject {
    private static let defaultsKey = "userSections.v1"
    private let defaults: UserDefaults
    /// projectID → ["49.68|Chorus", …]。用字串編碼是為了 UserDefaults 存得下去，
    /// 巢狀的 [[String: Any]] 讀回來要一層層轉型，不值得。
    private var stored: [String: [String]]

    @Published private(set) var version = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.stored = defaults.dictionary(forKey: Self.defaultsKey) as? [String: [String]] ?? [:]
    }

    struct Entry: Equatable {
        let time: Double
        let label: String
    }

    func hasCustom(projectID: String) -> Bool {
        !(stored[projectID] ?? []).isEmpty
    }

    func sections(projectID: String) -> [Entry] {
        (stored[projectID] ?? []).compactMap { raw in
            let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let time = Double(parts[0]) else { return nil }
            return Entry(time: time, label: parts[1])
        }.sorted { $0.time < $1.time }
    }

    private func write(_ entries: [Entry], projectID: String) {
        let sorted = entries.sorted { $0.time < $1.time }
        if sorted.isEmpty {
            stored.removeValue(forKey: projectID)
        } else {
            stored[projectID] = sorted.map { String(format: "%.2f|%@", $0.time, $0.label) }
        }
        defaults.set(stored, forKey: Self.defaultsKey)
        DeviceSync.markChanged("userSections.v1", defaults: defaults)
        version += 1
    }

    /// 在某個時間點開一個新段落。`seed` 是這首歌目前的切點，
    /// 第一次新增時拿來當底稿，免得一按就清空整首歌的結構。
    func add(time: Double, label: String, projectID: String, seed: [Entry]) {
        var entries = hasCustom(projectID: projectID) ? sections(projectID: projectID) : seed
        entries.removeAll { abs($0.time - time) < 0.05 }
        entries.append(Entry(time: time, label: label))
        write(entries, projectID: projectID)
    }

    func rename(time: Double, to label: String, projectID: String) {
        var entries = sections(projectID: projectID)
        guard let index = entries.firstIndex(where: { abs($0.time - time) < 0.05 }) else { return }
        entries[index] = Entry(time: entries[index].time, label: label)
        write(entries, projectID: projectID)
    }

    func remove(time: Double, projectID: String) {
        var entries = sections(projectID: projectID)
        entries.removeAll { abs($0.time - time) < 0.05 }
        write(entries, projectID: projectID)
    }

    /// 全部丟掉，回到自動偵測的結果。
    func reset(projectID: String) {
        write([], projectID: projectID)
    }

    /// 段落名稱選單。照樂手講話的順序排，不是字母序。
    ///
    /// **存的是英文、顯示的是中文。** 段落名稱會進到 SheetSection.id
    /// （`"\(base)-\(anchor)"`），而段落筆記是用那個 id 當 key ——
    /// 存中文的話，哪天想改顯示方式就會把所有筆記打斷。
    static let labels = [
        "Intro", "Verse", "Pre-Chorus", "Chorus", "Bridge",
        "Solo", "Interlude", "Break", "Outro", "Ending",
    ]
}

/// 段落名稱的顯示層。只管畫面，不動存的值。
enum SectionLabel {
    private static let table = [
        "Intro": "前奏",
        "Verse": "主歌",
        "Pre-Chorus": "導歌",
        "Chorus": "副歌",
        "Bridge": "橋段",
        "Interlude": "間奏",
        "Outro": "尾奏",
        "Ending": "結尾",
        "Theme": "主題",
        "Fade Out": "淡出",
        "Song": "全曲",
        // Solo 跟 Break 樂手本來就講英文，硬翻反而卡。
    ]

    static func display(_ label: String) -> String {
        if let mapped = table[label] { return mapped }
        // 自動偵測認不出結構時會給 "Section 0" 這種佔位名稱。
        // 直接標成「未命名」比翻成「段落 0」誠實 —— 那個數字只是格子編號，沒有意義。
        if let match = label.range(of: "^Section\\s*", options: .regularExpression) {
            let tail = label[match.upperBound...].trimmingCharacters(in: .whitespaces)
            return tail.isEmpty ? "未命名" : "未命名 \(tail)"
        }
        return label
    }
}
