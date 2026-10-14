# Third-party notices

The optional Finder layout regeneration tool uses MIT-licensed [ds_store](https://github.com/dmgbuild/ds_store) 1.3.1 and [mac_alias](https://github.com/dmgbuild/mac_alias) 2.2.2 from PyPI as development tools. They are not included in the app, DMG or public source archive. The layout template contains project-defined window settings and icon coordinates only. Finder settings conventions were checked against the [dmgbuild source](https://github.com/dmgbuild/dmgbuild/blob/main/src/dmgbuild/core.py).

OpenSound's initial Bluetooth route, framing, and EQ command layouts are adapted from [AmitRajput-Dev/SonyBridge](https://github.com/AmitRajput-Dev/SonyBridge) at commit `8c81a2775a76097f4938fbc835411bd59088014c` (MIT). The full license is retained in `LICENSE.SonyBridge` and embedded in the application.

Additional command declarations, enum values, and protocol layouts are derived from [mos9527/SonyHeadphonesClient](https://github.com/mos9527/SonyHeadphonesClient) at commit `f11d686332e9aaf7630f9fb8a104b70c5d6f342c` (MIT). The full license is retained in `LICENSE.SonyHeadphonesClient` and embedded in the application. Its source checkout is a local research reference, not a build dependency.

The headphone product name and Sony trademarks belong to their owners. The supplied Sound Connect IPA, executable bytes, extracted assets, and raw analysis captures are not included in the public source package. The device hero images are retained from the pinned SonyBridge resources at the project owner's request; upstream describes them as official Sony product renders. Their provenance is recorded in `Resources/Devices/NOTICE.md`. Sony's product imagery and trademarks remain theirs; the code license is not a claim of ownership of those images. The app also uses system SF Symbols and the colorful geometric cow logo selected and supplied by the project owner. Icon provenance is retained in `Resources/Icon/PROMPT.txt`.

Ghidra 12.1.4, Temurin JDK 21, and PlayCover 3.1.0 are separately licensed research tools, not included in the app or source package.
