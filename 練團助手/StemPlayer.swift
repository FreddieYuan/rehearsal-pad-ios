import AVFoundation
import Combine
import Foundation
import MediaPlayer

/// 分軌播放器。
///
/// 六軌要「聽起來像同一次演奏」就不能各自 play() —— 用六個 AVAudioPlayer
/// 分別啟動會各差幾毫秒，鼓跟貝斯就散了。這裡用一個 AVAudioEngine，
/// 每軌一個 player node，全部 `play(at:)` 到同一個 host time，是取樣級對齊。
final class StemPlayer: ObservableObject {

    struct Track: Identifiable, Equatable {
        let id: String          // vocals / drums / bass / guitar / piano / other
        let name: String        // 顯示用中文
        let url: URL
        /// 這首歌要聽鍵盤該挑的那一軌。風琴曲會是 other 而不是 piano。
        var isKeyboardReference = false
    }

    /// 檔名 → 顯示名稱與排序。照樂團編制排，不是照字母。
    static let order: [(id: String, name: String)] = [
        ("vocals", "人聲"),
        ("drums", "鼓"),
        ("bass", "貝斯"),
        ("guitar", "吉他"),
        ("piano", "鍵盤"),
        ("other", "其他"),
    ]

    @Published private(set) var tracks: [Track] = []
    /// 現在載進來的是哪一首。
    ///
    /// 不要拿 tracks 的 id 來判斷「是不是同一首」—— Track.id 是軌名
    /// （vocals/drums/…），每首歌都一樣，那樣比永遠相等，換歌時根本不會重載，
    /// 結果就是跳到第二首卻還在播第一首。
    @Published private(set) var loadedProjectID: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var soloed: Set<String> = []
    @Published private(set) var muted: Set<String> = []
    @Published var volumes: [String: Float] = [:]

    private let engine = AVAudioEngine()
    private var nodes: [String: AVAudioPlayerNode] = [:]
    private var files: [String: AVAudioFile] = [:]
    private var sampleRate: Double = 44_100
    /// 這一輪排程是從第幾個 frame 開始的，算播放位置要加回去。
    private var startFrame: AVAudioFramePosition = 0
    private var ticker: AnyCancellable?
    /// 鎖屏 / 耳機控制要顯示的曲目資訊。
    private var nowPlayingTitle = ""
    private var nowPlayingArtist = ""
    private var remoteCommandsWired = false
    private var audioObservers: [NSObjectProtocol] = []
    /// 被中斷（來電、Siri、別的 App 搶走音訊）之前是不是正在播。
    private var wasPlayingBeforeInterruption = false
    /// 鎖屏資訊上次更新的時間。ticker 每 0.1 秒跑一次，
    /// 每次都寫 nowPlayingInfo 會讓鎖屏畫面變鈍。
    private var lastNowPlayingPush: CFTimeInterval = 0

    var hasStems: Bool { !tracks.isEmpty }

    // MARK: - 載入

    func load(
        tracks newTracks: [Track],
        projectID: String? = nil,
        title: String = "",
        artist: String = ""
    ) {
        unload()
        loadedProjectID = projectID
        nowPlayingTitle = title
        nowPlayingArtist = artist
        guard !newTracks.isEmpty else { return }

        configureSession()
        wireAudioNotifications()

        var loaded: [Track] = []
        var maxLength: AVAudioFramePosition = 0

        for track in newTracks {
            guard let file = try? AVAudioFile(forReading: track.url) else { continue }
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
            nodes[track.id] = node
            files[track.id] = file
            sampleRate = file.processingFormat.sampleRate
            maxLength = max(maxLength, file.length)
            loaded.append(track)
            if volumes[track.id] == nil { volumes[track.id] = 1 }
        }

        guard !loaded.isEmpty else { return }
        tracks = loaded
        duration = Double(maxLength) / sampleRate
        applyMix()

        engine.prepare()
        scheduleAll(from: 0)
        wireRemoteCommands()
        updateNowPlaying()
    }

    func unload() {
        stopTicker()
        for node in nodes.values {
            node.stop()
            engine.detach(node)
        }
        if engine.isRunning { engine.stop() }
        nodes.removeAll()
        files.removeAll()
        tracks = []
        loadedProjectID = nil
        isPlaying = false
        elapsed = 0
        duration = 0
        startFrame = 0
        soloed.removeAll()
        muted.removeAll()
    }

    private func configureSession() {
        // 沒設 .playback 的話，iPad 側邊靜音鍵一撥就沒聲音了。
        // 在 iPhone 上這個 category 再加上 Info.plist 的 UIBackgroundModes=audio，
        // 才能鎖屏後繼續播 —— 「在路上聽」少了這兩者之一都不成立。
        //
        // 這支必須在每次 play() 都呼叫，不能只在 load() 呼叫一次：
        // App 在背景暫停一陣子之後，系統會把 session 收回去，
        // 這時從鎖屏按播放，engine.start() 會直接丟例外，看起來就是「按了沒反應」。
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    /// 重新接線。
    ///
    /// 換輸出裝置（插拔耳機、連上藍牙、AirPods 從手機跳到手錶）會改變
    /// mainMixerNode 的格式，舊的連線就失效了，engine 也已經被系統停掉。
    /// 在路上聽的時候這件事一直在發生。
    private func reconnectNodes() {
        for (id, node) in nodes {
            guard let file = files[id] else { continue }
            engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
        }
        applyMix()
        engine.prepare()
    }

    /// 從目前位置把整條鏈重新架起來。中斷結束、換線、媒體服務重置都走這裡。
    private func rebuild(resume: Bool) {
        let position = elapsed
        for node in nodes.values { node.stop() }
        if engine.isRunning { engine.stop() }
        isPlaying = false
        stopTicker()

        configureSession()
        reconnectNodes()
        startFrame = AVAudioFramePosition(position * sampleRate)
        elapsed = position
        scheduleAll(from: startFrame)
        pushNowPlaying(force: true)
        if resume { play() }
    }

    private func wireAudioNotifications() {
        guard audioObservers.isEmpty else { return }
        let center = NotificationCenter.default

        // 來電、Siri、別的 App 搶走音訊。結束後系統不會自己幫你接回來。
        audioObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                self.wasPlayingBeforeInterruption = self.isPlaying
                self.isPlaying = false
                self.stopTicker()
                self.pushNowPlaying(force: true)
            case .ended:
                let options = AVAudioSession.InterruptionOptions(
                    rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                self.rebuild(resume: options.contains(.shouldResume)
                             && self.wasPlayingBeforeInterruption)
                self.wasPlayingBeforeInterruption = false
            @unknown default:
                break
            }
        })

        // 輸出裝置換了。engine 這時已經停了，連線也要重接。
        audioObservers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, !self.tracks.isEmpty else { return }
            self.rebuild(resume: self.isPlaying)
        })

        // 系統音訊服務整個重置（少見，但一發生就全毀）。
        audioObservers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, !self.tracks.isEmpty else { return }
            self.rebuild(resume: self.isPlaying)
        })
    }

    deinit {
        audioObservers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - 鎖屏 / 耳機控制

    private func wireRemoteCommands() {
        guard !remoteCommandsWired else { return }
        remoteCommandsWired = true
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self, !self.tracks.isEmpty else { return .noSuchContent }
            self.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.toggle()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: event.positionTime)
            return .success
        }
        // 上一首/下一首在這裡沒有意義（一次只載一首），明確關掉比留著沒反應好。
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    private func updateNowPlaying() { pushNowPlaying(force: true) }

    /// ticker 每 0.1 秒跑一次，但鎖屏資訊不需要那麼頻繁 ——
    /// 每秒寫 10 次 nowPlayingInfo 會讓鎖屏畫面變鈍，系統自己會內插進度。
    private func pushNowPlaying(force: Bool = false) {
        let now = CFAbsoluteTimeGetCurrent()
        if !force && now - lastNowPlayingPush < 0.9 { return }
        lastNowPlayingPush = now

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlayingTitle.isEmpty ? "練團助手" : nowPlayingTitle,
            MPMediaItemPropertyArtist: nowPlayingArtist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if tracks.isEmpty { info = [:] }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - 播放控制

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard !tracks.isEmpty, !isPlaying else { return }
        // 每次都重新要一次 session —— 背景待久了系統會收回去。
        configureSession()
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                // 從鎖屏被叫醒時最常走到這裡：route 換過、連線失效。
                // 重接一次再試；還是起不來才真的放棄。
                reconnectNodes()
                configureSession()
                guard (try? engine.start()) != nil else { return }
            }
        }
        // 全部對同一個 host time 起跑；那 0.08 秒是留給排程本身的餘裕。
        let startAt = AVAudioTime(hostTime: mach_absolute_time()
            + AVAudioTime.hostTime(forSeconds: 0.08))
        for node in nodes.values { node.play(at: startAt) }
        isPlaying = true
        startTicker()
        updateNowPlaying()
    }

    func pause() {
        guard isPlaying else { return }
        for node in nodes.values { node.pause() }
        engine.pause()
        isPlaying = false
        stopTicker()
        updateNowPlaying()
    }

    func restart() {
        seek(to: 0)
    }

    func seek(to seconds: Double) {
        let wasPlaying = isPlaying
        pause()
        for node in nodes.values { node.stop() }
        let clamped = min(max(seconds, 0), max(duration - 0.05, 0))
        startFrame = AVAudioFramePosition(clamped * sampleRate)
        elapsed = clamped
        scheduleAll(from: startFrame)
        updateNowPlaying()
        if wasPlaying { play() }
    }

    private func scheduleAll(from frame: AVAudioFramePosition) {
        for (id, file) in files {
            guard let node = nodes[id] else { continue }
            let remaining = file.length - frame
            guard remaining > 0 else { continue }
            node.scheduleSegment(
                file,
                startingFrame: frame,
                frameCount: AVAudioFrameCount(remaining),
                at: nil
            )
        }
    }

    // MARK: - 混音

    func toggleMute(_ id: String) {
        if muted.contains(id) { muted.remove(id) } else { muted.insert(id) }
        applyMix()
    }

    func toggleSolo(_ id: String) {
        if soloed.contains(id) { soloed.remove(id) } else { soloed.insert(id) }
        applyMix()
    }

    func setVolume(_ value: Float, for id: String) {
        volumes[id] = value
        applyMix()
    }

    func isAudible(_ id: String) -> Bool {
        if muted.contains(id) { return false }
        if !soloed.isEmpty { return soloed.contains(id) }
        return true
    }

    /// solo 一旦有人按下，其他軌就靜音 —— 跟混音台一樣的規矩。
    private func applyMix() {
        for track in tracks {
            nodes[track.id]?.volume = isAudible(track.id) ? (volumes[track.id] ?? 1) : 0
        }
    }

    // MARK: - 播放位置

    private func startTicker() {
        ticker = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.updateElapsed() }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func updateElapsed() {
        guard let node = nodes.values.first,
              let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else { return }
        let position = Double(startFrame + playerTime.sampleTime) / playerTime.sampleRate
        elapsed = min(max(position, 0), duration)
        pushNowPlaying()
        if elapsed >= duration - 0.05 {
            pause()
            seek(to: 0)
        }
    }
}
