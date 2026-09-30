"""Assert rendered MKV/HEVC+FLAC playback in the actual iOS VLC adapter."""
import json, os, subprocess, sys, time
from pathlib import Path
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread

app, output = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
output.mkdir(parents=True, exist_ok=True)
fixture = output / "fixture.mkv"
(output / "fixture.srt").write_text("1\n00:00:00,000 --> 00:00:29,000\nGuoPlayer MKV subtitle test\n")
subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
    "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=24",
    "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
    "-f", "lavfi", "-i", "sine=frequency=880:sample_rate=48000",
    "-i", str(output / "fixture.srt"), "-map", "0:v", "-map", "1:a", "-map", "2:a", "-map", "3:s",
    "-c:v", "libx265", "-preset", "ultrafast", "-x265-params", "log-level=error", "-c:a", "flac", "-c:s", "srt", "-t", "30", str(fixture)], check=True)
class Handler(SimpleHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_GET(self):
        if self.path not in ["/fixture.mkv", "/fixture.srt"]: self.send_error(404); return
        data = (output / self.path.lstrip("/")).read_bytes(); start, end = 0, len(data)-1
        value = self.headers.get("Range")
        if value:
            first, last = value.removeprefix("bytes=").split("-", 1)
            start = int(first or 0); end = min(int(last), end) if last else end
            if not 0 <= start <= end < len(data): self.send_error(416); return
        self.send_response(206 if value else 200)
        self.send_header("Content-Type", "video/x-matroska" if self.path.endswith("mkv") else "application/x-subrip")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end-start+1))
        if value: self.send_header("Content-Range", f"bytes {start}-{end}/{len(data)}")
        self.end_headers()
        try: self.wfile.write(data[start:end+1])
        except (BrokenPipeError, ConnectionResetError): pass
server = ThreadingHTTPServer(("127.0.0.1", 18765), Handler)
Thread(target=server.serve_forever, daemon=True).start()
subprocess.run(["open", "-a", "Simulator"], check=False)
subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"], text=True))["devices"]
device = next(d for ds in devices.values() for d in ds if d["name"].startswith("iPhone"))
udid = device["udid"]
subprocess.run(["xcrun", "simctl", "boot", udid], check=True)
try:
    subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=True, timeout=180)
    subprocess.run(["xcrun", "simctl", "install", udid, str(app)], check=True)
    env = dict(os.environ, SIMCTL_CHILD_GUOPLAYER_VLC_TEST_URL="http://127.0.0.1:18765/fixture.mkv")
    subprocess.run(["xcrun", "simctl", "launch", "--stdout=" + str(output / "app-stdout.log"), "--stderr=" + str(output / "app-stderr.log"), udid, "com.guoplayer.app", "--vlc-smoke"], env=env, check=True, timeout=120)
    container = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", udid, "com.guoplayer.app", "data"], text=True).strip())
    report = container / "Documents/vlc-smoke.json"
    for _ in range(180):
        if report.exists(): break
        time.sleep(1)
    subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", str(output / "vlc-mkv-playing.png")], check=False, timeout=45)
    if not report.exists():
        for name in ["app-stdout.log", "app-stderr.log"]:
            log = output / name
            if log.exists(): print(log.read_text(errors="replace")[-6000:], flush=True)
        raise RuntimeError("VLC simulator test timed out")
    result = json.loads(report.read_text())
    (output / "vlc-smoke.json").write_text(json.dumps(result, indent=2))
    subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", str(output / "vlc-mkv-playing.png")], check=True)
    print(json.dumps(result), flush=True)
    assert result.get("pass"), result
    print("iOS VLC MKV HEVC/FLAC rendered decode, audio/subtitle selection, seek, pause/resume: PASS")
finally:
    import shutil
    for crash in (Path.home() / "Library/Logs/DiagnosticReports").glob("GuoPlayer*"):
        if crash.is_file(): shutil.copy2(crash, output / crash.name)
    subprocess.run(["xcrun", "simctl", "shutdown", udid], check=False)
    server.shutdown()
