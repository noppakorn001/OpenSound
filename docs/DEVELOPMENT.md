# Developing OpenSound

## Requirements

- An Apple Silicon Mac running macOS 14 or later.
- Xcode with its macOS SDK, Swift and Clang C++ toolchains selected by `xcode-select`.
- Git, Bash and Python 3.9 or later for development checks. The build uses Apple command-line tools including `xcrun`, `codesign`, `sips` and `iconutil`.

No package manager, paid signing account, Node, Java, Ghidra, PlayCover, private research checkout, IPA or Sony account is required. Intel builds are not currently supported by the build script. If the tools are missing, install Xcode and complete its first-run setup; check `xcrun --find swiftc`, `xcrun --sdk macosx --show-sdk-path` and `python3 --version` before continuing.

## Build from a fork

Clone your GitHub fork, then run these commands from the checkout root:

```sh
bash scripts/build.sh
open dist/OpenSound.app
```

The app is locally ad-hoc signed and requires no secrets or credentials. Build output goes into ignored `build/` and `dist/`. Swift module caches are separated by checkout path so moving a folder does not reuse an incompatible cache. Bluetooth permission and a paired supported headset are needed for live controls, not for compiling or offline tests. No headphone settings change during a build.

To omit the Sony product renders whose redistribution rights are unconfirmed:

```sh
OPENSOUND_DEVICE_IMAGES=none bash scripts/build.sh
```

This uses the existing generic headphone illustration. It removes any old bundled device images when rebuilding, keeps the MIT cow app icon, and does not change the photos stored in the checkout. See [licensing](LICENSING.md).

## Offline checks

```sh
bash scripts/test.sh
python3 tests/FeatureCatalogTests.py
bash scripts/security-test.sh
python3 tests/SourceExportTests.py
python3 scripts/check-public-privacy.py
```

The first script tests C++ framing/protocol parsing with sanitizers and Swift reconnect policy. Security tests exercise malformed packets and diagnostic-file protections. Catalogue validation intentionally skips regeneration without the optional reference checkout; the checked-in catalogue is enough to build and validate its schema. Source export tests check that untracked files and symlinks cannot enter public packages.

Privacy checking requires a Git checkout. It does not run against a plain extracted archive without Git history. Configure your own GitHub no-reply commit email before the first commit and enable the pre-push hook as described in [CONTRIBUTING](../CONTRIBUTING.md).

## Source map

| Location | Responsibility |
|---|---|
| `Sources/App/WFControl.swift` | SwiftUI portrait window, Menu Bar controls and observable UI/device state |
| `Sources/App/ReconnectPolicy.swift` | Reconnect timing and user intent |
| `Sources/Core/WFProtocol.h`, `.cpp` | C++ framing, parsing and typed Sony protocol helpers |
| `Sources/Native/WFTransport.h`, `.mm` | IOBluetooth discovery, SDP and RFCOMM transport |
| `Sources/Native/WFBridge.h`, `.mm` | Objective-C++ bridge, serialized requests, capabilities and readback/restoration |
| `Sources/Native/*Tests.mm` | Optional tests against real hardware |
| `tests/` | Offline C++, Swift and Python tests |
| `Resources/` | Bundle metadata, app icon, optional device renders and Finder layout |
| `docs/` | Compatibility evidence, protocol catalogue, licensing and audit snapshots |
| `scripts/` | Build, tests, privacy checks and release packaging |

Keep transport, protocol, bridge/device state and UI responsibilities separate. UI updates belong on the main thread; transport requests are serialized. A setting is successful only after device readback. Preserve fields the user did not change and report unavailable capabilities rather than guessing a format. See [control descriptors](CONTROL_DESCRIPTOR_API.md) and [protocol inventory](PROTOCOL_INVENTORY.md).

## Optional hardware testing

Only run these while deliberately testing a paired headset and after closing other controller sessions:

```sh
bash scripts/hardware-test.sh
bash scripts/settings-hardware-test.sh
bash scripts/touch-hardware-test.sh
```

These tests send real commands and temporarily change settings, then attempt to restore saved values and verify readback. Keep the device available until restoration completes. A failure or disconnect can prevent restoration; inspect the device's actual settings afterward. Read each script's usage before running it. Never publish raw diagnostic recordings.

## Packaging and releases

```sh
bash scripts/package-source.sh
bash scripts/package-dmg.sh
```

The source packager exports only tracked, allowlisted files, checking each exported file for privacy findings. Stage intended new files before packaging; untracked local files are excluded. It does not export `.git`, private research, credentials or build output. Generated source archives carry `SOURCE_MANIFEST.txt` and can be built and repackaged without Git. With `OPENSOUND_DEVICE_IMAGES=none`, source packaging also omits Sony product images and interface screenshots that contain them.

The DMG packages the app already in `dist/`; rebuild first after changing source or the artwork option. A local build is ad-hoc signed, not notarized. Release publishers must review licensing, attribution, screenshots, privacy and the selected app version before publishing. Fork maintainers should choose their own bundle identifier in `Resources/Info.plist` if their fork is installed alongside OpenSound, and update repository links and branding as appropriate.

CI uses read-only repository permissions and requires no secrets. Fork pull requests run the same offline checks and build. Live Bluetooth tests are not part of CI. Audit manifests and release validation reports are dated historical evidence, not a claim that later modifications have been independently audited.
