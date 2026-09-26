"""Portable checks that can run before Xcode is available."""
from pathlib import Path
import plistlib
import re
import json
import struct
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
project = (root / "GuoPlayer.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
plist = plistlib.loads((root / "GuoPlayer/Info.plist").read_bytes())
ET.parse(root / "GuoPlayer.xcodeproj/xcshareddata/xcschemes/GuoPlayer.xcscheme")
ET.parse(root / "GuoPlayer/LaunchScreen.storyboard")
assert plist["CFBundleIdentifier"] == "$(PRODUCT_BUNDLE_IDENTIFIER)"
assert plist["UILaunchStoryboardName"] == "LaunchScreen"
assert "com.guoplayer.app" in project
assert "IPHONEOS_DEPLOYMENT_TARGET = 17.0" in project
assert 'TARGETED_DEVICE_FAMILY = "1,2"' in project
assert "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon" in project
assert "Assets.xcassets" in project and "LaunchScreen.storyboard" in project
assert "DEVELOPMENT_TEAM" not in project and "PROVISIONING_PROFILE" not in project

assets = root / "GuoPlayer/Assets.xcassets"
icon_set = json.loads((assets / "AppIcon.appiconset/Contents.json").read_text(encoding="utf-8"))
assert icon_set["images"][0]["filename"] == "AppIcon-1024.png"
icon_bytes = (assets / "AppIcon.appiconset/AppIcon-1024.png").read_bytes()
assert icon_bytes[:8] == b"\x89PNG\r\n\x1a\n"
assert struct.unpack(">II", icon_bytes[16:24]) == (1024, 1024)
assert (assets / "BrandMark.imageset/BrandMark.png").exists()

swift_files = list((root / "GuoPlayer").glob("*.swift"))
assert len(swift_files) == 7
for file in swift_files:
    assert f"path = {file.name};" in project, file
assert (root / "GuoPlayer/logo.png").exists()
ids = re.findall(r"^\s*([A-F0-9]{24}) = \{", project, re.M)
assert len(ids) == len(set(ids)), "duplicate project object ID"
declared = set(ids)
references = set(re.findall(r"\b[A-F0-9]{24}\b", project))
assert references <= declared, f"unresolved project IDs: {references - declared}"
workflow = (root.parent / ".github/workflows/ios-unsigned.yml").read_text(encoding="utf-8")
for value in ("CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "Payload/GuoPlayer.app", "actions/upload-artifact@v4"):
    assert value in workflow, value
print("iOS project static checks: PASS")
