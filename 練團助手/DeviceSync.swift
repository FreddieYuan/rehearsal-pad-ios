import Foundation

/// iPad 跟 iPhone 之間同步「使用者自己排的東西」。
///
/// 為什麼不用 iCloud：免費開發者帳號的描述檔只給 application-identifier、
/// team-identifier、get-task-allow、keychain-access-groups 四個 entitlement，
/// 沒有 iCloud，所以 NSUbiquitousKeyValueStore 用不了（要付費帳號才開得了）。
///
/// 替代方案：App 把狀態寫成 Documents/sync-state.json，Mac 端（sync-devices.sh）
/// 用 devicectl 讀出兩台的檔案、逐項比時間，再把贏的那幾項寫回落後那台的
/// Documents/sync-inbox.json。下次啟動時 App 就會吃掉 inbox。
/// 同步點是「插上線跑一次腳本」，不是即時。
///
/// 時間戳是「逐項」而不是整份的：在 iPhone 改曲序，不該把 iPad 上寫的段落筆記
/// 一起蓋掉。沒有被真的改過的項目時間戳是 0，永遠輸給有改過的那一邊。
enum DeviceSync {

    /// 會同步的 UserDefaults key。
    ///
    /// 只放「內容」—— 曲序、段落筆記、自訂音色。
    /// 字級、和弦表開關這類是裝置各自的使用習慣（iPad 要大、手機要小），
    /// 同步過去反而礙事，所以刻意不收。
    static let syncedKeys = [
        "songOrder.v1",
        "sectionNotes.v1",
        "nordPatchSlots.v2",
        "chordOverrides.v1",
        "sectionOffsets.v1",
        "userSections.v1",
        "sectionPatches.v1",
    ]

    /// 每個 key 最後一次「真的被使用者改到」的時間。沒有記錄 = 0 = 只是開機時
    /// 順手匯出的既有資料，沒有可信的修改時間。
    private static let stampsKey = "deviceSync.stamps.v1"
    private static let formatVersion = 2

    private static var documents: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private static var stateURL: URL? { documents?.appendingPathComponent("sync-state.json") }
    private static var inboxURL: URL? { documents?.appendingPathComponent("sync-inbox.json") }

    private static func stamps(_ defaults: UserDefaults) -> [String: Double] {
        defaults.dictionary(forKey: stampsKey) as? [String: Double] ?? [:]
    }

    // MARK: - 匯出給 Mac 讀

    /// 某一項被使用者改掉了：更新它的時間戳，然後立刻重寫 sync-state.json。
    ///
    /// 要即時寫，不能只靠進背景時匯出 —— 改完直接拔線就漏掉了。
    static func markChanged(_ key: String, defaults: UserDefaults = .standard) {
        var current = stamps(defaults)
        current[key] = Date().timeIntervalSince1970
        defaults.set(current, forKey: stampsKey)
        exportState(defaults: defaults)
    }

    /// 把目前狀態寫成 sync-state.json。
    static func exportState(defaults: UserDefaults = .standard) {
        guard let stateURL else { return }
        let stamps = stamps(defaults)
        var entries: [String: Any] = [:]
        for key in syncedKeys {
            guard let value = defaults.object(forKey: key) else { continue }
            entries[key] = ["updatedAt": stamps[key] ?? 0, "value": value]
        }
        let payload: [String: Any] = [
            "version": formatVersion,
            "writtenAt": Date().timeIntervalSince1970,
            "entries": entries,
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    /// 還沒有 sync-state.json（或還是舊格式）時，把目前的狀態寫出來當起點。
    /// 不然要等到使用者下次改東西，Mac 才讀得到任何東西。
    /// 已經是現行格式就不碰 —— 免得用開機時間蓋掉真正的最後修改時間。
    static func bootstrapIfNeeded(defaults: UserDefaults = .standard) {
        guard let stateURL else { return }
        if let data = try? Data(contentsOf: stateURL),
           let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           payload["version"] as? Int == formatVersion {
            return
        }
        exportState(defaults: defaults)
    }

    // MARK: - 吃掉 Mac 送進來的

    /// 有 inbox 就套用並刪除。回傳有沒有真的改到東西。
    ///
    /// 必須在任何 store 讀 UserDefaults **之前**呼叫 —— SongLibrary 一建立
    /// 就會讀曲序，晚一步套用就要等下次啟動才生效。
    @discardableResult
    static func importInbox(defaults: UserDefaults = .standard) -> Bool {
        guard let inboxURL,
              FileManager.default.fileExists(atPath: inboxURL.path),
              let data = try? Data(contentsOf: inboxURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = payload["entries"] as? [String: [String: Any]]
        else { return false }

        var newStamps = stamps(defaults)
        var changed = false
        for key in syncedKeys {
            guard let entry = entries[key], let incoming = entry["value"] else { continue }
            defaults.set(incoming, forKey: key)
            // 連時間戳一起繼承。不然這台會看起來比來源新，下次同步又倒推回去。
            newStamps[key] = entry["updatedAt"] as? Double ?? 0
            changed = true
        }
        defaults.set(newStamps, forKey: stampsKey)
        try? FileManager.default.removeItem(at: inboxURL)
        if changed { exportState(defaults: defaults) }
        return changed
    }
}
