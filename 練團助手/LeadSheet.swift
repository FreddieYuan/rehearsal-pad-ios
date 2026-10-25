import Foundation

// 這一層是 web 版 exporters.py 的 Swift 移植：
// 段落合併（Verse ×4）、連續同和弦壓縮、和弦落在歌詞正上方、雜訊歌詞清掉。
// 目的是讓 iPad 的譜跟網頁版看起來是同一份譜。

// MARK: - Sheet model

/// 譜面上的一顆和弦。
///
/// 帶著 time 是為了「點下去可以改」—— 改和弦要寫回 ChordOverrideStore，
/// 而那邊是用時間當 key 的。只傳符號字串就找不回它是哪一顆。
struct SheetChord: Identifiable, Hashable {
    let time: Double
    /// 原始未移調的符號。畫面上顯示時才套移調。
    let symbol: String
    var id: Double { time }
}

struct SheetSegment: Identifiable {
    let id: Int
    /// 落在這一段開頭的和弦（原始未移調）。空的代表這段沒有和弦變化。
    let chords: [SheetChord]
    let text: String
}

struct SheetLine: Identifiable {
    enum Layout {
        /// 沒有和弦，只有歌詞。
        case plain(String)
        /// 和弦太密、句子太短，改成整排和弦壓在歌詞上面。
        case stacked(chords: [SheetChord], text: String)
        /// 和弦逐字落在歌詞正上方。
        case inline([SheetSegment])
    }

    let id: String
    /// 這一行歌詞的開始時間。在行上開新段落時拿它當切點。
    let start: Double
    let layout: Layout
}

struct SheetTake: Identifiable {
    let id: String
    let occurrenceNumber: Int
    /// 這次跟第一次和弦不一樣，才會單獨列出來。
    let isVariant: Bool
    /// 段落開頭的和弦總覽（已壓縮連續重複）。
    let chordRow: [SheetChord]
    let lines: [SheetLine]
}

struct SheetSection: Identifiable {
    let id: String
    let label: String
    /// 這一段**原始**的切點時間。人工修正切點時拿它當 key ——
    /// 修正後的時間會跟著位移變，不能當 key。
    let anchor: Double
    /// 這個段落在整首歌出現幾次；> 1 時標題顯示 ×N。
    let repeatCount: Int
    /// 這一段要用的 Nord 音色。每一段都有（你才知道現在該在哪一顆）。
    var patch: NordPatch?
    /// 跟上一段不同＝真的要伸手去轉。相同的話畫面上會變淡。
    var patchIsChange = true
    let takes: [SheetTake]
}

// MARK: - Builder

enum LeadSheetBuilder {

    static func build(
        project: SongProject,
        catalog: NordCatalog,
        overrides: NordPatchOverrideStore,
        boundaries: SectionBoundaryStore? = nil,
        userSections: UserSectionStore? = nil,
        sectionPatches: SectionPatchStore? = nil
    ) -> [SheetSection] {
        let timeline = keyboardTimeline(project, catalog: catalog, overrides: overrides)
        let chords = project.chords.sorted { $0.time < $1.time }
        let lyrics = cleanedLyrics(project)
        let groups = groupedSectionRanges(project, chords: chords, lyrics: lyrics,
                                          boundaries: boundaries, userSections: userSections)

        let sections = groups.compactMap { group -> SheetSection? in
            let occurrences = group.occurrences
            let total = occurrences.count

            var wanted: [(range: SectionRange, occurrence: Int, isVariant: Bool)] = []
            if total > 1 {
                wanted.append((occurrences[0], 1, false))
                for (offset, occurrence) in occurrences.dropFirst().enumerated() {
                    if meaningfullyDifferentChords(chords, occurrences[0], occurrence) {
                        wanted.append((occurrence, offset + 2, true))
                    }
                }
            } else {
                wanted = occurrences.enumerated().map { ($0.element, $0.offset + 1, false) }
            }

            let takes: [SheetTake] = wanted.compactMap { item in
                let range = item.range
                let takeChords = chords.filter { $0.time >= range.start && $0.time < range.end }
                let takeLyrics = lyrics.filter { $0.start >= range.start && $0.start < range.end }
                guard !takeChords.isEmpty || !takeLyrics.isEmpty else { return nil }

                let lines = takeLyrics.map { line -> SheetLine in
                    let lineChords = chords.filter { $0.time >= line.start && $0.time < line.end }
                    return sheetLine(for: line, chords: lineChords)
                }
                return SheetTake(
                    id: "\(group.base)-\(range.start)-\(item.occurrence)",
                    occurrenceNumber: item.occurrence,
                    isVariant: item.isVariant,
                    chordRow: compactChords(takeChords),
                    lines: lines
                )
            }

            guard !takes.isEmpty else { return nil }
            let sectionID = "\(group.base)-\(occurrences[0].anchor)"
            // 這一段自己指定的音色最優先；沒指定才退回整首的推薦／你選的那一顆。
            let sectionPatch = sectionPatches?
                .raw(projectID: project.id, sectionID: sectionID)
                .map { NordPatch.parse($0, catalog: catalog) }
            return SheetSection(
                // id 用 anchor 不用 start：切點被人工移動時 start 會變，
                // 用 start 當 id 會讓已經寫好的段落筆記整個脫鉤。
                id: sectionID,
                label: group.base,
                anchor: occurrences[0].anchor,
                repeatCount: total,
                patch: sectionPatch ?? activePatch(in: timeline, at: occurrences[0].start),
                takes: takes
            )
        }

        return markPatchChanges(sections)
    }

    /// 連續同一顆音色不再隱藏，改成變淡 —— 你隨時看得到現在該在哪一顆，
    /// 但「要伸手去轉」的那幾段仍然一眼跳出來。
    private static func markPatchChanges(_ sections: [SheetSection]) -> [SheetSection] {
        var lastPatch: NordPatch?
        return sections.map { section in
            guard let patch = section.patch else { return section }
            var section = section
            section.patchIsChange = !(lastPatch?.isSameSound(as: patch) ?? false)
            lastPatch = patch
            return section
        }
    }

    /// 這首歌的音色格。長度至少 minimumSlots，原始推薦更多就更長。
    /// 每一格：使用者填過的優先，否則落回原始資料的第 i 顆推薦。
    static func patchSlots(
        _ project: SongProject,
        catalog: NordCatalog,
        overrides: NordPatchOverrideStore
    ) -> [(original: NordPatch?, resolved: NordPatch?, isCustom: Bool)] {
        let originals = originalPatches(project, catalog: catalog)
        let count = max(NordPatchOverrideStore.minimumSlots, originals.count)
        return (0..<count).map { index in
            let original = index < originals.count ? originals[index] : nil
            if let raw = overrides.slotPatch(projectID: project.id, index: index) {
                return (original, NordPatch.parse(raw, catalog: catalog), true)
            }
            return (original, original, false)
        }
    }

    /// 這首歌的鍵盤音色時間軸，已經套上使用者的自訂。
    /// 一份資料同時餵給標題列的清單跟段落徽章，兩邊才不會各講各的。
    static func keyboardTimeline(
        _ project: SongProject,
        catalog: NordCatalog,
        overrides: NordPatchOverrideStore
    ) -> [(time: Double, patch: NordPatch)] {
        let originals = originalPatches(project, catalog: catalog)
        let slots = patchSlots(project, catalog: catalog, overrides: overrides)

        // 使用者一旦自己挑過音色，這首歌就以他的為準，不再把自動推薦的「換音色」印上譜。
        //
        // 自動推薦實測幾乎沒有鑑別力：24 首有鍵盤註記的歌裡，有 23 首在同一首歌內
        // 既推風琴又推電鋼 —— 它連「這首是什麼樂器」都沒有立場。台上看到假的
        // 「伸手轉旋鈕」提示比完全沒有提示更糟，尤其當它跟你自己挑的那顆互相矛盾
        // （實例：Cissy Strut 選了 All Draws Out，譜上卻仍叫你換去 E Piano MKII）。
        //
        // 要在段落之間換音色的話，用「每段落重點」自己寫 —— 那是你決定的，不是猜的。
        if let chosen = slots.first(where: { $0.isCustom })?.resolved {
            return [(0, chosen)]
        }

        let notes = project.bandNotes
            .filter { $0.instrument == "keyboard" }
            .sorted { ($0.time ?? 0) < ($1.time ?? 0) }

        var result: [(time: Double, patch: NordPatch)] = []
        for note in notes {
            let raw = note.detail.isEmpty ? note.label : note.detail
            guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let original = NordPatch.parse(raw, catalog: catalog)
            // 這顆推薦音色排在第幾格，就吃第幾格的自訂結果。
            let index = originals.firstIndex { $0.isSameSound(as: original) }
            let resolved = index.flatMap { slots[$0].resolved } ?? original
            result.append((note.time ?? 0, resolved))
        }

        // 這首歌本來沒有鍵盤註記，但使用者在第一格填了音色，就從頭用到尾。
        if result.isEmpty, let first = slots.first?.resolved {
            result.append((0, first))
        }
        return result
    }

    /// 整首歌會用到的 Nord 音色，去重、照時間排。
    /// 段落徽章只標「換音色的那一刻」，但很多歌的第一筆註記不在時間 0，
    /// 開頭會整片空白，所以標題列要有一份完整清單。
    static func patches(
        _ project: SongProject,
        catalog: NordCatalog,
        overrides: NordPatchOverrideStore
    ) -> [NordPatch] {
        var result: [NordPatch] = []
        for entry in keyboardTimeline(project, catalog: catalog, overrides: overrides) {
            if !result.contains(where: { $0.isSameSound(as: entry.patch) }) {
                result.append(entry.patch)
            }
        }
        return result
    }

    /// 這首歌原本（未覆寫）用到的音色，用來當覆寫的識別 key。
    static func originalPatches(_ project: SongProject, catalog: NordCatalog) -> [NordPatch] {
        var result: [NordPatch] = []
        let notes = project.bandNotes
            .filter { $0.instrument == "keyboard" }
            .sorted { ($0.time ?? 0) < ($1.time ?? 0) }
        for note in notes {
            let raw = note.detail.isEmpty ? note.label : note.detail
            guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let patch = NordPatch.parse(raw, catalog: catalog)
            if !result.contains(where: { $0.isSameSound(as: patch) }) {
                result.append(patch)
            }
        }
        return result
    }

    /// 整首歌用到的和弦，去重、保持出現順序。開場前掃一眼用。
    static func distinctChords(_ project: SongProject) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for chord in project.chords.sorted(by: { $0.time < $1.time }) where !seen.contains(chord.chord) {
            seen.insert(chord.chord)
            result.append(chord.chord)
        }
        return result
    }

    // MARK: Section ranges

    struct SectionRange {
        let label: String
        let start: Double
        let end: Double
        /// 未經人工修正的原始切點。存修正值時當 key。
        let anchor: Double
    }

    static func sectionRanges(
        _ project: SongProject,
        lyrics: [LyricLine] = [],
        boundaries: SectionBoundaryStore? = nil,
        userSections: UserSectionStore? = nil
    ) -> [SectionRange] {
        // 有自訂段落就完全用自訂的。混用自動跟手標只會讓人分不清哪條線是誰畫的。
        if let userSections, userSections.hasCustom(projectID: project.id) {
            return applyBoundaryOffsets(
                userRanges(userSections.sections(projectID: project.id), project: project),
                lyrics: lyrics, projectID: project.id, boundaries: boundaries)
        }

        let sections = project.sections.sorted { $0.start < $1.start }
        guard !sections.isEmpty else {
            let lastChord = project.chords.map(\.time).max() ?? 0
            let lastLyric = project.lyrics.map(\.end).max() ?? 0
            let end = max(project.song.durationSec ?? 0, lastChord, lastLyric)
            return [SectionRange(label: "Song", start: 0, end: end, anchor: 0)]
        }

        var ranges: [SectionRange] = []
        if sections[0].start > 0 {
            ranges.append(SectionRange(label: "Intro", start: 0, end: sections[0].start, anchor: 0))
        }
        for (index, section) in sections.enumerated() {
            let nextStart = index + 1 < sections.count ? sections[index + 1].start : nil
            let end = section.end ?? nextStart ?? project.song.durationSec ?? section.start
            ranges.append(SectionRange(label: section.label, start: section.start,
                                       end: end, anchor: section.start))
        }
        return applyBoundaryOffsets(ranges, lyrics: lyrics,
                                    projectID: project.id, boundaries: boundaries)
    }

    /// 自訂段落 → SectionRange。第一段若不是從 0 開始，前面補一段 Intro。
    private static func userRanges(
        _ entries: [UserSectionStore.Entry],
        project: SongProject
    ) -> [SectionRange] {
        guard !entries.isEmpty else { return [] }
        let lastChord = project.chords.map(\.time).max() ?? 0
        let lastLyric = project.lyrics.map(\.end).max() ?? 0
        let songEnd = max(project.song.durationSec ?? 0, lastChord, lastLyric)

        var ranges: [SectionRange] = []
        if entries[0].time > 0 {
            ranges.append(SectionRange(label: "Intro", start: 0,
                                       end: entries[0].time, anchor: 0))
        }
        for (index, entry) in entries.enumerated() {
            let end = index + 1 < entries.count ? entries[index + 1].time : songEnd
            ranges.append(SectionRange(label: entry.label, start: entry.time,
                                       end: end, anchor: entry.time))
        }
        return ranges
    }

    /// 把「往前／往後移幾行歌詞」換算成實際時間，並把前一段的結尾接上。
    ///
    /// 以歌詞行為單位而不是秒，是因為使用者看到的就是行 —— 說「晚了一行」
    /// 比說「晚了 3.04 秒」直覺得多，而且不同歌的行長差很多。
    private static func applyBoundaryOffsets(
        _ ranges: [SectionRange],
        lyrics: [LyricLine],
        projectID: String,
        boundaries: SectionBoundaryStore?
    ) -> [SectionRange] {
        guard let boundaries, !lyrics.isEmpty, ranges.count > 1 else { return ranges }
        let starts = lyrics.map(\.start).sorted()

        var adjusted = ranges
        // 第一段的開頭固定在 0，不給移。
        for index in 1..<adjusted.count {
            let offset = boundaries.offset(projectID: projectID, anchor: adjusted[index].anchor)
            guard offset != 0 else { continue }
            guard let current = starts.firstIndex(where: { $0 >= adjusted[index].start }) else { continue }
            let target = min(max(current + offset, 0), starts.count - 1)
            var newStart = starts[target]
            // 不能越過鄰居，否則段落順序會亂掉。
            newStart = max(newStart, adjusted[index - 1].start + 0.01)
            if index + 1 < adjusted.count {
                newStart = min(newStart, adjusted[index + 1].start - 0.01)
            }
            adjusted[index] = SectionRange(label: adjusted[index].label, start: newStart,
                                           end: adjusted[index].end,
                                           anchor: adjusted[index].anchor)
            adjusted[index - 1] = SectionRange(label: adjusted[index - 1].label,
                                               start: adjusted[index - 1].start,
                                               end: newStart,
                                               anchor: adjusted[index - 1].anchor)
        }
        return adjusted
    }

    /// 把 "Verse (Rep)" 收斂成 "Verse"。
    static func baseSectionLabel(_ label: String) -> String {
        let stripped = label.replacingOccurrences(
            of: "\\s*\\(Rep\\)\\s*$",
            with: "",
            options: [.regularExpression]
        ).trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? "Section" : stripped
    }

    struct SectionGroup {
        let base: String
        var occurrences: [SectionRange]
    }

    static func groupedSectionRanges(
        _ project: SongProject,
        chords: [ChordEvent],
        lyrics: [LyricLine] = [],
        boundaries: SectionBoundaryStore? = nil,
        userSections: UserSectionStore? = nil
    ) -> [SectionGroup] {
        var groups: [SectionGroup] = []
        // base label → groups 裡的 index，同名段落也可能因為和弦差太多而分成兩組。
        var bucketIndices: [String: [Int]] = [:]

        for range in sectionRanges(project, lyrics: lyrics, boundaries: boundaries,
                                   userSections: userSections) {
            let base = baseSectionLabel(range.label)
            var placed = false
            for index in bucketIndices[base, default: []] {
                if repeatCompatible(chords, groups[index].occurrences[0], range) {
                    groups[index].occurrences.append(range)
                    placed = true
                    break
                }
            }
            if !placed {
                groups.append(SectionGroup(base: base, occurrences: [range]))
                bucketIndices[base, default: []].append(groups.count - 1)
            }
        }
        return groups
    }

    // MARK: Chord helpers

    /// 連續重複的和弦只留第一顆。
    static func compactChordEvents(_ chords: [ChordEvent]) -> [ChordEvent] {
        var result: [ChordEvent] = []
        var last: String?
        for chord in chords where chord.chord != last {
            result.append(chord)
            last = chord.chord
        }
        return result
    }

    static func compactChords(_ chords: [ChordEvent]) -> [SheetChord] {
        compactChordEvents(chords).map { SheetChord(time: $0.time, symbol: $0.chord) }
    }

    /// 只要符號、不要時間：段落之間比對「和弦走向一不一樣」時用這支。
    static func compactSymbols(_ chords: [ChordEvent]) -> [String] {
        compactChordEvents(chords).map(\.chord)
    }

    private static func chordPattern(_ chords: [ChordEvent], from start: Double, to end: Double) -> [String] {
        compactSymbols(chords.filter { $0.time >= start && $0.time < end })
    }

    /// 同名段落不一定真的是重複；長度與和弦內容都要對得上才合併。
    static func repeatCompatible(_ chords: [ChordEvent], _ reference: SectionRange, _ candidate: SectionRange) -> Bool {
        let referenceDuration = max(reference.end - reference.start, 0.001)
        let candidateDuration = max(candidate.end - candidate.start, 0.001)
        let durationRatio = min(referenceDuration, candidateDuration) / max(referenceDuration, candidateDuration)
        guard durationRatio >= 0.72 else { return false }

        let referencePattern = chordPattern(chords, from: reference.start, to: reference.end)
        let candidatePattern = chordPattern(chords, from: candidate.start, to: candidate.end)
        if referencePattern.isEmpty || candidatePattern.isEmpty { return true }

        let countRatio = Double(min(referencePattern.count, candidatePattern.count))
            / Double(max(referencePattern.count, candidatePattern.count))
        guard countRatio >= 0.65 else { return false }

        return similarityRatio(referencePattern, candidatePattern) >= 0.45
    }

    static func meaningfullyDifferentChords(_ chords: [ChordEvent], _ reference: SectionRange, _ candidate: SectionRange) -> Bool {
        let referencePattern = chordPattern(chords, from: reference.start, to: reference.end)
        let candidatePattern = chordPattern(chords, from: candidate.start, to: candidate.end)
        if referencePattern == candidatePattern { return false }
        if referencePattern.isEmpty || candidatePattern.isEmpty {
            return !(referencePattern.isEmpty && candidatePattern.isEmpty)
        }
        return similarityRatio(referencePattern, candidatePattern) < 0.85
    }

    /// 對應 Python difflib SequenceMatcher.ratio()，這裡用 LCS 算：2 * LCS / (len(a) + len(b))。
    static func similarityRatio(_ lhs: [String], _ rhs: [String]) -> Double {
        if lhs.isEmpty && rhs.isEmpty { return 1 }
        if lhs.isEmpty || rhs.isEmpty { return 0 }

        var previous = [Int](repeating: 0, count: rhs.count + 1)
        var current = previous
        for i in 1...lhs.count {
            for j in 1...rhs.count {
                current[j] = lhs[i - 1] == rhs[j - 1]
                    ? previous[j - 1] + 1
                    : max(previous[j], current[j - 1])
            }
            previous = current
            current = [Int](repeating: 0, count: rhs.count + 1)
        }
        return 2 * Double(previous[rhs.count]) / Double(lhs.count + rhs.count)
    }

    // MARK: Lyric line layout

    static func isCJK(_ character: Character) -> Bool {
        guard let value = character.unicodeScalars.first?.value else { return false }
        return (0x3400...0x9FFF).contains(value)   // 漢字
            || (0xF900...0xFAFF).contains(value)   // 相容漢字
            || (0x3040...0x30FF).contains(value)   // 假名
    }

    /// 排版單位：漢字一個字算一個，拉丁文以空白斷詞。
    ///
    /// web 版是用空白數詞的，那對英文歌沒問題，但中文歌詞整句幾乎沒有空白，
    /// 永遠只數到 2、3 個「詞」，於是每一句都被判定成「太擠」而把和弦整排壓在上面，
    /// 和弦落在哪個字上的資訊就整個消失了。
    static func displayUnits(_ text: String) -> Int {
        var count = 0
        var inLatinRun = false
        for character in text {
            if character.isWhitespace {
                inLatinRun = false
            } else if isCJK(character) {
                count += 1
                inLatinRun = false
            } else if !inLatinRun {
                count += 1
                inLatinRun = true
            }
        }
        return count
    }

    /// 一句話裡漢字佔多數，就不做「吸附到字首」—— 中文沒有詞界，
    /// 硬吸附會把相隔很遠的兩顆和弦拉到同一個空白旁邊擠在一起。
    static func isCJKHeavy(_ characters: [Character]) -> Bool {
        let visible = characters.filter { !$0.isWhitespace }
        guard !visible.isEmpty else { return false }
        return Double(visible.filter(isCJK).count) / Double(visible.count) > 0.3
    }

    /// 和弦太多、句子太短時，逐字對位會擠成一團，改成整排壓在上面。
    /// 判準是「每顆和弦有沒有三個字的位置可以站」。
    static func shouldStackChords(_ events: [ChordEvent], text: String) -> Bool {
        let count = events.count
        guard count > 1 else { return false }
        return displayUnits(text) < count * 3
    }

    /// 把位置吸附到最近的字首（前後 radius 個字元內），避免和弦切在單字中間。
    /// 中文沒有空格，會原地不動，跟 web 版行為一致。
    static func wordStartNear(_ characters: [Character], _ position: Int, radius: Int = 8) -> Int {
        if position <= 0 { return 0 }
        let count = characters.count
        if position >= count { return count }

        var index = position
        while index >= max(0, position - radius) {
            if index > 0 && characters[index - 1] == " " { return index }
            index -= 1
        }
        index = position + 1
        while index <= min(count, position + radius) {
            if index > 0 && characters[index - 1] == " " { return index }
            index += 1
        }
        return position
    }

    static func sheetLine(for lyric: LyricLine, chords: [ChordEvent]) -> SheetLine {
        let text = lyric.text
        let id = "\(lyric.start)-\(text)"
        guard !chords.isEmpty, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return SheetLine(id: id, start: lyric.start, layout: .plain(text))
        }

        let events = compactChordEvents(chords.sorted { $0.time < $1.time })
        if shouldStackChords(events, text: text) {
            return SheetLine(id: id, start: lyric.start, layout: .stacked(chords: events.map { SheetChord(time: $0.time, symbol: $0.chord) }, text: text))
        }

        let characters = Array(text)
        let snapsToWordStarts = !isCJKHeavy(characters)
        let duration = max(lyric.end - lyric.start, 0.001)
        var cuts: [(position: Int, chords: [SheetChord])] = []
        for event in events {
            let fraction = min(max((event.time - lyric.start) / duration, 0), 1)
            let raw = Int(fraction * Double(characters.count))
            let position = snapsToWordStarts ? wordStartNear(characters, raw) : raw
            if let last = cuts.last, last.position == position {
                cuts[cuts.count - 1].chords.append(SheetChord(time: event.time, symbol: event.chord))
            } else {
                cuts.append((position, [SheetChord(time: event.time, symbol: event.chord)]))
            }
        }
        guard let firstCut = cuts.first else {
            return SheetLine(id: id, start: lyric.start, layout: .plain(text))
        }

        var segments: [SheetSegment] = []
        if firstCut.position > 0 {
            segments.append(SheetSegment(
                id: 0,
                chords: [],
                text: String(characters[0..<firstCut.position])
            ))
        }
        for (index, cut) in cuts.enumerated() {
            let end = index + 1 < cuts.count ? cuts[index + 1].position : characters.count
            segments.append(SheetSegment(
                id: segments.count,
                chords: cut.chords,
                text: String(characters[cut.position..<end])
            ))
        }
        return SheetLine(id: id, start: lyric.start, layout: .inline(segments))
    }

    // MARK: Lyrics cleanup

    private static let sectionLabelPattern =
        "^\\[?\\s*(intro|verse|pre[-\\s]?chorus|chorus|bridge|solo|interlude|outro|instrumental|hook|refrain)"
        + "(?:\\s+\\d+)?\\s*\\]?$"
    private static let creditPrefixPattern =
        "^\\s*(低音吉他|中提琴|音頻工程師|混音師|附加製作|人聲錄音|絃樂編寫|弦樂編寫|"
        + "母帶工程師|人聲|編程|製作|作詞|作曲|編曲|監製|錄音|"
        + "bass|viola|audio engineer|mixing engineer|mastering engineer|"
        + "vocal|vocals|programming|producer|additional production|recording engineer|"
        + "strings arrangement|arranger|composer|lyricist)\\s*[:：｜|]"
    private static let trailingCreditPattern =
        "(mixing engineer|mastering engineer|audio engineer|recording engineer|producer|arranger)"
    private static let pronounPattern = "\\b(i|you|we|he|she|they)\\b"

    /// 濾掉段落標記、製作名單這類不是歌詞的行，跟 web 版 clean_lyrics 一致。
    static func cleanedLyrics(_ project: SongProject) -> [LyricLine] {
        project.lyrics
            .sorted { $0.start < $1.start }
            .enumerated()
            .filter { !isMetadataLyric($0.element, song: project.song, lineIndex: $0.offset) }
            .map(\.element)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isMetadataLyric(_ line: LyricLine, song: SongInfo, lineIndex: Int) -> Bool {
        let stripped = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.isEmpty { return true }
        if matches(stripped, sectionLabelPattern) { return true }
        if matches(stripped, creditPrefixPattern) { return true }
        if matches(stripped, trailingCreditPattern) && !matches(stripped, pronounPattern) { return true }

        let normalised = normalise(stripped)
        let artist = normalise(song.artist)
        let title = normalise(song.title)
        if !artist.isEmpty && normalised == artist { return true }
        if lineIndex < 3 && line.start < 12 && !title.isEmpty && normalised == title { return true }
        return false
    }

    /// 小寫、去掉括號內容、只留字母數字，用來比對「這行是不是就是歌名／團名」。
    private static func normalise(_ value: String) -> String {
        let withoutParens = value.replacingOccurrences(
            of: "\\([^)]*\\)",
            with: "",
            options: [.regularExpression]
        )
        return String(withoutParens.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    // MARK: Band notes

    /// 段落開頭當下還在生效的 Nord 音色。
    static func activePatch(in timeline: [(time: Double, patch: NordPatch)], at start: Double) -> NordPatch? {
        timeline.last { $0.time <= start }?.patch
    }
}
