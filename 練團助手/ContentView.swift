import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var library: SongLibrary
    @EnvironmentObject private var notes: SectionNoteStore
    @EnvironmentObject private var chordOverrides: ChordOverrideStore
    @EnvironmentObject private var sectionBoundaries: SectionBoundaryStore
    @EnvironmentObject private var userSections: UserSectionStore
    @EnvironmentObject private var sectionPatches: SectionPatchStore
    @EnvironmentObject private var patchOverrides: NordPatchOverrideStore
    @StateObject private var audio = AudioPlayer()
    @StateObject private var stems = StemPlayer()
    @State private var transposeSteps = 0
    // 預設side bar是開的（要先選歌）；演出模式才收起來。
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    // 兩個都預設開著，不用每次點開。@AppStorage 讓它跨換歌、跨重開都記得，
    // 不然關掉之後換一首又跳回預設。
    @AppStorage("editSectionNotes.v1") private var isEditingNotes = true
    @AppStorage("showChordPalette.v1") private var showChordPalette = true
    @AppStorage("sheetTextScale.v1") private var sheetScale = 1.0
    @AppStorage("showStemMixer.v1") private var showStemMixer = false

    // iPhone 跟 iPad 是同一個 App、同一份資料，但用途不同：
    // iPad 立在譜架上看譜，iPhone 在路上戴耳機聽分軌。介面依尺寸分流。
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var sidebarEditMode: EditMode = .inactive

    private var isPerforming: Bool { columnVisibility == .detailOnly }

    var body: some View {
        if sizeClass == .compact {
            PhoneRootView(stems: stems, audio: audio)
        } else {
            padBody
        }
    }

    private var padBody: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $library.selectedProjectID) {
                // 這裡刻意「不」用 Button 包住整列。
                // 包了之後 Button 會吃掉 .onMove 的拖曳手勢 —— Edit 模式下連拖曳把手
                // 都不會出現，曲序根本拖不動。選取交給 List 的 selection binding
                // 配 .tag()，那本來就是它的工作。
                ForEach(library.projects) { project in
                    HStack(spacing: 10) {
                        ArtworkThumbnail(url: library.artworkURL(for: project), size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(project.song.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if !project.song.artist.isEmpty {
                                Text(project.song.artist)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tag(project.id)
                }
                .onMove(perform: library.moveProjects)
            }
            .environment(\.editMode, $sidebarEditMode)
            .navigationTitle("曲目")
            .toolbar {
                // EditButton 在 NavigationSplitView 側欄裡不會真的進入編輯模式，
                // 所以自己管 editMode。
                Button {
                    withAnimation {
                        sidebarEditMode = sidebarEditMode.isEditing ? .inactive : .active
                    }
                } label: {
                    Label(
                        sidebarEditMode.isEditing ? "完成" : "排序",
                        systemImage: sidebarEditMode.isEditing ? "checkmark" : "arrow.up.arrow.down"
                    )
                }
            }
        } detail: {
            if let project = library.selectedProject {
                SongDetailView(
                    project: project,
                    audio: audio,
                    transposeSteps: $transposeSteps,
                    audioURL: library.audioURL(for: project),
                    artworkURL: library.artworkURL(for: project),
                    stems: stems,
                    stemTracks: library.stemTracks(for: project),
                    catalog: library.nordCatalog,
                    overrides: patchOverrides,
                    chordOverrides: chordOverrides,
                    boundaries: sectionBoundaries,
                    userSections: userSections,
                    sectionPatches: sectionPatches,
                    isPerforming: isPerforming,
                    isEditingNotes: $isEditingNotes,
                    showChordPalette: $showChordPalette,
                    sheetScale: $sheetScale,
                    showStemMixer: $showStemMixer,
                    onTogglePerforming: {
                        withAnimation {
                            columnVisibility = isPerforming ? .all : .detailOnly
                        }
                    }
                )
                // 改過音色或和弦就整份重算。兩者都是偶發動作，重算不痛。
                .id("\(project.id)-\(patchOverrides.version)-\(chordOverrides.version)-\(sectionBoundaries.version)-\(notes.moveVersion)-\(userSections.version)-\(sectionPatches.version)")
            } else {
                ContentUnavailableView("沒有曲目", systemImage: "music.note.list")
            }
        }
        .onChange(of: library.selectedProjectID) {
            transposeSteps = 0
            audio.load(url: library.selectedProject.flatMap(library.audioURL(for:)))
            if let project = library.selectedProject {
                stems.load(
                    tracks: library.stemTracks(for: project),
                    projectID: project.id,
                    title: project.song.title,
                    artist: project.song.artist
                )
            } else {
                stems.unload()
            }
        }
    }
}

struct SongDetailView: View {
    let project: SongProject
    @ObservedObject var audio: AudioPlayer
    @Binding var transposeSteps: Int
    let audioURL: URL?
    let artworkURL: URL?
    @ObservedObject var stems: StemPlayer
    let stemTracks: [StemPlayer.Track]
    let isPerforming: Bool
    @Binding var isEditingNotes: Bool
    @Binding var showChordPalette: Bool
    @Binding var sheetScale: Double
    @Binding var showStemMixer: Bool
    let onTogglePerforming: () -> Void
    @EnvironmentObject private var notes: SectionNoteStore
    @EnvironmentObject private var patchOverrides: NordPatchOverrideStore
    private let catalog: NordCatalog
    /// 音色格：每首歌都有，原始資料沒有的就是空格等你填。
    private let patchSlots: [(original: NordPatch?, resolved: NordPatch?, isCustom: Bool)]

    /// 譜的結構只跟曲目有關，移調不影響，所以只算一次。
    private let sections: [SheetSection]
    private let chordSymbols: [String]
    private let seedSections: [UserSectionStore.Entry]
    @EnvironmentObject private var sectionPatchesForCommon: SectionPatchStore

    init(
        project: SongProject,
        audio: AudioPlayer,
        transposeSteps: Binding<Int>,
        audioURL: URL?,
        artworkURL: URL?,
        stems: StemPlayer,
        stemTracks: [StemPlayer.Track],
        catalog: NordCatalog,
        overrides: NordPatchOverrideStore,
        chordOverrides: ChordOverrideStore,
        boundaries: SectionBoundaryStore,
        userSections: UserSectionStore,
        sectionPatches: SectionPatchStore,
        isPerforming: Bool,
        isEditingNotes: Binding<Bool>,
        showChordPalette: Binding<Bool>,
        sheetScale: Binding<Double>,
        showStemMixer: Binding<Bool>,
        onTogglePerforming: @escaping () -> Void
    ) {
        self.project = project
        self.audio = audio
        self._transposeSteps = transposeSteps
        self.audioURL = audioURL
        self.artworkURL = artworkURL
        self.stems = stems
        self.stemTracks = stemTracks
        self.isPerforming = isPerforming
        self._isEditingNotes = isEditingNotes
        self._showChordPalette = showChordPalette
        self._sheetScale = sheetScale
        self._showStemMixer = showStemMixer
        self.onTogglePerforming = onTogglePerforming
        self.catalog = catalog
        // 手改過的和弦要在建譜「之前」套進去 —— 段落重複判定和和弦一覽
        // 都是看和弦內容決定的，只在畫面上換字會讓這兩者跟譜對不起來。
        var corrected = project
        corrected.chords = chordOverrides.apply(to: project.chords, projectID: project.id)
        self.sections = LeadSheetBuilder.build(project: corrected, catalog: catalog,
                                               overrides: overrides, boundaries: boundaries,
                                               userSections: userSections,
                                               sectionPatches: sectionPatches)
        // 第一次自訂段落時的底稿：這首歌目前實際用的切點（含重複段的每一次）。
        // 用畫面上合併後的 sections 當底稿會漏掉重複的那幾次。
        self.seedSections = LeadSheetBuilder.sectionRanges(
            corrected, lyrics: LeadSheetBuilder.cleanedLyrics(corrected),
            boundaries: boundaries, userSections: userSections
        ).map { UserSectionStore.Entry(time: $0.anchor, label: $0.label) }
        self.chordSymbols = LeadSheetBuilder.distinctChords(corrected)
        self.patchSlots = LeadSheetBuilder.patchSlots(project, catalog: catalog, overrides: overrides)
    }

    var body: some View {
        GeometryReader { geometry in
            // 量整頁寬度，決定歌詞要不要排成兩欄。
            let contentWidth = geometry.size.width - 56
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    keyRow
                    patchStrip
                    controls
                    if hasStems && showStemMixer && !isPerforming {
                        StemMixerView(player: stems)
                    }
                    if showChordPalette && !chordSymbols.isEmpty {
                        ChordPalette(symbols: chordSymbols, transposeSteps: transposeSteps)
                    }
                    sheet(width: contentWidth)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // 曲名照樂譜習慣印在譜頭，導覽列就留白，不重複第二次。
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            audio.load(url: audioURL)
            if stems.loadedProjectID != project.id {
                stems.load(
                    tracks: stemTracks,
                    projectID: project.id,
                    title: project.song.title,
                    artist: project.song.artist
                )
            }
        }
    }

    /// 譜頭照樂譜的規矩：曲名、演出者在最上面，底下才是演奏資訊。
    /// Key 是演奏資訊列的第一項而且是列裡最大的字 —— 台上第一個要確認的是它，
    /// 但它不該大過曲名。
    private var keyRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.song.title)
                        .font(.system(size: 30, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 8) {
                        if !project.song.artist.isEmpty {
                            Text(project.song.artist)
                        }
                        if !sourceLabel.isEmpty {
                            Text("·")
                            Text(sourceLabel)
                        }
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let url = artworkURL {
                    ArtworkThumbnail(url: url, size: 72)
                }
            }

            HStack(alignment: .center, spacing: 12) {
                Text("Key")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(MusicTransposer.transposeKey(project.analysis.key, semitones: transposeSteps))
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(transposeSteps == 0 ? .primary : Color.sheetSection)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    transposeButton(systemName: "minus", step: -1)
                    transposeButton(systemName: "plus", step: 1)
                }

                if transposeSteps != 0 {
                    Text("\(transposeSteps > 0 ? "+" : "")\(transposeSteps)　原 \(project.analysis.key)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.sheetSection)
                    Button("歸零") { transposeSteps = 0 }
                        .font(.caption.weight(.bold))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }

                if let bpm = project.analysis.bpm {
                    Divider().frame(height: 22)
                    Text("♩= \(String(format: "%.0f", bpm))")
                        .font(.system(size: 16, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func transposeButton(systemName: String, step: Int) -> some View {
        Button {
            transposeSteps += step
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 26, height: 20)
        }
        .buttonStyle(.bordered)
    }

    /// 這首歌的音色格。每首歌都有固定幾格，原始資料沒有推薦的就留空給你自己填。
    /// 整個曲庫用過的音色，次數多的排前面。
    private var commonPatches: [String] {
        var counts = sectionPatchesForCommon.usedCounts
        for (raw, n) in patchOverrides.usedCounts { counts[raw, default: 0] += n }
        return counts
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .map { $0.key }
    }

    private var patchStrip: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            Text("音色")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.trailing, 2)

            ForEach(Array(patchSlots.enumerated()), id: \.offset) { index, slot in
                NordPatchPicker(
                    catalog: catalog,
                    current: slot.resolved,
                    isOverridden: slot.isCustom,
                    originalName: slot.isCustom ? slot.original?.name : nil,
                    onSelect: { raw in
                        patchOverrides.setSlotPatch(raw, projectID: project.id, index: index)
                    },
                    onReset: slot.isCustom ? {
                        patchOverrides.setSlotPatch(nil, projectID: project.id, index: index)
                    } : nil,
                    common: commonPatches
                )
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        // 台上只留下真正會用到的：音色（在上面那排）跟和弦表。
        // 播放、分軌、編輯、字級都是排練時才動的東西，留在畫面上只會分心，
        // 而且誤觸「編輯譜面」會讓整份譜長出一堆按鈕。
        if isPerforming { performanceControls } else { rehearsalControls }
    }

    private var performanceControls: some View {
        HStack(spacing: 10) {
            Button {
                showChordPalette.toggle()
            } label: {
                Label("和弦表", systemImage: showChordPalette ? "pianokeys.inverse" : "pianokeys")
            }
            .buttonStyle(.bordered)
            .disabled(chordSymbols.isEmpty)

            Spacer(minLength: 0)

            // 沒有這顆就出不去了，不能省。
            Button {
                onTogglePerforming()
            } label: {
                Label("顯示曲目", systemImage: "sidebar.left")
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var rehearsalControls: some View {
        HStack(spacing: 10) {
            Button {
                if hasStems { stems.toggle() } else { audio.toggle() }
            } label: {
                let playing = hasStems ? stems.isPlaying : audio.isPlaying
                Label(playing ? "暫停" : "播放", systemImage: playing ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasStems && audioURL == nil)

            if hasStems {
                Button {
                    showStemMixer.toggle()
                } label: {
                    Label("分軌", systemImage: "slider.vertical.3")
                }
                .buttonStyle(.bordered)
                .tint(showStemMixer ? Color.sheetChord : Color.accentColor)
            }

            Button {
                showChordPalette.toggle()
            } label: {
                Label("和弦表", systemImage: showChordPalette ? "pianokeys.inverse" : "pianokeys")
            }
            .buttonStyle(.bordered)
            .disabled(chordSymbols.isEmpty)

            Button {
                isEditingNotes.toggle()
            } label: {
                Label(isEditingNotes ? "編輯完成" : "編輯譜面", systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .tint(isEditingNotes ? Color.sheetSection : Color.accentColor)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Button {
                    sheetScale = max(0.8, (sheetScale - 0.1).rounded(toPlaces: 1))
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .buttonStyle(.bordered)
                .disabled(sheetScale <= 0.8)

                Text("\(Int(sheetScale * 100))%")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 42)

                Button {
                    sheetScale = min(2.0, (sheetScale + 0.1).rounded(toPlaces: 1))
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .buttonStyle(.bordered)
                .disabled(sheetScale >= 2.0)
            }

            Button {
                onTogglePerforming()
            } label: {
                Label(
                    isPerforming ? "顯示曲目" : "演出模式",
                    systemImage: isPerforming ? "sidebar.left" : "rectangle.inset.filled"
                )
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    /// 這首歌有沒有打包分軌；沒有就退回單軌試聽。
    private var hasStems: Bool { !stemTracks.isEmpty }

    private func sheet(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if sections.isEmpty {
                Text("這首還沒有可用的譜面資料。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    SectionBlock(
                        section: section,
                        transposeSteps: transposeSteps,
                        projectID: project.id,
                        previousSectionID: index > 0 ? sections[index - 1].id : nil,
                        nextSectionID: index + 1 < sections.count ? sections[index + 1].id : nil,
                        seed: seedSections,
                        // 演出時一律關掉編輯控制項：誤觸會讓整份譜長出按鈕。
                        // 已經寫好的筆記仍然照常顯示（唯讀）。
                        isEditingNotes: isEditingNotes && !isPerforming,
                        metrics: SheetMetrics(scale: sheetScale),
                        contentWidth: width
                    )
                }
            }
        }
    }

    private var sourceLabel: String {
        guard case .string(let value)? = project.sources["chord_status"] else { return "" }
        if value.contains("user") || value.contains("official") {
            return "可信譜"
        }
        if value.contains("draft") {
            return "草稿"
        }
        return ""
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

/// 譜面字級。基準值是「iPad 立在譜架上、人站在鍵盤後面」的距離抓的，
/// scale 讓你在現場自己再調，不用改程式。
struct SheetMetrics {
    var scale: CGFloat = 1

    var lyric: CGFloat { 22 * scale }
    var inlineChord: CGFloat { 26 * scale }
    var chordRow: CGFloat { 28 * scale }
    var sectionLabel: CGFloat { 24 * scale }
    /// 逐字對位時預留給和弦的高度，要跟著和弦字級走。
    var chordSlot: CGFloat { 34 * scale }
    var note: CGFloat { 18 * scale }
}

// MARK: - Section

struct SectionBlock: View {
    let section: SheetSection
    let transposeSteps: Int
    let projectID: String
    /// 上一段／下一段的 id，給「把筆記往上／往下搬」用。nil＝已經到頭。
    var previousSectionID: String? = nil
    var nextSectionID: String? = nil
    /// 第一次自訂段落時的底稿（這首歌目前的切點）。
    var seed: [UserSectionStore.Entry] = []
    let isEditingNotes: Bool
    let metrics: SheetMetrics
    /// 可用寬度。夠寬才把歌詞排成兩欄 —— 字級放大時一欄就塞不下了。
    var contentWidth: CGFloat = 0

    @EnvironmentObject private var notes: SectionNoteStore
    @EnvironmentObject private var boundaries: SectionBoundaryStore
    @EnvironmentObject private var userSections: UserSectionStore
    @EnvironmentObject private var sectionPatches: SectionPatchStore
    @EnvironmentObject private var patchOverridesForCommon: NordPatchOverrideStore
    @EnvironmentObject private var library: SongLibrary
    /// 草稿留在畫面本地，打字時不會驚動整棵 view tree。
    @State private var draft = ""
    /// 這一次拖曳已經套用了幾行，放手歸零。
    @State private var dragSteps = 0

    /// 整個曲庫用過的音色，次數多的排前面。
    private var commonPatches: [String] {
        var counts = sectionPatches.usedCounts
        for (raw, n) in patchOverridesForCommon.usedCounts { counts[raw, default: 0] += n }
        return counts
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .map { $0.key }
    }

    private var showsNote: Bool {
        isEditingNotes || !draft.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 段落名、音色、重點筆記擠在同一行 —— 三樣都是「這段怎麼彈」的資訊，
            // 分三行讀要掃三次，而且白白吃掉譜面的垂直空間。
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                header
                patchControl
                if showsNote {
                    noteView.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            lines
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.sheetSection)
                .frame(width: 4)
        }
        .onAppear {
            draft = notes.note(projectID: projectID, sectionID: section.id)
        }
        .onChange(of: draft) { _, newValue in
            notes.setNote(newValue, projectID: projectID, sectionID: section.id)
        }
    }

    /// 一欄至少要這麼寬才塞得下「和弦壓在歌詞上」。跟著字級走 ——
    /// 字放到 200% 還硬排兩欄，只會每行都折行，比單欄更難讀。
    private var minColumnWidth: CGFloat { max(340, metrics.lyric * 17) }

    private var usesTwoColumns: Bool {
        contentWidth >= minColumnWidth * 2 + 24
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 12) {
            if usesTwoColumns, section.takes.count > 1 {
                // 一段有兩次以上（和弦不同）：第一次放左邊、第二次放右邊。
                ForEach(Array(stride(from: 0, to: section.takes.count, by: 2)), id: \.self) { index in
                    HStack(alignment: .top, spacing: 24) {
                        takeView(section.takes[index])
                        if index + 1 < section.takes.count {
                            takeView(section.takes[index + 1])
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            } else if usesTwoColumns, let take = section.takes.first,
                      take.lines.count >= 6 {
                // 只有一次、但行數夠多：從中間對半拆成左右兩欄。
                let half = (take.lines.count + 1) / 2
                HStack(alignment: .top, spacing: 24) {
                    lyricColumn(Array(take.lines[..<half]))
                    lyricColumn(Array(take.lines[half...]))
                }
            } else {
                ForEach(section.takes) { take in takeView(take) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func takeView(_ take: SheetTake) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if take.isVariant {
                Text("第 \(take.occurrenceNumber) 次（和弦不同）")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            // 有歌詞時和弦已經標在歌詞上，段落總覽只會整組重複一次；
            // 只有純演奏段落（前奏／間奏／solo）才需要這排和弦。
            if take.lines.isEmpty && !take.chordRow.isEmpty {
                ChordRow(chords: take.chordRow, transposeSteps: transposeSteps,
                         projectID: projectID, size: metrics.chordRow)
            }
            ForEach(take.lines) { line in
                LyricLineView(line: line, transposeSteps: transposeSteps,
                              projectID: projectID, metrics: metrics,
                              isEditing: isEditingNotes, seed: seed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lyricColumn(_ lines: [SheetLine]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(lines) { line in
                LyricLineView(line: line, transposeSteps: transposeSteps,
                              projectID: projectID, metrics: metrics,
                              isEditing: isEditingNotes, seed: seed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var patchControl: some View {
        if isEditingNotes {
            NordPatchPicker(
                catalog: library.nordCatalog,
                current: section.patch,
                isOverridden: sectionPatches.raw(projectID: projectID, sectionID: section.id) != nil,
                originalName: nil,
                onSelect: { raw in
                    sectionPatches.setRaw(raw, projectID: projectID, sectionID: section.id)
                },
                onReset: sectionPatches.raw(projectID: projectID, sectionID: section.id) == nil
                    ? nil
                    : { sectionPatches.setRaw(nil, projectID: projectID, sectionID: section.id) },
                common: commonPatches
            )
        } else if let patch = section.patch {
            NordPatchBadge(patch: patch, isChange: section.patchIsChange)
        }
    }

    @ViewBuilder
    private var noteView: some View {
        if isEditingNotes {
            VStack(alignment: .leading, spacing: 6) {
                noteMover
                noteEditor
            }
        } else {
            Text(draft)
                .font(.system(size: metrics.note, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.noteBackground, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// 把這一段的筆記整則搬到上／下一段。
    /// 用途是「提前提醒」—— 換音色或換彈法的提示要在你還在看上一段時就出現。
    private var noteMover: some View {
        HStack(spacing: 6) {
            Button {
                if let previousSectionID {
                    notes.move(projectID: projectID, from: section.id, to: previousSectionID)
                }
            } label: {
                Label("往上一段", systemImage: "arrow.up")
            }
            .disabled(previousSectionID == nil || draft.isEmpty)
            Button {
                if let nextSectionID {
                    notes.move(projectID: projectID, from: section.id, to: nextSectionID)
                }
            } label: {
                Label("往下一段", systemImage: "arrow.down")
            }
            .disabled(nextSectionID == nil || draft.isEmpty)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .tint(.secondary)
    }

    @ViewBuilder
    private var noteEditor: some View {
        Group {
            // 這裡不能用 TextField(axis: .vertical)：接上實體鍵盤時 Return 會被當成
            // 送出（收鍵盤）而不是換行，打英文就變成「按 Enter 沒反應」。
            // 打中文時 Return 先被注音／拼音拿去選字，所以反而看起來正常。
            // TextEditor 的 Return 永遠是換行，實體鍵盤和螢幕鍵盤都一樣。
            ZStack(alignment: .topLeading) {
                // TextEditor 自己不會隨內容長高，只會內捲。用同字級的隱形文字撐高度。
                // 這裡的 8/5 是 UITextView 預設的 textContainerInset 和
                // lineFragmentPadding，對齊了游標才不會跟假文字錯開。
                Text(draft.isEmpty ? " " : draft)
                    .font(.system(size: metrics.note))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(0)
                if draft.isEmpty {
                    Text("這段的重點…")
                        .font(.system(size: metrics.note))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .font(.system(size: metrics.note))
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
            }
            .padding(10)
            .background(Color.noteBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.sheetSection.opacity(0.45), lineWidth: 1.5)
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(section.repeatCount > 1
                 ? "[\(SectionLabel.display(section.label))] ×\(section.repeatCount)"
                 : "[\(SectionLabel.display(section.label))]")
                .font(.system(size: metrics.sectionLabel, weight: .black))
                .foregroundStyle(Color.sheetSection)
                // 編輯模式下整個標題可以直接上下拖，拖一行的距離就移一行。
                .gesture(isEditingNotes ? boundaryDrag : nil)
            if isEditingNotes { sectionMenu; boundaryStepper }
        }
    }

    /// 改這一段的名字，或把自己標的切點拿掉。
    private var sectionMenu: some View {
        Menu {
            Section("改名") {
                ForEach(UserSectionStore.labels, id: \.self) { label in
                    Button(SectionLabel.display(label)) {
                        userSections.rename(time: section.anchor, to: label, projectID: projectID)
                    }
                }
            }
            if userSections.hasCustom(projectID: projectID) {
                Divider()
                Button("刪除這個切點", role: .destructive) {
                    userSections.remove(time: section.anchor, projectID: projectID)
                }
                Button("全部回到自動偵測", role: .destructive) {
                    userSections.reset(projectID: projectID)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .tint(Color.sheetSection)
    }

    // MARK: - 段落切點微調

    /// 拖一行歌詞的高度＝移一行。用實際字級算，字放大時手感才一致。
    private var lineStep: CGFloat { max(metrics.lyric * 1.9, 28) }

    private var boundaryOffset: Int {
        boundaries.offset(projectID: projectID, anchor: section.anchor)
    }

    private var boundaryDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // 邊拖邊套用：把「已經拖過的行數」跟「這次手勢開始時的值」比，
                // 差多少就補多少，這樣來回拖也不會累加錯。
                let steps = Int((value.translation.height / lineStep).rounded())
                if steps != dragSteps {
                    boundaries.nudge(by: steps - dragSteps,
                                     projectID: projectID, anchor: section.anchor)
                    dragSteps = steps
                }
            }
            .onEnded { _ in dragSteps = 0 }
    }

    private var boundaryStepper: some View {
        HStack(spacing: 4) {
            Button {
                boundaries.nudge(by: -1, projectID: projectID, anchor: section.anchor)
            } label: {
                Image(systemName: "chevron.up").font(.caption.weight(.bold))
            }
            Button {
                boundaries.nudge(by: 1, projectID: projectID, anchor: section.anchor)
            } label: {
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            if boundaryOffset != 0 {
                Text(boundaryOffset > 0 ? "+\(boundaryOffset) 行" : "\(boundaryOffset) 行")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.sheetSection)
                Button("歸位") {
                    boundaries.setOffset(0, projectID: projectID, anchor: section.anchor)
                }
                .font(.caption2)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .tint(Color.sheetSection)
    }
}

// MARK: - Lyrics + chords

struct ChordRow: View {
    let chords: [SheetChord]
    let transposeSteps: Int
    let projectID: String
    var size: CGFloat = 28

    var body: some View {
        FlowLayout(spacing: size * 0.75, rowSpacing: size * 0.28) {
            ForEach(chords) { chord in
                ChordText(
                    chord: chord,
                    transposeSteps: transposeSteps,
                    projectID: projectID,
                    size: size
                )
            }
        }
    }
}

struct LyricLineView: View {
    let line: SheetLine
    let transposeSteps: Int
    let projectID: String
    let metrics: SheetMetrics
    var isEditing = false
    /// 第一次自訂段落時拿來當底稿的現有切點。
    var seed: [UserSectionStore.Entry] = []

    @EnvironmentObject private var userSections: UserSectionStore

    /// 每段都預留一樣高的和弦位，歌詞才會對齊在同一條線上。
    private var chordSlotHeight: CGFloat { metrics.chordSlot }

    var body: some View {
        if isEditing {
            HStack(alignment: .top, spacing: 8) {
                splitButton
                content
            }
        } else {
            content
        }
    }

    /// 在這一行開一個新段落。自動偵測常常整段切錯（切穿副歌），
    /// 不是移一行能救的，所以要能直接指定「這裡是 Chorus」。
    private var splitButton: some View {
        Menu {
            ForEach(UserSectionStore.labels, id: \.self) { label in
                Button(SectionLabel.display(label)) {
                    userSections.add(time: line.start, label: label,
                                     projectID: projectID, seed: seed)
                }
            }
        } label: {
            Image(systemName: "text.insert").font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .tint(Color.sheetSection)
    }

    @ViewBuilder
    private var content: some View {
        switch line.layout {
        case .plain(let text):
            lyricText(text)
                .padding(.bottom, 6)
        case .stacked(let chords, let text):
            VStack(alignment: .leading, spacing: 2) {
                ChordRow(chords: chords, transposeSteps: transposeSteps, projectID: projectID, size: metrics.inlineChord)
                lyricText(text)
            }
            .padding(.bottom, 10)
        case .inline(let segments):
            FlowLayout(spacing: 0, rowSpacing: 6) {
                ForEach(segments) { segment in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: metrics.inlineChord * 0.42) {
                            ForEach(segment.chords) { chord in
                                ChordText(
                                    chord: chord,
                                    transposeSteps: transposeSteps,
                                    projectID: projectID,
                                    size: metrics.inlineChord
                                )
                            }
                        }
                        // 和弦比底下那截歌詞寬時，這個右內距會把整段撐開，
                        // 下一顆和弦才不會跟它黏在一起（Bm7E）。
                        .padding(.trailing, segment.chords.isEmpty ? 0 : metrics.inlineChord * 0.7)
                        .frame(height: chordSlotHeight, alignment: .bottomLeading)
                        lyricText(segment.text)
                    }
                }
            }
            .padding(.bottom, 10)
        }
    }

    private func lyricText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: metrics.lyric))
            .foregroundStyle(.primary)
    }
}

/// 譜面上的和弦。點下去跳出鍵盤提示圖，卡片上可以進一步改和弦。
struct ChordText: View {
    let chord: SheetChord
    let transposeSteps: Int
    let projectID: String
    let size: CGFloat

    @EnvironmentObject private var chordOverrides: ChordOverrideStore
    @State private var showHint = false
    @State private var showEditor = false
    /// 先收 popover 再開 sheet。兩個 presentation 同時在轉場時，
    /// sheet 會被吃掉不出現，所以等 popover 真的消失了再開。
    @State private var wantsEditor = false

    /// 畫面上看到的是移調後的樣子；存回去時要再轉回原調。
    private var displayed: String {
        MusicTransposer.transposeChord(chord.symbol, semitones: transposeSteps)
    }

    private var isCustom: Bool {
        chordOverrides.isCustom(projectID: projectID, time: chord.time)
    }

    var body: some View {
        Text(displayed)
            .font(.system(size: size, weight: .heavy))
            .foregroundStyle(Color.sheetChord)
            // 自己改過的和弦畫一條底線 —— 不加顏色，免得在譜上比原本的和弦還搶眼。
            .overlay(alignment: .bottom) {
                if isCustom {
                    Rectangle()
                        .fill(Color.sheetChord.opacity(0.55))
                        .frame(height: max(1.5, size * 0.07))
                        .offset(y: size * 0.12)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { showHint = true }
            .popover(isPresented: $showHint) {
                ChordHintCard(
                    symbol: displayed,
                    shape: ChordShape.parse(displayed),
                    isCustom: isCustom,
                    onEdit: { wantsEditor = true; showHint = false }
                )
                .presentationCompactAdaptation(.popover)
                .onDisappear {
                    guard wantsEditor else { return }
                    wantsEditor = false
                    showEditor = true
                }
            }
            .sheet(isPresented: $showEditor) {
                ChordEditorView(
                    displayed: displayed,
                    isCustom: isCustom,
                    onPick: { picked in
                        // picked 是使用者在移調後的畫面上挑的，存回去要轉回原調。
                        chordOverrides.setSymbol(
                            MusicTransposer.transposeChord(picked, semitones: -transposeSteps),
                            projectID: projectID, time: chord.time
                        )
                    },
                    onReset: {
                        chordOverrides.setSymbol(nil, projectID: projectID, time: chord.time)
                    }
                )
            }
    }
}

// MARK: - Artwork

struct ArtworkThumbnail: View {
    let url: URL?
    let size: CGFloat

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
        .task(id: url) {
            guard let url else { image = nil; return }
            image = await Task.detached(priority: .userInitiated) {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return UIImage(data: data)
            }.value
        }
    }
}

// MARK: - Colors

extension Color {
    /// web 版和弦藍 #2466a8，暗色下提亮。
    static let sheetChord = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.55, green: 0.75, blue: 0.98, alpha: 1)
            : UIColor(red: 0.141, green: 0.400, blue: 0.659, alpha: 1)
    })

    /// 段落筆記的底，淡到不搶譜面。
    static let noteBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.15, blue: 0.10, alpha: 1)
            : UIColor(red: 1.0, green: 0.96, blue: 0.90, alpha: 1)
    })

    /// web 版段落橘 #cf5b1f，暗色下提亮。
    static let sheetSection = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.62, blue: 0.38, alpha: 1)
            : UIColor(red: 0.812, green: 0.357, blue: 0.122, alpha: 1)
    })
}

// MARK: - Flow layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat? = nil

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for item in result.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (items: [(index: Int, origin: CGPoint)], size: CGSize) {
        let maxWidth = proposal.width ?? 760
        let verticalSpacing = rowSpacing ?? spacing
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        var items: [(Int, CGPoint)] = []

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            items.append((index, CGPoint(x: x, y: y)))
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (items, CGSize(width: min(usedWidth, maxWidth), height: y + rowHeight))
    }
}


// PhoneUI 也要用，所以不是 private。
extension Double {
    /// 連按加減不要累積出 1.2000000000000002 這種值。
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
