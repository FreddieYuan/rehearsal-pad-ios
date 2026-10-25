import AVFoundation
import Foundation
import Combine

final class AudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var title = "No audio"

    private var player: AVAudioPlayer?

    func load(url: URL?) {
        stop()
        guard let url else {
            title = "No audio"
            return
        }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            title = url.lastPathComponent
        } catch {
            title = "Audio unavailable"
            player = nil
        }
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }
}
