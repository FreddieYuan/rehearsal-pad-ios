import SwiftUI

/// 吉他指板圖（橫式）—— 靜態查表，每個和弦最多三個把位可切換。
/// lowE 在底、highE 在頂，nut 在左，格位向右。-1=悶弦  0=空弦  N=格位（絕對值）
struct GuitarDiagram: View {
    let symbol: String
    var width: CGFloat = 140
    var height: CGFloat = 64          // Canvas 高度；導覽列另加 ~16pt

    @State private var voicingIndex = 0

    // MARK: - 和弦曲庫（多把位）
    // 每個陣列依序：open 把位 → A-string barre → E-string barre
    // E-shape major  fret f: [f, f+2, f+2, f+1, f, f]
    // A-shape major  fret f: [-1, f, f+2, f+2, f+2, f]
    // E-shape minor  fret f: [f, f+2, f+2, f, f, f]
    // A-shape minor  fret f: [-1, f, f+2, f+2, f+1, f]
    // E-shape dom7   fret f: [f, f+2, f, f+1, f, f]
    // A-shape dom7   fret f: [-1, f, f+2, f, f+2, f]
    // E-shape m7     fret f: [f, f+2, f+2, f, f+3, f]  (open Em7 shape)
    // A-shape m7     fret f: [-1, f, f+2, f, f+1, f]
    // E-shape maj7   fret f: [f, f+2, f+1, f+1, f, f]
    // A-shape maj7   fret f: [-1, f, f+2, f+1, f+2, f]
    private static let library: [String: [[Int]]] = [

        // ── C ──
        "C":     [[-1, 3, 2, 0, 1, 0],
                  [-1, 3, 5, 5, 5, 3],
                  [8, 10, 10, 9, 8, 8]],
        "Cm":    [[-1, 3, 5, 5, 4, 3],
                  [8, 10, 10, 8, 8, 8]],
        "C7":    [[-1, 3, 2, 3, 1, 0],
                  [-1, 3, 5, 3, 5, 3],
                  [8, 10, 8, 9, 8, 8]],
        "Cmaj7": [[-1, 3, 2, 0, 0, 0],
                  [-1, 3, 5, 4, 5, 3],
                  [8, 10, 9, 9, 8, 8]],
        "Cadd9": [[-1, 3, 2, 0, 3, 3],
                  [-1, 3, 5, 5, 3, 3]],

        // ── D ──
        "D":     [[-1, -1, 0, 2, 3, 2],
                  [-1, 5, 7, 7, 7, 5],
                  [10, 12, 12, 11, 10, 10]],
        "Dm":    [[-1, -1, 0, 2, 3, 1],
                  [-1, 5, 7, 7, 6, 5],
                  [10, 12, 12, 10, 10, 10]],
        "D7":    [[-1, -1, 0, 2, 1, 2],
                  [-1, 5, 7, 5, 7, 5],
                  [10, 12, 10, 11, 10, 10]],
        "Dm7":   [[-1, -1, 0, 2, 1, 1],
                  [-1, 5, 7, 5, 6, 5]],
        "Dsus2": [[-1, -1, 0, 2, 3, 0],
                  [-1, 5, 7, 7, 5, 5]],

        // ── E ──
        "E":     [[0, 2, 2, 1, 0, 0],
                  [-1, 7, 9, 9, 9, 7]],
        "Em":    [[0, 2, 2, 0, 0, 0],
                  [-1, 7, 9, 9, 8, 7],
                  [7, 9, 9, 7, 7, 7]],
        "E7":    [[0, 2, 0, 1, 0, 0],
                  [-1, 7, 9, 7, 9, 7],
                  [7, 9, 7, 8, 7, 7]],
        "Em7":   [[0, 2, 2, 0, 3, 0],
                  [-1, 7, 9, 7, 8, 7]],
        "Esus4": [[0, 2, 2, 2, 0, 0],
                  [-1, 7, 9, 9, 10, 7]],

        // ── F ──
        "F":     [[1, 3, 3, 2, 1, 1],
                  [-1, 8, 10, 10, 10, 8]],
        "Fmaj7": [[-1, -1, 3, 2, 1, 0],
                  [1, 3, 2, 2, 1, 1],
                  [8, 10, 9, 9, 8, 8]],

        // ── G ──
        "G":     [[3, 2, 0, 0, 0, 3],
                  [3, 5, 5, 4, 3, 3],
                  [-1, 10, 12, 12, 12, 10]],
        "G7":    [[3, 2, 0, 0, 0, 1],
                  [3, 5, 3, 4, 3, 3],
                  [-1, 10, 12, 10, 12, 10]],
        "Gmaj7": [[3, 2, 0, 0, 0, 2],
                  [3, 5, 4, 4, 3, 3],
                  [-1, 10, 12, 11, 12, 10]],

        // ── A ──
        "A":     [[-1, 0, 2, 2, 2, 0],
                  [5, 7, 7, 6, 5, 5]],
        "Am":    [[-1, 0, 2, 2, 1, 0],
                  [5, 7, 7, 5, 5, 5],
                  [-1, 5, 7, 7, 6, 5]],
        "A7":    [[-1, 0, 2, 0, 2, 0],
                  [5, 7, 5, 6, 5, 5],
                  [-1, 5, 7, 5, 7, 5]],
        "Am7":   [[-1, 0, 2, 0, 1, 0],
                  [5, 7, 7, 5, 8, 5],
                  [-1, 5, 7, 5, 6, 5]],
        "Asus2": [[-1, 0, 2, 2, 0, 0],
                  [5, 7, 7, 4, 5, 5]],
        "Asus4": [[-1, 0, 2, 2, 3, 0],
                  [5, 7, 7, 7, 5, 5]],

        // ── B / Bb ──
        "Bb":    [[-1, 1, 3, 3, 3, 1],
                  [6, 8, 8, 7, 6, 6]],
        "Bm":    [[-1, 2, 4, 4, 3, 2],
                  [7, 9, 9, 7, 7, 7]],
        "B7":    [[-1, 2, 1, 2, 0, 2],
                  [-1, 2, 4, 2, 4, 2],
                  [7, 9, 7, 8, 7, 7]],
    ]

    private static let enharmonic: [String: String] = [
        "C#": "Db", "D#": "Eb", "F#": "Gb", "G#": "Ab", "A#": "Bb",
        "Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#",
    ]

    // 後綴簡化：先查曲庫
    private static let suffixFallbacks: [(String, String)] = [
        ("maj13","maj7"), ("maj11","maj7"), ("maj9","maj7"),
        ("13","7"), ("11","7"), ("9","7"),
        ("m13","m7"), ("m11","m7"), ("m9","m7"), ("m6","m"),
        ("6",""),
        ("add9",""), ("add11",""), ("add4",""),
        ("7sus4","sus4"), ("7sus2","sus2"), ("sus4",""), ("sus2",""),
        ("m7b5","m7"), ("m7","m"), ("maj7",""),
        ("dim7","m"), ("dim","m"), ("aug",""),
        ("7",""),
    ]

    // ── 動態 barre 生成 ──────────────────────────────────────────────
    // 對曲庫找不到的根音（C#、Eb、F# 等）用公式算把位

    private static let semitones: [String: Int] = [
        "C":0, "C#":1, "Db":1, "D":2, "D#":3, "Eb":3,
        "E":4, "F":5,  "F#":6, "Gb":6, "G":7,  "G#":8,
        "Ab":8,"A":9,  "A#":10,"Bb":10,"B":11,
    ]

    // Open shapes for A-string root (barre at fret 0 = open A position)
    private static let aShapes: [String: [Int]] = [
        "":     [-1, 0, 2, 2, 2, 0],
        "m":    [-1, 0, 2, 2, 1, 0],
        "7":    [-1, 0, 2, 0, 2, 0],
        "m7":   [-1, 0, 2, 0, 1, 0],
        "maj7": [-1, 0, 2, 1, 2, 0],
        "sus4": [-1, 0, 2, 2, 3, 0],
        "sus2": [-1, 0, 2, 2, 0, 0],
    ]

    // Open shapes for low-E root
    private static let eShapes: [String: [Int]] = [
        "":     [0, 2, 2, 1, 0, 0],
        "m":    [0, 2, 2, 0, 0, 0],
        "7":    [0, 2, 0, 1, 0, 0],
        "maj7": [0, 2, 1, 1, 0, 0],
        "sus4": [0, 2, 2, 2, 0, 0],
    ]

    // barre(shape, fret): 每個非悶弦加上 fret
    private static func barre(_ shape: [Int], at f: Int) -> [Int] {
        shape.map { $0 == -1 ? -1 : $0 + f }
    }

    // 後綴 → 對應 aShapes/eShapes 的 key
    private static func qualityKey(_ suffix: String) -> String? {
        switch suffix {
        case "", "5", "6", "add9", "add11", "add4", "aug": return ""
        case "m", "m6":                                     return "m"
        case "7", "9", "11", "13":                          return "7"
        case "m7", "m9", "m11", "m13", "m7b5":             return "m7"
        case "maj7", "maj9", "maj11", "maj13":              return "maj7"
        case "sus4", "7sus4":                               return "sus4"
        case "sus2", "7sus2":                               return "sus2"
        case "dim", "dim7":                                 return "m"
        default:                                            return nil
        }
    }

    private static func dynamicVoicings(root: String, suffix: String) -> [[Int]]? {
        guard let s = semitones[root],
              let q = qualityKey(suffix) else { return nil }
        let aFret = (s - 9 + 12) % 12
        let eFret = (s - 4 + 12) % 12
        var result: [[Int]] = []
        if let shape = aShapes[q] { result.append(barre(shape, at: aFret)) }
        if let shape = eShapes[q] { result.append(barre(shape, at: eFret)) }
        return result.isEmpty ? nil : result
    }

    // ────────────────────────────────────────────────────────────────

    // ♭ / ♯ Unicode → b / # (有些 app 輸出的是音樂符號而非 ASCII)
    private static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "♭", with: "b")
         .replacingOccurrences(of: "♯", with: "#")
    }

    // 全部把位列表
    private var allVoicings: [[Int]]? {
        let base = Self.normalize(symbol).components(separatedBy: "/").first ?? symbol
        // 1. 直查
        if let v = Self.library[base] { return v }
        guard !base.isEmpty, "ABCDEFG".contains(base.prefix(1)) else { return nil }
        let rootLen: Int = {
            guard base.count >= 2 else { return 1 }
            let c1 = base[base.index(base.startIndex, offsetBy: 1)]
            return (c1 == "b" || c1 == "#") ? 2 : 1
        }()
        let root   = String(base.prefix(rootLen))
        let suffix = String(base.dropFirst(rootLen))
        // 2. 同名異名
        let alt = Self.enharmonic[root]
        if let alt, let v = Self.library[alt + suffix] { return v }
        // 3. 後綴簡化 → 曲庫（保留多把位）
        for (from, to) in Self.suffixFallbacks where suffix == from {
            if let v = Self.library[root + to]       { return v }
            if let alt, let v = Self.library[alt + to] { return v }
        }
        // 4. 動態 barre 生成（涵蓋所有根音 + 常見和弦質）
        if let v = Self.dynamicVoicings(root: root, suffix: suffix) { return v }
        if let alt, let v = Self.dynamicVoicings(root: alt, suffix: suffix) { return v }
        // 5. 動態 + 後綴簡化
        for (from, to) in Self.suffixFallbacks where suffix == from {
            if let v = Self.dynamicVoicings(root: root, suffix: to) { return v }
            if let alt, let v = Self.dynamicVoicings(root: alt, suffix: to) { return v }
        }
        return nil
    }

    private var currentStrings: [Int]? {
        guard let v = allVoicings, !v.isEmpty else { return nil }
        return v[min(voicingIndex, v.count - 1)]
    }

    var body: some View {
        VStack(spacing: 3) {
            if let strings = currentStrings {
                Canvas { ctx, size in
                    Self.draw(ctx: ctx, size: size, strings: strings)
                }
                .frame(width: width, height: height)

                let count = allVoicings?.count ?? 0
                if count > 1 {
                    HStack(spacing: 0) {
                        Button {
                            voicingIndex = max(0, voicingIndex - 1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .frame(width: 36, height: 28)
                                .contentShape(Rectangle())
                        }
                        .disabled(voicingIndex == 0)

                        Text("\(voicingIndex + 1) / \(count)")
                            .frame(minWidth: 32)

                        Button {
                            voicingIndex = min(count - 1, voicingIndex + 1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .frame(width: 36, height: 28)
                                .contentShape(Rectangle())
                        }
                        .disabled(voicingIndex >= count - 1)
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.1))
                    Text("?").font(.system(size: 12)).foregroundStyle(Color.secondary)
                }
                .frame(width: width, height: height)
            }
        }
        .onChange(of: symbol) { voicingIndex = 0 }
    }

    // MARK: - Canvas 繪圖（橫式）
    private static func draw(ctx: GraphicsContext, size: CGSize, strings: [Int]) {
        let padL: CGFloat = 16
        let padR: CGFloat = 30
        let padT: CGFloat = 4
        let padB: CGFloat = 4
        let nStr = 6
        let nFret = 4

        let fw = size.width  - padL - padR
        let fh = size.height - padT - padB
        let fg = fw / CGFloat(nFret)
        let sg = fh / CGFloat(nStr - 1)

        let fx = (0...nFret).map { padL + CGFloat($0) * fg }
        // sy[0]=lowE（底），sy[5]=highE（頂）
        let sy = (0..<nStr).map { padT + fh - CGFloat($0) * sg }

        let played   = strings.filter { $0 > 0 }
        let baseFret = played.isEmpty ? 1 : (played.min()! <= 2 ? 1 : played.min()!)
        let dotR     = max(4.0, sg * 0.32)
        let indX     = padL - 9

        // Nut（粗）或把位起始線（細）
        var nut = Path()
        nut.move(to: CGPoint(x: fx[0], y: sy[nStr - 1] - 1))
        nut.addLine(to: CGPoint(x: fx[0], y: sy[0] + 1))
        ctx.stroke(nut, with: .color(.primary.opacity(0.85)),
                   lineWidth: baseFret == 1 ? 3 : 1)

        // 格線（縱）
        for col in 1...nFret {
            var p = Path()
            p.move(to:    CGPoint(x: fx[col], y: sy[nStr - 1]))
            p.addLine(to: CGPoint(x: fx[col], y: sy[0]))
            ctx.stroke(p, with: .color(.secondary.opacity(0.45)), lineWidth: 0.75)
        }

        // 弦線（橫）
        for y in sy {
            var p = Path()
            p.move(to:    CGPoint(x: fx[0], y: y))
            p.addLine(to: CGPoint(x: fx[nFret], y: y))
            ctx.stroke(p, with: .color(.secondary.opacity(0.45)), lineWidth: 0.75)
        }

        // 把位數字（右側）
        if baseFret > 1 {
            ctx.draw(
                Text("\(baseFret)fr")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.red),
                at: CGPoint(x: fx[nFret] + 15,
                            y: sy[0] + (sy[nStr - 1] - sy[0]) / 2)
            )
        }

        // 各弦狀態
        for (i, fretAbs) in strings.enumerated() {
            let y = sy[i]
            switch fretAbs {
            case -1:
                let d: CGFloat = 3
                for (dx1, dy1, dx2, dy2) in [(-d,-d,d,d),(d,-d,-d,d)] {
                    var p = Path()
                    p.move(to:    CGPoint(x: indX + dx1, y: y + dy1))
                    p.addLine(to: CGPoint(x: indX + dx2, y: y + dy2))
                    ctx.stroke(p, with: .color(.secondary), lineWidth: 1.5)
                }
            case 0:
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: indX - 4, y: y - 4, width: 8, height: 8)),
                    with: .color(.primary.opacity(0.75)), lineWidth: 1.5
                )
            default:
                let fretRel = fretAbs - baseFret + 1
                if fretRel >= 1 && fretRel <= nFret {
                    let cx = fx[fretRel - 1] + fg * 0.5
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: cx - dotR, y: y - dotR,
                                               width: dotR * 2, height: dotR * 2)),
                        with: .color(.primary)
                    )
                }
            }
        }
    }
}
