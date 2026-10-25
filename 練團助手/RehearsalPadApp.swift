import SwiftUI

@main
struct RehearsalPadApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 一定要在 store 建立之前 —— SongLibrary 一初始化就會讀曲序。
        DeviceSync.importInbox()
        DeviceSync.bootstrapIfNeeded()
    }

    @StateObject private var library = SongLibrary()
    @StateObject private var sectionNotes = SectionNoteStore()
    @StateObject private var patchOverrides = NordPatchOverrideStore()
    @StateObject private var chordOverrides = ChordOverrideStore()
    @StateObject private var boundaries = SectionBoundaryStore()
    @StateObject private var userSections = UserSectionStore()
    @StateObject private var sectionPatches = SectionPatchStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(sectionNotes)
                .environmentObject(patchOverrides)
                .environmentObject(chordOverrides)
                .environmentObject(boundaries)
                .environmentObject(userSections)
                .environmentObject(sectionPatches)
                .onChange(of: scenePhase) { _, phase in
                    // 進背景時把狀態寫出去，Mac 下次插線才讀得到最新的排序。
                    if phase != .active { DeviceSync.exportState() }
                }
        }
    }
}
