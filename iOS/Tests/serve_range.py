"""Local deterministic MP4 fixture server with HTTP byte range support."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import sys

folder = Path(sys.argv[1]).resolve()
class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if urlsplit(self.path).path != "/fixture.mp4":
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
