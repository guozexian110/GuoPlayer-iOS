# Third party notices and relinking

GuoPlayer uses the unmodified VideoLAN VLCKit/libVLC through tylerjonesio/vlckit-spm 3.6.0 (LGPL 2.1 or later). The license is in LICENSE-VLCKit.txt. VideoLAN and the respective upstream contributors retain copyright.

- Wrapper/source and build script: https://github.com/tylerjonesio/vlckit-spm/tree/3.6.0
- VLCKit source: https://github.com/videolan/vlckit/tree/3.6.0
- Upstream libVLC: https://code.videolan.org/videolan/vlc
- Binary: https://github.com/tylerjonesio/vlckit-spm/releases/download/3.6.0/VLCKit-all.xcframework.zip
- SHA256: 5da4747e001900bbb4153f58db2be4695096c9c2350aea00376ad67b39c053f6

No library modifications are applied. Complete GuoPlayer source and Xcode project are available in this repository. You may rebuild/relink GuoPlayer with your modified compatible LGPL library, and reverse engineer the application to debug such changes. Replace the package reference with a local compatible package built using the upstream generate.sh script, then build using the README command. No original developer signing key is required; sign the resulting app yourself.

The workflow also publishes GuoPlayer-relink-objects containing device build intermediate object files/link file lists for the same build. Download it alongside the IPA to preserve the exact application objects used in that version. These artifacts expire after 30 days; builds can be rerun from the matching repository commit. Do not treat this binary dependency as an assurance of App Store review approval.
