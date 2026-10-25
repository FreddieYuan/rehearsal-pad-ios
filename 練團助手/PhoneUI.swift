import SwiftUI

// iPhone 版。跟 iPad 版是同一個 App、同一份資料，只是介面重心不同：
// iPad 是譜架上的譜，iPhone 是路上戴耳機聽分軌。
// 所以這裡把分軌台放在第一眼，譜退成次要的一個頁面。

struct PhoneRootView: View {
    @EnvironmentObject private var library: SongLibrary
    @ObservedObject var stems: StemPlayer
    @ObservedObject var audio: AudioPlayer
    @State private var query = ""
    // 用明確的 editMode 狀態，不靠 EditButton 自己推斷 ——
    // 在 NavigationSplitView 的側欄裡 EditButton 不會進入編輯模式（iPad 版踩過）。
    @State private var editMode: EditMode = .inactive

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var filtered: [SongProject] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return library.projects }
        return library.projects.filter {
            $0.song.title.lowercased().contains(q) || $0.song.artist.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { project in
                    NavigationLink {
                        PhonePlayerView(project: project, stems: stems, audio: audio)
                    } label: {
                        row(project)
                    }
                }
                .onMove(perform: move)
            }
            .listStyle(.plain)
            .environment(\.editMode, $editMode)
            .navigationTitle("拼盤")
            .searchable(text: $query, prompt: "搜尋曲名或歌手")
            .toolbar { sortToolbar }
            .onChange(of: query) { _, _ in
                // 一開始搜尋就退出排序模式，免得停在一個不能拖的編輯狀態。
                if isSearching, editMode.isEditing { editMode = .inactive }
            }
        }
    }

    /// 搜尋中看到的是過濾後的清單，拖曳的索引對不回完整曲序，
    /// 搬過去會落在錯的位置，所以直接不動作（排序按鈕那時也是停用的）。
    private func move(from source: IndexSet, to destination: Int) {
        guard !isSearching else { return }
        library.moveProjects(from: source, to: destination)
    }

    @ToolbarContentBuilder
    private var sortToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation {
                    editMode = editMode.isEditing ? .inactive : .active
                }
            } label: {
                Label(
                    editMode.isEditing ? "完成" : "排序",
                    systemImage: editMode.isEditing ? "checkmark" : "arrow.up.arrow.down"
                )
            }
            .disabled(isSearching)
        }
    }

    private func row(_ project: SongProject) -> some View {
        HStack(spacing: 10) {
            ArtworkThumbnail(url: library.artworkURL(for: project), size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.song.title)
                    .font(.headline)
                if !project.song.artist.isEmpty {
                    Text(project.song.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            // 沒有分軌的歌先標出來，免得點進去才發現只有單軌。
            if library.stemTracks(for: project).isEmpty {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct PhonePlayerView: View {
    let project: SongProject
    @ObservedObject var stems: StemPlayer
    @ObservedObject var audio: AudioPlayer
    @EnvironmentObject private var library: SongLibrary

    private var tracks: [StemPlayer.Track] { library.stemTracks(for: project) }
    private var hasStems: Bool { !tracks.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if hasStems {
                    transport
                    faders
                } else {
                    noStems
                }
                NavigationLink {
                    PhoneSheetView(project: project)
                } label: {
                    Label("看譜", systemImage: "doc.plaintext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(18)
        }
        .navigationTitle(project.song.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if hasStems {
                if stems.loadedProjectID != project.id {
                    audio.stop()
                    stems.load(
                        tracks: tracks,
                        projectID: project.id,
                        title: project.song.title,
                        artist: project.song.artist
                    )
                }
            } else {
                stems.unload()
                audio.load(url: library.audioURL(for: project))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ArtworkThumbnail(url: library.artworkURL(for: project), size: 80)
            VStack(alignment: .leading, spacing: 6) {
                if !project.song.artist.isEmpty {
                    Text(project.song.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Text(project.analysis.key)
                        .font(.system(size: 22, weight: .black))
                    if let bpm = project.analysis.bpm {
                        Text("♩= \(String(format: "%.0f", bpm))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var transport: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                Button {
                    stems.restart()
                } label: {
                    Image(systemName: "backward.end.fill").font(.title3)
                }
                Button {
                    stems.toggle()
                } label: {
                    Image(systemName: stems.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                }
                Button {
                    stems.seek(to: max(stems.elapsed - 10, 0))
                } label: {
                    Image(systemName: "gobackward.10").font(.title3)
                }
            }
            HStack(spacing: 8) {
                Text(timecode(stems.elapsed))
                    .font(.caption.monospacedDigit())
                Slider(
                    value: Binding(get: { stems.elapsed }, set: { stems.seek(to: $0) }),
                    in: 0...max(stems.duration, 0.1)
                )
                Text(timecode(stems.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var faders: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reference = stems.tracks.first(where: { $0.isKeyboardReference }) {
                Button {
                    for id in Array(stems.soloed) where id != reference.id {
                        stems.toggleSolo(id)
                    }
                    if !stems.soloed.contains(reference.id) {
                        stems.toggleSolo(reference.id)
                    }
                } label: {
                    Label(
                        reference.id == "piano" ? "只聽鍵盤" : "只聽鍵盤（在「\(reference.name)」軌）",
                        systemImage: "pianokeys.inverse"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            ForEach(stems.tracks) { track in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(track.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(stems.isAudible(track.id) ? Color.primary : Color.secondary)
                        if track.isKeyboardReference {
                            Image(systemName: "pianokeys")
                                .font(.caption2)
                                .foregroundStyle(Color.sheetChord)
                        }
                        Spacer()
                        Button("M") { stems.toggleMute(track.id) }
                            .font(.caption.weight(.black))
                            .buttonStyle(.bordered)
                            .tint(stems.muted.contains(track.id) ? .red : .secondary)
                        Button("S") { stems.toggleSolo(track.id) }
                            .font(.caption.weight(.black))
                            .buttonStyle(.bordered)
                            .tint(stems.soloed.contains(track.id) ? .yellow : .secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { stems.volumes[track.id] ?? 1 },
                            set: { stems.setVolume($0, for: track.id) }
                        ),
                        in: 0...1.5
                    )
                    .disabled(!stems.isAudible(track.id))
                }
            }

            if !stems.soloed.isEmpty {
                Button {
                    for id in Array(stems.soloed) { stems.toggleSolo(id) }
                } label: {
                    Label("取消所有 Solo", systemImage: "xmark.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var noStems: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("這首還沒有分軌，只能整首試聽。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                audio.toggle()
            } label: {
                Label(audio.isPlaying ? "暫停" : "播放",
                      systemImage: audio.isPlaying ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(library.audioURL(for: project) == nil)
        }
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// iPhone 上的譜：同一份 LeadSheetBuilder，字級縮小一點，不放筆記欄。
struct PhoneSheetView: View {
    let project: SongProject
    @EnvironmentObject private var library: SongLibrary
    @EnvironmentObject private var patchOverrides: NordPatchOverrideStore
    @EnvironmentObject private var chordOverrides: ChordOverrideStore
    @EnvironmentObject private var boundaries: SectionBoundaryStore
    @EnvironmentObject private var userSections: UserSectionStore
    @EnvironmentObject private var sectionPatches: SectionPatchStore
    @AppStorage("phoneSheetScale.v1") private var scale = 0.75

    private var sections: [SheetSection] {
        // 跟 iPad 同一條路：手改的和弦要在建譜之前套進去。
        var corrected = project
        corrected.chords = chordOverrides.apply(to: project.chords, projectID: project.id)
        return LeadSheetBuilder.build(
            project: corrected,
            catalog: library.nordCatalog,
            overrides: patchOverrides,
            boundaries: boundaries,
            userSections: userSections,
            sectionPatches: sectionPatches
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(sections) { section in
                    SectionBlock(
                        section: section,
                        transposeSteps: 0,
                        projectID: project.id,
                        isEditingNotes: false,
                        metrics: SheetMetrics(scale: scale)
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(project.song.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    scale = max(0.5, (scale - 0.1).rounded(toPlaces: 1))
                } label: { Image(systemName: "textformat.size.smaller") }
                Button {
                    scale = min(1.6, (scale + 0.1).rounded(toPlaces: 1))
                } label: { Image(systemName: "textformat.size.larger") }
            }
        }
    }
}
