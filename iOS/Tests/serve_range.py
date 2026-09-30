"""Local deterministic MP4 fixture server with HTTP byte range support."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import sys
import json

folder = Path(sys.argv[1]).resolve()
class Handler(SimpleHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))) or "{}")
        path = urlsplit(self.path).path
        if path == "/gateway/Items/fixture/PlaybackInfo" and body.get("DeviceProfile"):
            response = {"MediaSources": [{"Id": "source", "Container": "mp4", "SupportsDirectPlay": False, "SupportsDirectStream": True, "DirectStreamUrl": "/Videos/fixture/stream.mp4", "MediaStreams": []}], "PlaySessionId": "fixture-session"}
            data = json.dumps(response).encode()
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
        elif path == "/gateway/Sessions/Playing/Progress":
            (folder / "progress.json").write_text(json.dumps(body))
            self.send_response(204); self.end_headers()
        else:
            self.send_error(404)
    def do_GET(self):
        if urlsplit(self.path).path not in ["/fixture.mp4", "/gateway/Videos/fixture/stream.mp4"]:
            self.send_error(404)
            return
        data = (folder / "fixture.mp4").read_bytes()
        start, end = 0, len(data) - 1
        value = self.headers.get("Range")
        if value:
            try:
                first, last = value.removeprefix("bytes=").split("-", 1)
                if first:
                    start = int(first)
                    end = min(int(last), end) if last else end
                else:
                    start = max(0, len(data) - int(last))
                if not 0 <= start <= end < len(data):
                    raise ValueError()
            except ValueError:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{len(data)}")
                self.end_headers()
                return
        self.send_response(206 if value else 200)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if value:
            self.send_header("Content-Range", f"bytes {start}-{end}/{len(data)}")
        self.end_headers()
        self.wfile.write(data[start:end+1])
ThreadingHTTPServer(("127.0.0.1", 18764), Handler).serve_forever()
