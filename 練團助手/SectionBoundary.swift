import Foundation
import Combine

/// 段落切點的人工修正。
///
/// 上游的段落是自動偵測的，很多歌切在 10 秒整數格上（0/30/80/140…），
/// 根本沒對齊樂句 —— 例如《你要的愛》切在 30.00 秒，但
/// 「雖然不曾懷疑你」(26.96) 跟「還是忐忑不定」(33.80) 是一組對句，
/// 切點晚了一行。這裡存「這個段落往前／往後移幾行歌詞」。
///
/// key 用**原始**切點時間，不是修正後的：修正後的時間會跟著位移變，
/// 拿它當 key 會讓下一次查不到自己剛存的值。
final class SectionBoundaryStore: ObservableObject {
    private static let defaultsKey = "sectionOffsets.v1"
    private let defaults: UserDefaults
    private var offsets: [String: Int]

    /// 改切點會影響整份譜（段落重複判定、和弦分配都跟著變），所以整份重算。
    @Published private(set) var version = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.offsets = defaults.dictionary(forKey: Self.defaultsKey) as? [String: Int] ?? [:]
    }

    private func key(projectID: String, anchor: Double) -> String {
        String(format: "%@|%.2f", projectID, anchor)
    }

    func offset(projectID: String, anchor: Double) -> Int {
        offsets[key(projectID: projectID, anchor: anchor)] ?? 0
    }

    func setOffset(_ value: Int, projectID: String, anchor: Double) {
        let storageKey = key(projectID: projectID, anchor: anchor)
        if value == 0 {
            offsets.removeValue(forKey: storageKey)
        } else {
            offsets[storageKey] = value
        }
        defaults.set(offsets, forKey: Self.defaultsKey)
        DeviceSync.markChanged("sectionOffsets.v1", defaults: defaults)
        version += 1
    }

    func nudge(by delta: Int, projectID: String, anchor: Double) {
        setOffset(offset(projectID: projectID, anchor: anchor) + delta,
                  projectID: projectID, anchor: anchor)
    }
}
