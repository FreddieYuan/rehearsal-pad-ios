import Foundation
import Combine

// Nord Electro 4D 的音色註記解析。
// band_notes 裡的 detail 長這樣：
//   "E Piano MKII [Pgm 01:3]"
//   "All Draws Out [Pgm 05:1] — 88 8888 888"
//   "Official organ/keyboard chart"        ← 沒有 Pgm 的自由文字
// 網頁版把 [Pgm ...] 當雜訊砍掉，在桌上看沒差；站在台上，Pgm 編號跟抽把設定
// 才是真正要用的東西，所以這裡全部留下來。

struct NordPatch: Equatable {
    /// 音色名稱，例如 "E Piano MKII"。
    let name: String
    /// Nord 面板上要轉到的位置，例如 "01:3"。沒有就是自由文字註記。
    let program: String?
    /// B3 抽把設定，例如 "88 8888 888"。
    let drawbars: String?
    /// 從音色表查到的分類，例如 "Organ — B3"。
    let category: String?

    /// 同一顆音色（不管註記文字有沒有差異）。
    func isSameSound(as other: NordPatch) -> Bool {
        if let program, let otherProgram = other.program {
            return program == otherProgram
        }
        return name == other.name
    }

    /// 畫面上顯示的 Program 編號。
    /// 資料裡是 "19:1"，但冒號看起來像時間碼，台上容易看錯，所以顯示成 "19-1"。
    /// 注意 `program` 本身維持原樣 —— 它是自訂音色的識別 key，改了會讓存過的覆寫失效。
    var programDisplay: String? {
        program?.replacingOccurrences(of: ":", with: "-")
    }

    /// 給顏色用的粗分類。
    enum Family {
        case organ, piano, electricPiano, clav, sample, unknown
    }

    var family: Family {
        guard let category else { return .unknown }
        if category.hasPrefix("Organ") { return .organ }
        if category.hasPrefix("Electric Piano") { return .electricPiano }
        if category.hasPrefix("Piano") { return .piano }
        if category.hasPrefix("Clav") { return .clav }
        if category.hasPrefix("Sample") { return .sample }
        return .unknown
    }
}

/// 音色表裡的一個分類，例如「Organ — B3」。
struct NordCategory: Identifiable {
    var id: String { name }
    let name: String
    /// 原始顯示字串（要存回覆寫時用這個），配上解析後的內容（畫面上用）。
    let entries: [(raw: String, patch: NordPatch)]
}

/// 從 bandpack 根目錄的 nord_patches.json 讀進來的音色分類表。
struct NordCatalog {
    /// 正規化後的音色名稱 → 分類名稱。
    private let categoryByPatch: [String: String]
    /// 給下拉選單用的完整清單，順序照音色表。
    let categories: [NordCategory]

    static let empty = NordCatalog(categoryByPatch: [:], categories: [])

    private init(categoryByPatch: [String: String], categories: [NordCategory]) {
        self.categoryByPatch = categoryByPatch
        self.categories = categories
    }

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawCategories = root["categories"] as? [[String: Any]] else { return nil }

        var map: [String: String] = [:]
        var built: [NordCategory] = []
        for category in rawCategories {
            guard let name = category["name"] as? String,
                  let patches = category["patches"] as? [String] else { continue }
            var entries: [(raw: String, patch: NordPatch)] = []
            for patch in patches {
                let parsed = NordPatch.parse(patch, catalog: nil)
                map[NordCatalog.key(parsed.name)] = name
                if let program = parsed.program {
                    map["pgm:" + program] = name
                }
                entries.append((patch, parsed))
            }
            built.append(NordCategory(name: name, entries: entries))
        }
        self.categoryByPatch = map
        self.categories = built
    }

    func category(forName name: String, program: String?) -> String? {
        if let program, let hit = categoryByPatch["pgm:" + program] { return hit }
        return categoryByPatch[NordCatalog.key(name)]
    }

    private static func key(_ name: String) -> String {
        name.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

extension NordPatch {
    /// 拆 "名稱 [Pgm 05:1] — 88 8888 888"。
    static func parse(_ detail: String, catalog: NordCatalog?) -> NordPatch {
        let text = detail.trimmingCharacters(in: .whitespacesAndNewlines)

        var program: String?
        if let range = text.range(of: "\\[Pgm\\s*([^\\]]*)\\]", options: .regularExpression) {
            let inside = text[range]
                .replacingOccurrences(of: "[Pgm", with: "")
                .replacingOccurrences(of: "]", with: "")
                .trimmingCharacters(in: .whitespaces)
            program = inside.isEmpty ? nil : inside
        }

        // 抽把設定寫在破折號後面，只由數字跟空白組成。
        var drawbars: String?
        if let dash = text.range(of: "—") ?? text.range(of: " - ") {
            let tail = text[dash.upperBound...].trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty, tail.allSatisfy({ $0.isNumber || $0.isWhitespace }) {
                drawbars = tail
            }
        }

        var name = text
        if let range = name.range(of: "\\s*\\[Pgm[^\\]]*\\].*$", options: .regularExpression) {
            name.removeSubrange(range)
        }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = text }

        return NordPatch(
            name: name,
            program: program,
            drawbars: drawbars,
            category: catalog?.category(forName: name, program: program)
        )
    }
}


// MARK: - 使用者自訂音色

/// 每首歌固定給幾格音色可以自己填，不管原始資料有沒有。
///
/// 格子的解析順序：使用者填過的優先，沒填過就落回原始資料的第 i 顆推薦音色，
/// 兩個都沒有就是空格。所以「改掉推薦」跟「自己補一顆」是同一個動作，
/// 不用分成兩種覆寫。
///
/// 一樣只存本地，不回寫 project.json：Streamlit 那邊才是譜的來源。
final class NordPatchOverrideStore: ObservableObject {
    /// 每首歌至少給這麼多格；原始資料更多就給更多，不能把真實資料藏起來。
    static let minimumSlots = 4

    private static let slotsKey = "nordPatchSlots.v2"
    private let defaults: UserDefaults
    private var slots: [String: String]

    /// 只是給畫面一個「該重算了」的訊號。改音色是偶發動作，重算整份譜沒有負擔。
    @Published private(set) var version = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.slots = defaults.dictionary(forKey: Self.slotsKey) as? [String: String] ?? [:]
    }

    private func key(projectID: String, index: Int) -> String {
        "\(projectID)|\(index)"
    }

    func slotPatch(projectID: String, index: Int) -> String? {
        slots[key(projectID: projectID, index: index)]
    }

    func setSlotPatch(_ raw: String?, projectID: String, index: Int) {
        let storageKey = key(projectID: projectID, index: index)
        if let raw { slots[storageKey] = raw } else { slots.removeValue(forKey: storageKey) }
        defaults.set(slots, forKey: Self.slotsKey)
        DeviceSync.markChanged("nordPatchSlots.v2", defaults: defaults)
        version += 1
    }

    /// 整個曲庫用過的音色 → 次數。給選單的「常用」區用。
    var usedCounts: [String: Int] {
        slots.values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    func isCustom(projectID: String, index: Int) -> Bool {
        slotPatch(projectID: projectID, index: index) != nil
    }
}
