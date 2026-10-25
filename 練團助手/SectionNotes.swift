import Foundation
import Combine

/// 每個段落的手寫重點，例如「這裡進 solo」「第二次不彈」「等鼓 fill」。
/// 存本地 UserDefaults，不回寫 project.json —— 這是「這次演出的提醒」，
/// 不是譜的一部分，跟著人走而不是跟著譜走。
///
/// 注意：這個 store 刻意不用 @Published。之前用 @Published 綁 TextField，
/// 每打一個字就重繪整棵畫面，打字會漏字（實測打 27 個字只進 12 個）。
/// 現在改成畫面各自持有草稿、只在變動時寫檔，store 不對外發布變更。
final class SectionNoteStore: ObservableObject {
    private static let defaultsKey = "sectionNotes.v1"
    private let defaults: UserDefaults
    private var notes: [String: String]

    /// 只在「筆記搬到別段」時跳號，打字時不跳。
    ///
    /// 這個 store 刻意不用 @Published（打字會漏字），所以搬家之後畫面不會自己更新 ——
    /// 各段的 TextEditor 綁的是自己的本地 draft，不會知道底層換了。
    /// 用這個版本號讓整份譜重建一次，draft 才會重新載入。
    @Published private(set) var moveVersion = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.notes = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }

    private func key(projectID: String, sectionID: String) -> String {
        "\(projectID)|\(sectionID)"
    }

    func note(projectID: String, sectionID: String) -> String {
        notes[key(projectID: projectID, sectionID: sectionID)] ?? ""
    }

    func setNote(_ text: String, projectID: String, sectionID: String) {
        let storageKey = key(projectID: projectID, sectionID: sectionID)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes.removeValue(forKey: storageKey)
        } else {
            notes[storageKey] = text
        }
        defaults.set(notes, forKey: Self.defaultsKey)
        DeviceSync.markChanged("sectionNotes.v1", defaults: defaults)
    }

    /// 把筆記搬到另一段。目標段已經有筆記就互換 ——
    /// 直接覆蓋會無聲吃掉一則已經寫好的提醒。
    func move(projectID: String, from: String, to: String) {
        let fromKey = key(projectID: projectID, sectionID: from)
        let toKey = key(projectID: projectID, sectionID: to)
        guard notes[fromKey] != nil || notes[toKey] != nil else { return }
        let moving = notes[fromKey]
        let displaced = notes[toKey]
        if let displaced { notes[fromKey] = displaced } else { notes.removeValue(forKey: fromKey) }
        if let moving { notes[toKey] = moving } else { notes.removeValue(forKey: toKey) }
        defaults.set(notes, forKey: Self.defaultsKey)
        DeviceSync.markChanged("sectionNotes.v1", defaults: defaults)
        moveVersion += 1
    }
}
