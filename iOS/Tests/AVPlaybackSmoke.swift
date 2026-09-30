import Foundation
import AVFoundation
import CoreVideo

// Generate our own video, serve it over HTTP and exercise AVPlayer with EmbyAPI's URL.
// This verifies AVFoundation transport/decoding, not a user's Emby server or device.
@main struct AVPlaybackSmoke {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("fixture.mp4")
        let writer = try AVAssetWriter(outputURL: file, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? EmbyError.message("Cannot write fixture") }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<120 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            var pixel: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32ARGB, nil, &pixel) == kCVReturnSuccess, let pixel else { throw EmbyError.message("Cannot allocate frame") }
            CVPixelBufferLockBaseAddress(pixel, [])
            memset(CVPixelBufferGetBaseAddress(pixel), Int32(frame % 255), CVPixelBufferGetDataSize(pixel))
            CVPixelBufferUnlockBaseAddress(pixel, [])
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 24)) else { throw writer.error ?? EmbyError.message("Cannot append frame") }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? EmbyError.message("Fixture writing failed") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "iOS/Tests/serve_range.py", folder.path]
        try process.run()
        defer { process.terminate() }
        try await Task.sleep(for: .seconds(1))
        let server = EmbyServer(id: UUID(), name: "Fixture", baseURL: URL(string: "http://127.0.0.1:18764/gateway")!, userId: "mock", username: "mock")
        let decoder = JSONDecoder()
        decoder.userInfo[.serverId] = server.id
        let item = try decoder.decode(MediaItem.self, from: Data(#"{"Id":"fixture","Name":"Fixture","Type":"Movie"}"#.utf8))
        let api = EmbyAPI()
        let info = try await api.playback(server, token: "fixture-token", item: item)
        let source = info.mediaSources[0]
        let urls = api.streamURLs(server, token: "fixture-token", item: item, source: source, forceTranscode: false)
        let url = try await api.resolveStreamURL(urls)
        guard url.path == "/gateway/Videos/fixture/stream.mp4" else { throw EmbyError.message("Proxy prefix was lost") }
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else { throw EmbyError.message("HTTP video is not playable") }
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.play()
        for _ in 0..<100 {
            if player.currentTime().seconds > 0.8 { break }
            if player.currentItem?.status == .failed { throw player.currentItem?.error ?? EmbyError.message("AVPlayer failed") }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard player.currentTime().seconds > 0.8 else { throw EmbyError.message("AVPlayer time did not advance") }
        player.pause()
        let sought = await player.seek(to: CMTime(seconds: 3, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        guard sought && abs(player.currentTime().seconds - 3) < 0.3 else { throw EmbyError.message("Seeking failed") }
        await api.report(server, token: "fixture-token", item: item, source: source, session: info.playSessionId, position: 30_000_000, phase: "/Progress")
        let progress = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("progress.json"))) as! [String: Any]
        guard progress["PositionTicks"] as? Int == 30_000_000 else { throw EmbyError.message("Progress sync failed") }
        player.replaceCurrentItem(with: nil)
        print("AVPlaybackSmoke: PASS (Emby negotiation, proxy 404 fallback, HTTP playback, advancing time, seek, progress sync)")
    }
}
