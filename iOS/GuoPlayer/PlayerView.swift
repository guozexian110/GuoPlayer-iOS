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
    @State private var attemptedFallback = false
    init(item: MediaItem, playlist: [MediaItem], preferredSourceId: String? = nil) {
        self.item = item; self.playlist = playlist; self.preferredSourceId = preferredSourceId; _current = State(initialValue: item)
    }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                HStack { Button { close() } label: { Label("返回", systemImage: "chevron.down") }; Spacer(); Text(current.name).lineLimit(1); Spacer(); Image(systemName: "airplayvideo") }
                    .font(.subheadline.bold()).padding(.horizontal)
                NativePlayer(player: player).frame(maxWidth: .infinity, maxHeight: .infinity)
                if loading { ProgressView("正在读取播放信息") }
                if let error {
                    VStack { Text(error).foregroundStyle(.red); Button("尝试 Emby 转码") { forceTranscode = true; startPlayback() }.buttonStyle(.borderedProminent) }
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
                            Menu { ForEach(info.mediaSources) { candidate in Button(candidate.container?.uppercased() ?? candidate.id) { source = candidate; startPlayback() } } } label: { Image(systemName: "server.rack") }
                        }
                        if nextEpisode != nil { Button { advance() } label: { Image(systemName: "forward.end.fill") } }
                    }.font(.title3).buttonStyle(.plain)
                    HStack(spacing: 22) {
                        Menu {
                            Button("自动") { chosenAudio = nil; startPlayback() }
                            ForEach(source?.mediaStreams.filter { $0.type == "Audio" } ?? []) { track in
                                Button(track.displayTitle ?? track.language ?? "音轨 \(track.index)") { chosenAudio = track.index; startPlayback() }
                            }
                        } label: { Label("音轨", systemImage: "waveform") }
                        Menu {
                            Button("关闭") { chosenSubtitle = -1; startPlayback() }
                            Button("自动") { chosenSubtitle = nil; startPlayback() }
                            ForEach(source?.mediaStreams.filter { $0.type == "Subtitle" } ?? []) { track in
                                Button(track.displayTitle ?? track.language ?? "字幕 \(track.index)") { chosenSubtitle = track.index; forceTranscode = true; startPlayback() }
                            }
                        } label: { Label("字幕", systemImage: "captions.bubble") }
                        Button(forceTranscode ? "转码中" : "切换转码") { forceTranscode.toggle(); startPlayback() }
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
            info = result; source = first
            let container = first.container?.lowercased() ?? ""
            forceTranscode = !((first.supportsDirectPlay == true && ["mp4", "m4v", "mov"].contains(container)) || first.canDirectStreamOnApple)
            startPlayback()
        } catch { self.error = error.localizedDescription }
        loading = false
    }
    private func startPlayback() {
        guard let server = store.server(for: current), let token = TokenVault.read(server.id), let source else { return }
        report("/Stopped")
        let url = store.api.streamURL(server, token: token, item: current, source: source, forceTranscode: forceTranscode, audio: chosenAudio, subtitle: chosenSubtitle)
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)
        let resume = position > 0 ? position : Double(current.userData?.playbackPositionTicks ?? 0) / 10_000_000
        if resume > 10 { player.seek(to: CMTime(seconds: resume, preferredTimescale: 600)) }
        player.play(); player.rate = speed
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 2), queue: .main) { time in
            position = time.seconds.isFinite ? time.seconds : 0
            let total = player.currentItem?.duration.seconds ?? 0
            duration = total.isFinite ? total : 0
            if player.currentItem === playerItem && playerItem.status == .failed {
                if !forceTranscode && !attemptedFallback {
                    attemptedFallback = true
                    forceTranscode = true
                    startPlayback()
                } else {
                    error = playerItem.error?.localizedDescription ?? "播放失败，请检查转码权限或切换片源"
                }
            }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { _ in
            report("/Stopped")
            advance()
        }
        report("")
        Task { while !Task.isCancelled && player.currentItem === playerItem { try? await Task.sleep(for: .seconds(10)); if player.currentItem === playerItem { report("/Progress") } } }
    }
    private func report(_ phase: String) {
        guard let server = store.server(for: current), let token = TokenVault.read(server.id), let source else { return }
        let ticks = Int64(max(position, 0) * 10_000_000)
        let media = current; let session = info?.playSessionId; let paused = player.rate == 0; let method = forceTranscode ? "Transcode" : (source.supportsDirectPlay == true ? "DirectPlay" : "DirectStream")
        Task { await store.api.report(server, token: token, item: media, source: source, session: session, position: ticks, phase: phase, paused: paused, method: method) }
    }
    private func advance() {
        guard let next = nextEpisode else { return }
        report("/Stopped"); current = next; info = nil; source = nil; position = 0; attemptedFallback = false; Task { await prepare() }
    }
    private func stop() {
        report("/Stopped")
        player.pause(); player.replaceCurrentItem(with: nil)
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
    }
    private func close() { stop(); dismiss() }
}
