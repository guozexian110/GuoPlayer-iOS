"""Build the public GuoPlayer discovery feed from TMDb without publishing its token."""
import datetime as dt
import json
import os
from pathlib import Path
import urllib.parse
import urllib.request

credential = os.environ.get("TMDB_READ_TOKEN", "").strip()
if not credential:
    raise SystemExit("TMDB_READ_TOKEN is required")

sections = {
    "day": ("/trending/all/day", {}),
    "week": ("/trending/all/week", {}),
    "now": ("/movie/now_playing", {"region": "CN"}),
    "anime": ("/tv/airing_today", {"timezone": "Asia/Shanghai"}),
    "movie": ("/movie/popular", {}),
    "tv": ("/tv/popular", {}),
    "topMovie": ("/movie/top_rated", {}),
    "topTV": ("/tv/top_rated", {}),
    "family": ("/discover/movie", {"with_genres": "10751"}),
    "animation": ("/discover/movie", {"with_genres": "16"}),
    "netflix": ("/discover/movie", {"with_watch_providers": "8", "watch_region": "US"}),
    "disney": ("/discover/movie", {"with_watch_providers": "337", "watch_region": "US"}),
    "apple": ("/discover/movie", {"with_watch_providers": "350", "watch_region": "US"}),
    "universal": ("/discover/movie", {"with_companies": "33"}),
    "paramount": ("/discover/movie", {"with_companies": "4"}),
    "columbia": ("/discover/movie", {"with_companies": "5"}),
    "marvel": ("/discover/movie", {"with_companies": "420"}),
}


def fetch(path: str, parameters: dict[str, str]) -> list[dict]:
    query = {"language": "zh-CN", "page": "1", **parameters}
    headers = {"Accept": "application/json", "User-Agent": "GuoPlayer-Feed/1.0"}
    if "." in credential:
        headers["Authorization"] = f"Bearer {credential}"
    else:
        query["api_key"] = credential
    url = "https://api.themoviedb.org/3" + path + "?" + urllib.parse.urlencode(query)
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=25) as response:
        data = json.load(response)
    results = data["results"]
    if not isinstance(results, list):
        raise ValueError(f"Invalid TMDb results for {path}")
    return [row for row in results if isinstance(row, dict) and row.get("poster_path")]


output = {}
for name, (path, parameters) in sections.items():
    rows = fetch(path, parameters)
    if name == "anime":
        rows = [row for row in rows if 16 in row.get("genre_ids", [])]
    output[name] = rows
    print(f"{name}: {len(rows)} titles")

assert output["day"] and output["week"], "Trending lists must not be empty"
destination = Path("site/feed/home.json")
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(json.dumps({
    "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    "sections": output,
}, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
Path("site/.nojekyll").touch()
Path("site/index.html").write_text(
    "<!doctype html><meta charset=utf-8><title>GuoPlayer feed</title>"
    "<p>GuoPlayer discovery data is provided by TMDb. This product is not endorsed by TMDb.</p>",
    encoding="utf-8",
)
