import SwiftUI
import AVKit
import AVFoundation

struct NativePlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.showsPlaybackControls = true
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) { controller.player = player }
}

struct PlayerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem
    let playlist: [MediaItem]
    let preferredSourceId: String?
    @State private var current: MediaItem
    @State private var player = AVPlayer()
    @State private var info: PlaybackInfo?
    @State private var source: PlaybackSource?
    @State private var forceTranscode = false
    @State private var chosenAudio: Int?
    @State private var chosenSubtitle: Int?
    @State private var speed: Float = 1
    @State private var error: String?
    @State private var loading = true
    @State private var position: Double = 0
    @State private var duration: Double = 0
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?
    @State private var failureObserver: NSObjectProtocol?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var startupTask: Task<Void, Never>?
    @State private var connectionTask: Task<Void, Never>?
    @State private var connectionId = UUID()
    @State private var progressTask: Task<Void, Never>?
    @State private var hasStarted = false
    @State private var switchingPlayback = false
    @State private var attemptedFallback = false
    @State private var attemptedAlternateHLS = false
    @State private var urlVariantIndex = 0
    init(item: MediaItem, playlist: [MediaItem], preferredSourceId: String? = nil) {
        self.item = item; self.playlist = playlist; self.preferredSourceId = preferredSourceId; _current = State(initialValue: item)
    }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                HStack { Button { close() } label: { Label("返回", systemImage: "chevron.down") }; Spacer(); Text(current.name).lineLimit(1); Spacer(); Image(systemName: "airplayvideo") }
                    .font(.subheadline.bold()).padding(.horizontal)
                ZStack {
                    NativePlayer(player: player).frame(maxWidth: .infinity, maxHeight: .infinity)
                    if loading { ProgressView("正在连接视频").tint(.cyan).padding(18).background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12)) }
                    if let error {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle").font(.title2)
                            Text(error).multilineTextAlignment(.center)
                            Button("尝试 Emby 转码") { forceTranscode = true; attemptedAlternateHLS = false; urlVariantIndex = 0; startPlayback() }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(20).frame(maxWidth: 310)
                        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                VStack(spacing: 10) {
                    Slider(value: Binding(get: { position }, set: { position = $0 }), in: 0...max(duration, 1), onEditingChanged: { editing in if !editing { player.seek(to: CMTime(seconds: position, preferredTimescale: 600)); report("/Progress") } })
                    HStack { Text(time(position)); Spacer(); Text(time(duration)) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    HStack(spacing: 20) {
                        Button { player.seek(to: CMTime(seconds: max(position - 10, 0), preferredTimescale: 600)) } label: { Image(systemName: "gobackward.10") }
                        Button { player.rate == 0 ? player.play() : player.pause(); report("/Progress") } label: { Image(systemName: player.rate == 0 ? "play.fill" : "pause.fill") }
                        Button { player.seek(to: CMTime(seconds: position + 10, preferredTimescale: 600)) } label: { Image(systemName: "goforward.10") }
                        Menu { ForEach([0.5, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in Button("\(value.formatted())×") { speed = Float(value); player.rate = speed } } } label: { Text("\(speed.formatted())×") }
                        if let info {
                            Menu { ForEach(info.mediaSources) { candidate in Button(candidate.container?.uppercased() ?? candidate.id) { source = candidate; urlVariantIndex = 0; chosenAudio = nil; chosenSubtitle = nil; attemptedFallback = false; attemptedAlternateHLS = false; forceTranscode = !(candidate.canDirectPlayOnApple || candidate.canDirectStreamOnApple || candidate.canTryRemoteOnApple); startPlayback() } } } label: { Image(systemName: "server.rack") }
                        }
                        if nextEpisode != nil { Button { advance() } label: { Image(systemName: "forward.end.fill") } }
                    }.font(.title3).buttonStyle(.plain)
                    HStack(spacing: 22) {
                        Menu {
                            Button("自动") { chosenAudio = nil; urlVariantIndex = 0; startPlayback() }
                            ForEach(source?.mediaStreams.filter { $0.type == "Audio" } ?? []) { track in
                                Button(track.displayTitle ?? track.language ?? "音轨 \(track.index)") { chosenAudio = track.index; forceTranscode = true; attemptedAlternateHLS = false; urlVariantIndex = 0; startPlayback() }
                            }
                        } label: { Label("音轨", systemImage: "waveform") }
                        Menu {
                            Button("关闭") { chosenSubtitle = -1; urlVariantIndex = 0; startPlayback() }
                            Button("自动") { chosenSubtitle = nil; urlVariantIndex = 0; startPlayback() }
                            ForEach(source?.mediaStreams.filter { $0.type == "Subtitle" } ?? []) { track in
                                Button(track.displayTitle ?? track.language ?? "字幕 \(track.index)") { chosenSubtitle = track.index; forceTranscode = true; attemptedAlternateHLS = false; urlVariantIndex = 0; startPlayback() }
                            }
                        } label: { Label("字幕", systemImage: "captions.bubble") }
                        Button(forceTranscode ? "转码中" : "切换转码") { forceTranscode.toggle(); urlVariantIndex = 0; attemptedFallback = false; attemptedAlternateHLS = false; startPlayback() }
                    }.font(.caption).buttonStyle(.bordered)
                }.padding(.horizontal, 18).padding(.bottom, 10)
            }
        }
        .task { await prepare() }
        .onDisappear { stop() }
    }
    private var nextEpisode: MediaItem? {
        guard let index = playlist.firstIndex(of: current), index + 1 < playlist.count else { return nil }
        return playlist[index + 1]
    }
    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = Int(seconds)
        return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
    private func prepare() async {
        loading = true; error = nil
        guard let server = store.server(for: current), let token = TokenVault.read(server.id) else { error = "服务器或登录令牌不可用"; loading = false; return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            let result = try await store.api.playback(server, token: token, item: current)
            guard let first = preferredSourceId.flatMap({ selected in result.mediaSources.first(where: { $0.id == selected }) }) ?? result.mediaSources.first else { throw EmbyError.message("服务器没有可播放片源") }
            info = result; source = first; urlVariantIndex = 0; attemptedFallback = false; attemptedAlternateHLS = false
            forceTranscode = !(first.canDirectPlayOnApple || first.canDirectStreamOnApple || first.canTryRemoteOnApple)
            startPlayback()
        } catch { self.error = error.localizedDescription; loading = false }
    }
    private func startPlayback() {
        guard let server = store.server(for: current), let token = TokenVault.read(server.id), let source else { return }
        connectionTask?.cancel()
        connectionId = UUID()
        player.pause(); player.replaceCurrentItem(with: nil)
        startupTask?.cancel()
        progressTask?.cancel()
        switchingPlayback = false
        statusObserver?.invalidate()
        statusObserver = nil
        loading = true
        error = nil
        if hasStarted { report("/Stopped") }; hasStarted = false
        let resume = position > 0 ? position : Double(current.userData?.playbackPositionTicks ?? 0) / 10_000_000
        let urls = store.api.streamURLs(server, token: token, item: current, source: source, forceTranscode: forceTranscode, audio: chosenAudio, subtitle: chosenSubtitle, sessionId: info?.playSessionId, preferServerTranscodingURL: !attemptedAlternateHLS)
        let generation = connectionId
        connectionTask = Task { @MainActor in
            do {
                let url = try await store.api.resolveStreamURL(Array(urls.dropFirst(min(urlVariantIndex, urls.count - 1))), headers: source.requiredHttpHeaders ?? [:])
                guard !Task.isCancelled, generation == connectionId else { return }
                urlVariantIndex = urls.firstIndex(of: url) ?? 0
                attachPlayback(url: url, resume: resume)
            } catch {
                guard !Task.isCancelled, generation == connectionId else { return }
                urlVariantIndex = urls.count - 1
                handlePlaybackFailure(error.localizedDescription)
            }
        }
    }
    private func attachPlayback(url: URL, resume: Double) {
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": source?.requiredHttpHeaders ?? [:]])
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)
        player.play()
        statusObserver = playerItem.observe(\.status, options: [.initial, .new]) { observed, _ in
            DispatchQueue.main.async {
                guard player.currentItem === playerItem else { return }
                switch observed.status {
                case .readyToPlay:
                    loading = false
                    if resume > 0 { player.seek(to: CMTime(seconds: resume, preferredTimescale: 600)) }
                    player.rate = speed
                    if !hasStarted { hasStarted = true; report("") }
                case .failed:
                    let status = observed.errorLog()?.events.last?.errorStatusCode ?? 0
                    handlePlaybackFailure((400...599).contains(status) ? "视频服务器返回 HTTP \(status)" : observed.error?.localizedDescription)
                default: break
                }
            }
        }
        startupTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, player.currentItem === playerItem,
                  loading || player.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }
            handlePlaybackFailure("视频连接超时")
        }
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 2), queue: .main) { time in
            if hasStarted && time.seconds.isFinite { position = time.seconds }
            let total = player.currentItem?.duration.seconds ?? 0
            duration = total.isFinite ? total : 0
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { _ in
            report("/Stopped")
            advance()
        }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: playerItem, queue: .main) { notification in
            guard player.currentItem === playerItem else { return }
            let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
            handlePlaybackFailure(message)
        }
        progressTask = Task { while !Task.isCancelled && player.currentItem === playerItem { try? await Task.sleep(for: .seconds(10)); if !Task.isCancelled && hasStarted && player.currentItem === playerItem { report("/Progress") } } }
    }
    private func handlePlaybackFailure(_ detail: String?) {
        guard !switchingPlayback else { return }
        switchingPlayback = true
        startupTask?.cancel()
        loading = false
        if let server = store.server(for: current), let token = TokenVault.read(server.id), let source,
           urlVariantIndex + 1 < store.api.streamURLs(server, token: token, item: current, source: source,
               forceTranscode: forceTranscode, audio: chosenAudio, subtitle: chosenSubtitle,
               sessionId: info?.playSessionId, preferServerTranscodingURL: !attemptedAlternateHLS).count {
            urlVariantIndex += 1
            startPlayback()
        } else if !forceTranscode && !attemptedFallback {
            attemptedFallback = true
            forceTranscode = true
            urlVariantIndex = 0
            startPlayback()
        } else if forceTranscode && !attemptedAlternateHLS && source?.transcodingUrl != nil {
            attemptedAlternateHLS = true
            urlVariantIndex = 0
            startPlayback()
        } else {
            player.pause()
            let guidance = detail?.contains("404") == true ? "请确认服务器地址、端口和子路径；该片源地址可能已失效。" : "请检查片源可用性与服务器转码权限。"
            error = "播放失败：\(detail ?? "服务器未返回可播放的视频")。\(guidance)"
        }
    }
    private func report(_ phase: String) {
        guard let server = store.server(for: current), let token = TokenVault.read(server.id), let source else { return }
        let ticks = Int64(max(position, 0) * 10_000_000)
        let media = current; let session = info?.playSessionId; let paused = player.rate == 0; let method = forceTranscode ? "Transcode" : (source.supportsDirectPlay == true ? "DirectPlay" : "DirectStream")
        Task { await store.api.report(server, token: token, item: media, source: source, session: session, position: ticks, phase: phase, paused: paused, method: method) }
    }
    private func advance() {
        guard let next = nextEpisode else { return }
        report("/Stopped"); current = next; info = nil; source = nil; position = 0; attemptedFallback = false; attemptedAlternateHLS = false; urlVariantIndex = 0; Task { await prepare() }
    }
    private func stop() {
        report("/Stopped")
        connectionTask?.cancel(); connectionTask = nil; connectionId = UUID()
        startupTask?.cancel(); startupTask = nil
        progressTask?.cancel(); progressTask = nil
        statusObserver?.invalidate(); statusObserver = nil
        player.pause(); player.replaceCurrentItem(with: nil)
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver); self.failureObserver = nil }
    }
    private func close() { stop(); dismiss() }
}
