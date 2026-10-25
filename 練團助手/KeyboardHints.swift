import SwiftUI

// MARK: - 鍵盤和弦圖

/// 兩個八度的鍵盤，把和弦的組成音標出來。
/// 這是「認和弦」用的圖，不是指法圖 —— 標的是音級，實際 voicing 你自己決定。
struct KeyboardDiagram: View {
    let shape: ChordShape
    var whiteKeyWidth: CGFloat = 15
    var whiteKeyHeight: CGFloat = 58

    private let octaves = 2
    private let whiteOffsets = [0, 2, 4, 5, 7, 9, 11]
    /// 黑鍵夾在第 0、1、3、4、5 個白鍵右邊。
    private let blackAfterWhite = [0, 1, 3, 4, 5]
    private let blackOffsets = [1, 3, 6, 8, 10]

    // 鍵盤在亮色暗色下都該長得像鍵盤，所以琴鍵顏色寫死不跟著主題翻。
    static let whiteKeyColor = Color(white: 0.96)
    static let blackKeyColor = Color(white: 0.11)

    private var blackKeyWidth: CGFloat { whiteKeyWidth * 0.62 }
    private var blackKeyHeight: CGFloat { whiteKeyHeight * 0.62 }
    private var totalWidth: CGFloat { CGFloat(octaves * 7) * whiteKeyWidth }

    /// 和弦音擺進兩個八度的位置。
    private var markedSemitones: Set<Int> {
        var result: Set<Int> = []
        let base = shape.bass == nil ? shape.root : shape.root + 12
        for interval in shape.intervals {
            var semitone = base + interval
            while semitone > octaves * 12 - 1 { semitone -= 12 }
            result.insert(semitone)
        }
        return result
    }

    private var rootSemitone: Int {
        let base = shape.bass == nil ? shape.root : shape.root + 12
        return base > octaves * 12 - 1 ? base - 12 : base
    }

    private var bassSemitone: Int? {
        shape.bass
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            whiteKeys
            blackKeys
        }
        .frame(width: totalWidth, height: whiteKeyHeight)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.quaternary, lineWidth: 1))
    }

    private var whiteKeys: some View {
        HStack(spacing: 0) {
            ForEach(0..<(octaves * 7), id: \.self) { index in
                let semitone = (index / 7) * 12 + whiteOffsets[index % 7]
                ZStack(alignment: .bottom) {
                    Rectangle()
                        .fill(KeyboardDiagram.whiteKeyColor)
                        .overlay(Rectangle().stroke(Color(white: 0.72), lineWidth: 0.5))
                    if let dot = dotColor(for: semitone, onBlackKey: false) {
                        Circle()
                            .fill(dot)
                            .frame(width: whiteKeyWidth * 0.62, height: whiteKeyWidth * 0.62)
                            .padding(.bottom, whiteKeyWidth * 0.3)
                    }
                }
                .frame(width: whiteKeyWidth, height: whiteKeyHeight)
            }
        }
    }

    private var blackKeys: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<(octaves * 5), id: \.self) { index in
                let octave = index / 5
                let slot = index % 5
                let semitone = octave * 12 + blackOffsets[slot]
                let x = CGFloat(octave * 7 + blackAfterWhite[slot] + 1) * whiteKeyWidth - blackKeyWidth / 2
                ZStack(alignment: .bottom) {
                    Rectangle().fill(KeyboardDiagram.blackKeyColor)
                    if let dot = dotColor(for: semitone, onBlackKey: true) {
                        Circle()
                            .fill(dot)
                            .frame(width: blackKeyWidth * 0.72, height: blackKeyWidth * 0.72)
                            .padding(.bottom, blackKeyWidth * 0.28)
                    }
                }
                .frame(width: blackKeyWidth, height: blackKeyHeight)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
                .offset(x: x)
            }
        }
    }

    // 琴鍵顏色不隨主題翻，所以上面的點也不能翻，否則暗色下根音會跟其他音同色。
    private static let whiteKeyDot = Color(red: 0.78, green: 0.13, blue: 0.13)
    private static let blackKeyDot = Color(red: 1.0, green: 0.55, blue: 0.55)
    // 分數和弦的低音改用藍色。原本是橘的，和弦音變紅之後兩者太接近了。
    private static let whiteKeyBassDot = Color(red: 0.141, green: 0.400, blue: 0.659)
    private static let blackKeyBassDot = Color(red: 0.62, green: 0.83, blue: 1.0)

    private func dotColor(for semitone: Int, onBlackKey: Bool) -> Color? {
        if semitone == bassSemitone {
            return onBlackKey ? Self.blackKeyBassDot : Self.whiteKeyBassDot
        }
        guard markedSemitones.contains(semitone) else { return nil }
        let isRoot = semitone == rootSemitone
        if onBlackKey {
            return isRoot ? Self.blackKeyDot : Self.blackKeyDot.opacity(0.72)
        }
        return isRoot ? Self.whiteKeyDot : Self.whiteKeyDot.opacity(0.42)
    }
}

/// 點和弦跳出來的小卡：鍵盤圖 + 音名。
struct ChordHintCard: View {
    let symbol: String
    /// 認不出來的符號也要能開卡片 —— 不然最該改的那幾顆反而點不動。
    let shape: ChordShape?
    var isCustom = false
    var onEdit: (() -> Void)? = nil

    /// 和弦表共用同一個偏好設定 key，切一次兩邊都跟著換。
    @AppStorage("chordDiagramMode") private var mode = "keyboard"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(symbol)
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(Color.sheetChord)
                if isCustom {
                    Text("已改")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.sheetChord.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.sheetChord)
                }
                Spacer()
                if shape != nil {
                    Picker("", selection: $mode) {
                        Text("鍵盤").tag("keyboard")
                        Text("吉他").tag("guitar")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }
            if let shape {
                if mode == "keyboard" {
                    KeyboardDiagram(shape: shape, whiteKeyWidth: 20, whiteKeyHeight: 76)
                } else {
                    GuitarDiagram(symbol: symbol)
                }
                Text(shape.noteNames.joined(separator: "  "))
                    .font(.callout.weight(.semibold).monospaced())
                    .foregroundStyle(.secondary)
                if shape.bass != nil {
                    Text("藍點＝低音（bass 顧根音時你可以不彈）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !shape.isRecognised {
                    Text("這個後綴我沒認出來，暫時當大三和弦畫。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                Text("這個符號解不開，畫不出鍵盤圖。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let onEdit {
                Divider()
                Button(action: onEdit) {
                    Label("改和弦", systemImage: "pencil")
                        .font(.callout.weight(.semibold))
                }
            }
        }
        .padding(16)
    }
}

/// 改和弦。
///
/// 和弦是模型聽出來的，會錯；這裡讓鍵盤手當場改掉。
/// 做成 sheet 而不是層層選單，是因為這是在譜架上隔一段距離操作 —— 按鈕要夠大。
struct ChordEditorView: View {
    let displayed: String
    let isCustom: Bool
    let onPick: (String) -> Void
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var root: String
    @State private var quality: String
    @State private var bass: String
    @State private var diagramMode = "keyboard"

    init(displayed: String, isCustom: Bool,
         onPick: @escaping (String) -> Void, onReset: @escaping () -> Void) {
        self.displayed = displayed
        self.isCustom = isCustom
        self.onPick = onPick
        self.onReset = onReset
        let parts = ChordChoice.split(displayed)
        _root = State(initialValue: parts?.root ?? "C")
        _quality = State(initialValue: parts?.quality ?? "")
        _bass = State(initialValue: parts?.bass ?? "")
    }

    private var preview: String {
        ChordChoice.compose(root: root, quality: quality, bass: bass)
    }

    private let grid = [GridItem(.adaptive(minimum: 64), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    previewCard
                    picker("根音", options: ChordChoice.roots.map { ($0, $0) },
                           selection: root) { root = $0 }
                    picker("性質", options: ChordChoice.qualities.map { ($0.label, $0.suffix) },
                           selection: quality) { quality = $0 }
                    picker("低音（斜線和弦）",
                           options: [("無", "")] + ChordChoice.roots.map { ($0, $0) },
                           selection: bass) { bass = $0 }
                }
                .padding(20)
            }
            .navigationTitle("改和弦")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("套用") { onPick(preview); dismiss() }
                        .fontWeight(.semibold)
                }
                if isCustom {
                    ToolbarItem(placement: .bottomBar) {
                        Button("改回原本", role: .destructive) { onReset(); dismiss() }
                    }
                }
            }
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preview)
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(Color.sheetChord)
            if let shape = ChordShape.parse(preview) {
                HStack(alignment: .bottom) {
                    if diagramMode == "keyboard" {
                        KeyboardDiagram(shape: shape, whiteKeyWidth: 22, whiteKeyHeight: 84)
                    } else {
                        GuitarDiagram(symbol: preview)
                    }
                    Spacer()
                    Picker("", selection: $diagramMode) {
                        Text("鍵盤").tag("keyboard")
                        Text("吉他").tag("guitar")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
                Text(shape.noteNames.joined(separator: "  "))
                    .font(.callout.weight(.semibold).monospaced())
                    .foregroundStyle(.secondary)
            }
            if preview != displayed {
                Text("原本：\(displayed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func picker(_ title: String,
                        options: [(String, String)],
                        selection: String,
                        onSelect: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: grid, alignment: .leading, spacing: 8) {
                ForEach(options, id: \.1) { option in
                    let picked = option.1 == selection
                    Button { onSelect(option.1) } label: {
                        Text(option.0)
                            .font(.callout.weight(picked ? .bold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                    .tint(picked ? Color.sheetChord : .secondary)
                }
            }
        }
    }
}

/// 整首歌用到的和弦一覽，開場前掃一眼用。
struct ChordPalette: View {
    let symbols: [String]
    let transposeSteps: Int

    @AppStorage("chordDiagramMode") private var mode = "keyboard"

    private var columns: [GridItem] {
        let min: CGFloat = mode == "keyboard" ? 220 : 155
        return [GridItem(.adaptive(minimum: min), spacing: 16, alignment: .leading)]
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Picker("", selection: $mode) {
                Text("鍵盤").tag("keyboard")
                Text("吉他").tag("guitar")
            }
            .pickerStyle(.segmented)
            .frame(width: 120)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    let transposed = MusicTransposer.transposeChord(symbol, semitones: transposeSteps)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transposed)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Color.sheetChord)
                        if mode == "keyboard" {
                            if let shape = ChordShape.parse(transposed) {
                                KeyboardDiagram(shape: shape)
                            }
                        } else {
                            GuitarDiagram(symbol: transposed, width: 140, height: 56)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Nord 音色徽章

struct NordPatchBadge: View {
    let patch: NordPatch
    /// 自己改過的音色標一顆點，跟推薦的分得出來。
    var isOverridden = false
    /// 跟上一段是同一顆音色時整個變淡。
    ///
    /// 每一段都印音色（你才知道現在該在哪一顆），但「要伸手去轉」的那幾段
    /// 必須一眼就跳出來 —— 每段都同樣醒目等於沒有重點。
    var isChange = true

    var body: some View {
        content.opacity(isChange ? 1 : 0.4)
    }

    private var content: some View {
        HStack(spacing: 8) {
            if let program = patch.programDisplay {
                Text(program)
                    .font(.system(size: 15, weight: .black).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(familyColor, in: RoundedRectangle(cornerRadius: 5))
            }
            Text(patch.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
            if let drawbars = patch.drawbars {
                Text(drawbars)
                    .font(.system(size: 14, weight: .bold).monospaced())
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
            if isOverridden {
                Circle()
                    .fill(familyColor)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(familyColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
    }

    private var familyColor: Color {
        switch patch.family {
        case .organ: return Color(red: 0.62, green: 0.29, blue: 0.65)
        case .piano: return Color(red: 0.20, green: 0.42, blue: 0.30)
        case .electricPiano: return Color(red: 0.14, green: 0.40, blue: 0.66)
        case .clav: return Color(red: 0.72, green: 0.45, blue: 0.10)
        case .sample: return Color(red: 0.45, green: 0.45, blue: 0.50)
        case .unknown: return Color(red: 0.45, green: 0.45, blue: 0.50)
        }
    }
}

// MARK: - Nord 音色選擇

/// 徽章本身就是下拉選單：點下去，第一層音色類型、第二層 Program。
/// 跟 Streamlit 那邊的兩層選法一致，手指習慣不用重學。
struct NordPatchPicker: View {
    let catalog: NordCatalog
    /// 目前這一格用的音色；nil 代表這首歌還沒有指定。
    let current: NordPatch?
    let isOverridden: Bool
    /// 被蓋掉的原始推薦音色名稱，讓人知道自己改掉了什麼。
    let originalName: String?
    let onSelect: (String) -> Void
    let onReset: (() -> Void)?
    /// 你已經用過的音色，照次數排。放在最上面一層 ——
    /// 挑剩下的歌時一鍵到位，不用每次都翻兩層選單。
    var common: [String] = []

    var body: some View {
        Menu {
            if !common.isEmpty {
                Section("常用") {
                    ForEach(common, id: \.self) { raw in
                        let patch = NordPatch.parse(raw, catalog: catalog)
                        Button {
                            onSelect(raw)
                        } label: {
                            if isCurrent(patch) {
                                Label(label(for: patch), systemImage: "checkmark")
                            } else {
                                Text(label(for: patch))
                            }
                        }
                    }
                }
            }
            ForEach(catalog.categories) { category in
                Menu(category.name) {
                    ForEach(Array(category.entries.enumerated()), id: \.offset) { _, entry in
                        Button {
                            onSelect(entry.raw)
                        } label: {
                            if isCurrent(entry.patch) {
                                Label(label(for: entry.patch), systemImage: "checkmark")
                            } else {
                                Text(label(for: entry.patch))
                            }
                        }
                    }
                }
            }
            if let onReset {
                Divider()
                Button(role: .destructive) {
                    onReset()
                } label: {
                    Label(
                        originalName.map { "改回 \($0)" } ?? "清空這一格",
                        systemImage: "arrow.uturn.backward"
                    )
                }
            }
        } label: {
            // 命中區要自己撐開。.buttonStyle(.plain) 只會把文字本身當按鈕，
            // 徽章的文字高度大約 24pt，遠低於可以放心戳的 44pt ——
            // 站在譜架前、手還在琴上的時候，那個差距非常有感。
            HStack(spacing: 8) {
                if let current {
                    NordPatchBadge(patch: current, isOverridden: isOverridden)
                } else {
                    // 空格：淡一點，四個並排時才不會比譜還吵。
                    Label("選音色", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.secondary)
                }
                // 有這個小箭頭才看得出「這裡可以點」。
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.secondary.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(
                        Color.secondary.opacity(current == nil ? 0.35 : 0.18),
                        style: current == nil
                            ? StrokeStyle(lineWidth: 1, dash: [4, 3])
                            : StrokeStyle(lineWidth: 1)
                    )
            )
            // 整塊都可以按，不是只有畫到字的地方。
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
    }

    private func isCurrent(_ patch: NordPatch) -> Bool {
        guard let current else { return false }
        return current.isSameSound(as: patch)
    }

    private func label(for patch: NordPatch) -> String {
        guard let program = patch.programDisplay else { return patch.name }
        var text = "\(patch.name)  ·  \(program)"
        if let drawbars = patch.drawbars { text += "  ·  \(drawbars)" }
        return text
    }
}
