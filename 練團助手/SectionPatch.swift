import Foundation
import Combine

/// 每個段落各自的 Nord 音色。
///
/// 原則是「每一段都有音色選擇和筆記」—— 筆記本來就是一段一則，音色以前卻是
/// 一首歌四格、再由自動推薦決定哪一段換。自動推薦實測幾乎沒有鑑別力
/// （24 首有註記的歌裡 23 首在同一首歌內風琴電鋼跳來跳去），所以改成
/// 跟筆記同一個模型：**你自己標的段落，你自己指定音色**。
///
/// key 跟段落筆記完全一樣（`"<projectID>|<sectionID>"`），兩者會一起脫鉤或一起存活 ——
/// 段落切點被刪掉時，筆記和音色是同一個命運，不會只掉一半。
final class SectionPatchStore: ObservableObject {
    private static let defaultsKey = "sectionPatches.v1"
    private let defaults: UserDefaults
    private var patches: [String: String]

    @Published private(set) var version = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.patches = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }

    private func key(projectID: String, sectionID: String) -> String {
        "\(projectID)|\(sectionID)"
    }

    func raw(projectID: String, sectionID: String) -> String? {
        patches[key(projectID: projectID, sectionID: sectionID)]
    }

    /// 整個曲庫用過的音色 → 次數。給選單的「常用」區用。
    var usedCounts: [String: Int] {
        patches.values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    func setRaw(_ value: String?, projectID: String, sectionID: String) {
        let storageKey = key(projectID: projectID, sectionID: sectionID)
        if let value, !value.isEmpty {
            patches[storageKey] = value
        } else {
            patches.removeValue(forKey: storageKey)
        }
        defaults.set(patches, forKey: Self.defaultsKey)
        DeviceSync.markChanged("sectionPatches.v1", defaults: defaults)
        version += 1
    }
}
