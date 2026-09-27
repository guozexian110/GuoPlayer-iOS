"""Offline smoke test for the scheduled TMDb feed builder."""
import io
import json
import os
from pathlib import Path
import runpy
from unittest.mock import patch

script = Path(__file__).with_name("build_tmdb_feed.py")
requests = []
writes = {}


def fake_open(request, timeout):
    requests.append(request)
    assert timeout == 25
    assert request.get_header("Authorization") == "Bearer fixture.token.value"
    rows = [{
        "id": 42, "title": "Fixture", "media_type": "movie",
        "poster_path": "/fixture.jpg", "genre_ids": [16],
    }]
    return io.BytesIO(json.dumps({"results": rows}).encode())


def fake_write(path, content, **kwargs):
    writes[str(path)] = content
    return len(content)


with patch.dict(os.environ, {"TMDB_READ_TOKEN": "fixture.token.value"}), \
     patch("urllib.request.urlopen", side_effect=fake_open), \
     patch.object(Path, "mkdir"), patch.object(Path, "touch"), \
     patch.object(Path, "write_text", fake_write):
    runpy.run_path(str(script), run_name="__main__")

raw = next(value for path, value in writes.items() if path.replace("\\", "/") == "site/feed/home.json")
feed = json.loads(raw)
assert len(requests) == 17
assert set(feed["sections"]) == {
    "day", "week", "now", "anime", "movie", "tv", "topMovie", "topTV",
    "family", "animation", "netflix", "disney", "apple", "universal",
    "paramount", "columbia", "marvel",
}
assert feed["sections"]["day"][0]["id"] == 42
assert "fixture.token.value" not in raw
print("TMDb feed smoke: PASS")
