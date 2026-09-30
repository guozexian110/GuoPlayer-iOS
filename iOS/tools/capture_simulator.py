"""Boot one available iPhone and iPad simulator and capture the launch layout."""
import json
from pathlib import Path
import struct
import subprocess
import sys
import time

app = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
output.mkdir(parents=True, exist_ok=True)
assert (app / "GuoPlayer").exists(), app
# Apple Silicon Simulator requires an ad-hoc signature. This uses no certificate
# and only touches the Debug Simulator app; the device IPA remains unsigned.
subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)], check=True, timeout=60)
subprocess.run(["open", "-a", "Simulator"], check=False, timeout=30)
devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"], text=True))["devices"]
available = [device for entries in devices.values() for device in entries if device.get("isAvailable", True)]

for kind in ("iPhone", "iPad"):
    matches = [device for device in available if device["name"].startswith(kind)]
    if not matches:
        raise RuntimeError(f"No available {kind} simulator")
    device = matches[0]
    udid = device["udid"]
    print(f"Launching on {device['name']} ({udid})", flush=True)
    subprocess.run(["xcrun", "simctl", "boot", udid], check=True)
    try:
        subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=True, timeout=180)
        subprocess.run(["xcrun", "simctl", "install", udid, str(app)], check=True, timeout=180)
        subprocess.run(["xcrun", "simctl", "launch", udid, "com.guoplayer.app"], check=True, timeout=180)
        time.sleep(10)
        screenshot = output / f"{kind.lower()}-discover.png"
        subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", str(screenshot)], check=True, timeout=180)
        subprocess.run(["xcrun", "simctl", "terminate", udid, "com.guoplayer.app"], check=False)
        subprocess.run(["xcrun", "simctl", "launch", udid, "com.guoplayer.app", "--layout-preview"], check=True, timeout=180)
        time.sleep(4)
        subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", str(output / f"{kind.lower()}-layout-preview.png")], check=True, timeout=180)
        png = screenshot.read_bytes()
        assert png[:8] == b"\x89PNG\r\n\x1a\n"
        width, height = struct.unpack(">II", png[16:24])
        assert width > 500 and height > 500, (width, height)
        print(f"{kind} screenshot: {width}x{height}", flush=True)
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", udid], check=False)
