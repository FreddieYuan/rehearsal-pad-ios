import Foundation
import Combine

final class SongLibrary: ObservableObject {
    @Published private(set) var projects: [SongProject] = []
    @Published var selectedProjectID: String?
    /// Nord 音色分類表，跟 bandpack 一起打包進來；沒有就退成沒有分類。
    private(set) var nordCatalog: NordCatalog = .empty

    /// 使用者手動拖曳的曲序，存 project id 陣列。
    private static let orderDefaultsKey = "songOrder.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadNordCatalog()
        loadBundledBandpacks()
    }

    var selectedProject: SongProject? {
        guard let selectedProjectID else { return projects.first }
        return projects.first { $0.id == selectedProjectID } ?? projects.first
    }

    func moveProjects(from source: IndexSet, to destination: Int) {
        let sortedSource = source.sorted()
        let moving = sortedSource.map { index in projects[index] }
        for index in sortedSource.reversed() {
            projects.remove(at: index)
        }
        let removedBeforeDestination = sortedSource.filter { index in index < destination }.count
        let adjustedDestination = max(0, min(destination - removedBeforeDestination, projects.count))
        projects.insert(contentsOf: moving, at: adjustedDestination)
        persistOrder()
    }

    func audioURL(for project: SongProject) -> URL? {
        let audioPath = project.song.previewPath ?? project.song.audioPath ?? ""
        guard !audioPath.isEmpty else { return nil }
        let packName = "\(project.id).bandpack"
        return Bundle.main.url(forResource: audioPath, withExtension: nil, subdirectory: "Bandpacks.bundle/\(packName)")
    }

    func artworkURL(for project: SongProject) -> URL? {
        guard let path = project.song.artworkPath, !path.isEmpty else { return nil }
        let packName = "\(project.id).bandpack"
        return Bundle.main.url(forResource: path, withExtension: nil, subdirectory: "Bandpacks.bundle/\(packName)")
    }

    private func loadNordCatalog() {
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("Bandpacks.bundle/nord_patches.json"),
              let catalog = NordCatalog(url: url) else { return }
        nordCatalog = catalog
    }

    /// 這首歌打包進來的分軌。沒有就回空陣列，畫面自動退回單軌試聽。
    func stemTracks(for project: SongProject) -> [StemPlayer.Track] {
        let packName = "\(project.id).bandpack"
        let reference = keyboardReferenceStem(for: project)
        return StemPlayer.order.compactMap { entry in
            guard let url = Bundle.main.url(
                forResource: "stems/\(entry.id).m4a",
                withExtension: nil,
                subdirectory: "Bandpacks.bundle/\(packName)"
            ) else { return nil }
            return StemPlayer.Track(
                id: entry.id,
                name: entry.name,
                url: url,
                isKeyboardReference: entry.id == reference
            )
        }
    }

    /// 這首歌要聽鍵盤該挑哪一軌。
    ///
    /// 分軌模型的 piano 類別只認鋼琴，Hammond organ 會被丟進 other，
    /// 所以風琴曲 solo「鍵盤」只會聽到空的。匯出時已經量過音量標好了，
    /// 這裡只是把答案讀出來。
    func keyboardReferenceStem(for project: SongProject) -> String? {
        guard case .string(let value)? = project.sources["keyboard_reference_stem"],
              !value.isEmpty else { return nil }
        return value
    }

    private func loadBundledBandpacks() {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Bandpacks.bundle") else {
            projects = []
            return
        }
        let packs = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )) ?? []

        let decoded = packs
            .filter { $0.pathExtension == "bandpack" }
            .compactMap { pack -> SongProject? in
                let url = pack.appendingPathComponent("project.json")
                guard let data = try? Data(contentsOf: url) else { return nil }
                let decoder = JSONDecoder()
                return try? decoder.decode(SongProject.self, from: data)
            }
        let ordered = applySavedOrder(to: defaultSorted(decoded))
        projects = ordered
        selectedProjectID = ordered.first?.id
    }

    /// 預設排序：歌手，再曲名。
    private func defaultSorted(_ list: [SongProject]) -> [SongProject] {
        list.sorted { left, right in
            if left.song.artist == right.song.artist {
                return left.song.title.localizedStandardCompare(right.song.title) == .orderedAscending
            }
            return left.song.artist.localizedStandardCompare(right.song.artist) == .orderedAscending
        }
    }

    /// 套用使用者存下來的曲序；沒存過或曲目已不存在就照預設排序。
    /// bundle 新增、但沒出現在存檔曲序裡的曲目，接在後面（維持預設排序）。
    private func applySavedOrder(to list: [SongProject]) -> [SongProject] {
        guard let savedOrder = defaults.array(forKey: Self.orderDefaultsKey) as? [String],
              !savedOrder.isEmpty else {
            return list
        }
        let rank = Dictionary(savedOrder.enumerated().map { ($0.element, $0.offset) }) { first, _ in first }
        // 存檔裡有的照存檔順序排前面，沒有的（bundle 新增曲目）接在後面，兩邊各自穩定。
        return list.enumerated().sorted { left, right in
            let leftRank = rank[left.element.id] ?? Int.max
            let rightRank = rank[right.element.id] ?? Int.max
            if leftRank == rightRank { return left.offset < right.offset }
            return leftRank < rightRank
        }.map(\.element)
    }

    private func persistOrder() {
        defaults.set(projects.map(\.id), forKey: Self.orderDefaultsKey)
        // 馬上寫出同步檔 —— 只靠進背景時匯出的話，改完直接拔線就漏掉了。
        DeviceSync.markChanged("songOrder.v1", defaults: defaults)
    }
}
