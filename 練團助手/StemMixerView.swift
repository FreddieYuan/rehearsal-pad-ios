import SwiftUI

/// 分軌試聽台。排練時想聽「鍵盤到底在彈什麼」，把其他軌 solo 掉就好。
struct StemMixerView: View {
    @ObservedObject var player: StemPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            transport
            Divider()
            ForEach(player.tracks) { track in
                trackRow(track)
            }
            if let reference = player.tracks.first(where: { $0.isKeyboardReference }) {
                Button {
                    // 一鍵只聽鍵盤那一軌。
                    for id in Array(player.soloed) where id != reference.id {
                        player.toggleSolo(id)
                    }
                    if !player.soloed.contains(reference.id) {
                        player.toggleSolo(reference.id)
                    }
                } label: {
                    // 鋼琴曲就在「鍵盤」軌，不用多說；風琴曲在「其他」軌，得講清楚。
                    Label(
                        reference.id == "piano" ? "只聽鍵盤" : "只聽鍵盤（在「\(reference.name)」軌）",
                        systemImage: "pianokeys.inverse"
                    )
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
            if !player.soloed.isEmpty {
                Button {
                    for id in Array(player.soloed) { player.toggleSolo(id) }
                } label: {
                    Label("取消所有 Solo", systemImage: "xmark.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 32, height: 26)
            }
            .buttonStyle(.borderedProminent)

            Button {
                player.restart()
            } label: {
                Image(systemName: "backward.end.fill")
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.bordered)

            Text(timecode(player.elapsed))
                .font(.subheadline.monospacedDigit().weight(.semibold))

            Slider(
                value: Binding(
                    get: { player.elapsed },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 0.1)
            )

            Text(timecode(player.duration))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func trackRow(_ track: StemPlayer.Track) -> some View {
        HStack(spacing: 10) {
            Text(track.name)
                .font(.subheadline.weight(.semibold))
                .frame(width: 52, alignment: .leading)
                .foregroundStyle(player.isAudible(track.id) ? Color.primary : Color.secondary)

            // 風琴曲的鍵盤不在「鍵盤」軌裡，標出來才不會 solo 到空的。
            if track.isKeyboardReference {
                Label("鍵盤在這", systemImage: "pianokeys")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.sheetChord)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.sheetChord.opacity(0.14), in: Capsule())
            }

            Button("M") { player.toggleMute(track.id) }
                .font(.caption.weight(.black))
                .buttonStyle(.bordered)
                .tint(player.muted.contains(track.id) ? .red : .secondary)

            Button("S") { player.toggleSolo(track.id) }
                .font(.caption.weight(.black))
                .buttonStyle(.bordered)
                .tint(player.soloed.contains(track.id) ? .yellow : .secondary)

            Slider(
                value: Binding(
                    get: { player.volumes[track.id] ?? 1 },
                    set: { player.setVolume($0, for: track.id) }
                ),
                in: 0...1.5
            )
            .disabled(!player.isAudible(track.id))
        }
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
