import SwiftUI
import VLCKitSPM

struct VLCTrack: Identifiable {
    let id: Int32
    let name: String
}

// VLCKit stays on the main thread; only this adapter knows its track identifiers.
@MainActor final class VLCPlayback: ObservableObject {
    let player = VLCMediaPlayer(options: ["--quiet"])
    @Published private(set) var state = "stopped"
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var playing = false
    @Published private(set) var audioTracks: [VLCTrack] = []
    @Published private(set) var subtitleTracks: [VLCTrack] = []
    private var poll: Task<Void, Never>?
    private var resume: Double = 0
    private var resumed = false
    private(set) var lastHeaders: [String: String] = [:]

    func open(_ url: URL, headers: [String: String], resume: Double, speed: Float) {
        stop()
        self.resume = resume; resumed = false; lastHeaders = headers
        let media = VLCMedia(url: url)
        #if targetEnvironment(simulator)
        // Simulator has no physical iPhone VideoToolbox decoder.
        media.addOption(":codec=avcodec")
        media.addOption(":avcodec-hw=none")
        #endif
        media.addOption(":network-caching=1500")
        media.addOption(":http-user-agent=GuoPlayer/iOS")
        // Disable verbose libVLC logs: stream URLs can contain access tokens.
        for (key, value) in headers {
            switch key.lowercased() {
            case "user-agent": media.addOption(":http-user-agent=\(value)")
            case "referer": media.addOption(":http-referrer=\(value)")
            case "cookie": media.addOption(":http-cookie=\(value)")
            default: break
            }
        }
        player.media = media
        player.rate = speed
        state = "opening"
        player.play()
        poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                self.update()
            }
        }
    }
    private func tracks(_ ids: [Any]?, _ names: [Any]?) -> [VLCTrack] {
        zip(ids ?? [], names ?? []).compactMap { id, name in
            guard let number = id as? NSNumber else { return nil }
            return VLCTrack(id: number.int32Value, name: String(describing: name))
        }
    }
    private func update() {
        playing = player.isPlaying
        duration = max(0, Double(player.media?.length.intValue ?? 0) / 1000)
        if !resumed, player.isSeekable, player.state == .playing {
            resumed = true
            if resume > 0 { seek(resume) }
        }
        position = max(0, Double(player.time.intValue) / 1000)
        audioTracks = tracks(player.audioTrackIndexes, player.audioTrackNames).filter { $0.id >= 0 }
        subtitleTracks = tracks(player.videoSubTitlesIndexes, player.videoSubTitlesNames).filter { $0.id >= 0 }
        switch player.state {
        case .playing: state = "playing"
        case .paused: state = "paused"
        case .ended: state = "ended"
        case .error: state = "error"
        case .opening: state = "opening"
        case .buffering: state = "buffering"
        default: break
        }
    }
    func seek(_ seconds: Double) {
        player.time = VLCTime(int: Int32(min(Double(Int32.max), max(0, seconds * 1000))))
    }
    func toggle() { player.isPlaying ? player.pause() : player.play() }
    func setRate(_ value: Float) { player.rate = value }
    func audio(_ id: Int32) { player.currentAudioTrackIndex = id }
    func subtitle(_ id: Int32) { player.currentVideoSubTitleIndex = id }
    func externalSubtitle(_ url: URL) { _ = player.addPlaybackSlave(url, type: .subtitle, enforce: true) }
    func stop() {
        poll?.cancel(); poll = nil
        player.stop(); player.media = nil
        state = "stopped"; playing = false; position = 0; duration = 0
        audioTracks = []; subtitleTracks = []
    }
}

struct VLCVideo: UIViewRepresentable {
    @ObservedObject var playback: VLCPlayback
    func makeUIView(context: Context) -> UIView {
        let view = UIView(); view.backgroundColor = .black
        playback.player.drawable = view
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        // libVLC renders into the same UIView for its lifetime. Clock updates
        // must not query/rebind the output surface while UIKit draws it.
    }
    static func dismantleUIView(_ view: UIView, coordinator: ()) { }
}

#if DEBUG
// Simulator acceptance test uses the same adapter and rendered video surface.
struct VLCSmokeView: View {
    @StateObject private var playback = VLCPlayback()
    private func log(_ value: String) { FileHandle.standardError.write(Data((value + "\n").utf8)) }
    var body: some View {
        VLCVideo(playback: playback).ignoresSafeArea().task {
            log("VLC smoke: task started")
            var result: [String: Any] = [:]
            do {
                guard let value = ProcessInfo.processInfo.environment["GUOPLAYER_VLC_TEST_URL"], let url = URL(string: value) else { throw EmbyError.message("Missing test URL") }
                log("VLC smoke: opening fixture")
                playback.open(url, headers: [:], resume: 0, speed: 1)
                log("VLC smoke: waiting for frames")
                for _ in 0..<160 {
                    try await Task.sleep(for: .milliseconds(250))
                    if playback.position > 2 && (playback.player.media?.statistics.decodedVideo ?? 0) > 5 { break }
                }
                log("VLC smoke: decode wait finished")
                guard let media = playback.player.media else { throw EmbyError.message("VLC has no media") }
                let stats = media.statistics
                result["decodedVideo"] = stats.decodedVideo
                result["decodedAudio"] = stats.decodedAudio
                result["displayedPictures"] = stats.displayedPictures
                result["duration"] = playback.duration
                result["audioTracks"] = playback.audioTracks.count
                result["subtitleTracks"] = playback.subtitleTracks.count
                guard stats.decodedVideo > 5, stats.decodedAudio > 5, stats.displayedPictures > 0, playback.audioTracks.count >= 2, !playback.subtitleTracks.isEmpty else { throw EmbyError.message("Decode or track discovery failed") }
                let lastAudio = playback.audioTracks.last!.id
                log("VLC smoke: selecting audio")
                playback.audio(lastAudio)
                playback.subtitle(playback.subtitleTracks.first!.id)
                playback.setRate(1.5)
                log("VLC smoke: seeking")
                playback.seek(8)
                log("VLC smoke: seek issued")
                try await Task.sleep(for: .seconds(2))
                result["seekPosition"] = playback.position
                result["audioSelected"] = playback.player.currentAudioTrackIndex == lastAudio
                result["subtitleSelected"] = playback.player.currentVideoSubTitleIndex >= 0
                let external = url.deletingLastPathComponent().appendingPathComponent("fixture.srt")
                log("VLC smoke: external subtitle")
                playback.externalSubtitle(external)
                log("VLC smoke: external subtitle issued")
                try await Task.sleep(for: .seconds(1))
                result["externalSubtitleTracks"] = playback.subtitleTracks.count
                result["externalSubtitleSelected"] = playback.player.currentVideoSubTitleIndex >= 0 && playback.subtitleTracks.count >= 2
                log("VLC smoke: pause/resume")
                playback.toggle()
                try await Task.sleep(for: .seconds(1))
                result["paused"] = !playback.player.isPlaying
                log("VLC smoke: pause/resume")
                playback.toggle()
                try await Task.sleep(for: .seconds(1))
                result["resumed"] = playback.player.isPlaying
                result["rate"] = playback.player.rate
                result["pass"] = playback.position >= 8 && (result["audioSelected"] as? Bool == true) && (result["subtitleSelected"] as? Bool == true) && (result["externalSubtitleSelected"] as? Bool == true) && (result["paused"] as? Bool == true) && playback.player.isPlaying
            } catch { result["pass"] = false; result["error"] = error.localizedDescription }
            let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("vlc-smoke.json")
            do {
                try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
                log("VLC smoke: report saved")
            } catch { log("VLC smoke: report serialization failed \(error)") }
        }
    }
}
#endif
