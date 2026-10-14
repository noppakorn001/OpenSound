# Static reconstruction and evidence

The original Sound Connect 13.2.0 IPA was preserved. SHA-256: `163ec86d677bc1194c6028e016968be9415302b06da06284c6037f3d415f3297`. Its ARM64 executable SHA-256 is `d615ff298e1070328d5704eb54655bebe03ddf7fed512375ac3b388467dfe8f0`. The main executable has `cryptid=0`. The extracted tree has 1,952 files and 17 thin Mach-O images; local manifests retain per-file hashes and encryption metadata.

Complete local REA records:

- Artifact: `ev_67dd8fda03cd4115796a62286a664c49171f3689796008a34f87a65c44a92630`.
- Mach-O: `ev_565b8df86bd21886d3bbf1bf5d35ebda13870a172a2a7fe67fd4ac20dbcb754b`.
- Bounded Ghidra ARM64 serializer span: `ev_953db1d4ae009c31f527bbe0ca87ce0a206a7b8a27069028af80c75a6c1d3143`.

The local `analysis/evidence` records, Objective-C method index, source-byte offsets, and annotated LLVM ARM64 disassembly are the source of these conclusions. Evidence IDs identify records, not links to a hosted service. Ghidra pseudocode is reconstructed analysis output, not Sony's source code.

Ghidra 12.1.4 and Temurin JDK 21.0.12.1+1 were downloaded from official release assets. Archive SHA-256 checks matched official metadata: Ghidra `ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db`; JDK `3623232f33a9c3baadf304480b2535f9a3cba8a58d42ecbb438ba267315d9998`. The release lacked the Apple Silicon decompiler; its bundled C++ source was built locally for ARM64. A seeded full executable import was stopped after eight minutes of unrelated autoanalysis. One provenance-bound 432-byte serializer span completed under Ghidra. Original-image metadata and bounded disassembly remain the primary evidence for external dispatch semantics.

## Reviewed packet layouts

Offsets below count payload bytes, including the opcode at zero. Objective-C method addresses are virtual addresses in the original ARM64 image, not runtime ASLR addresses.

| Behavior | Static anchor | Result |
|---|---|---|
| Framing | `MessageWriter.sendFrame` `0x1025e9220`; start/end getters `0x1025e9680` / `0x1025e9698` | Start `3E`, type, sequence, four-byte big-endian length, payload, additive checksum, end `3C`; reserved bytes escaped |
| Data families | `DataType.initialize` `0x1025e8868` | Table 1 data `0C`; table 2 `0E`; ACK `01` |
| Battery inquiries | `THMSGV2T1PowerInquiredType.initialize` `0x10140d098` | Single `00`, left/right `01`, cradle `02`; threshold variants `08` / `09` / `0A` |
| Left/right battery | `PowerRetStatusLeftRightBatteryBase` constants `0x10141820c`–`0x10141827c` | Inquiry 1, left level 2, left charging 3, right level 4, right charging 5 |
| Case/single battery | `PowerRetStatusBatteryBase` constants `0x101416a20` / `38` / `50` | Inquiry 1, level 2, charging 3 |
| Charging values | `BatteryChargingStatus.initialize` `0x10140e258` | Not charging `00`, charging `01`, unknown `02`, charged `03`, out of range `FF` |
| EQ capability | `EqEbbRetCapabilityEq.getEqPresets/getBand/getStep` `0x10143093c` / `0x101430c4c` / `0x101430d20` | Band count 2, step count 3, preset count 4; records at 5 contain id, name length, name bytes |
| EQ parameter | `EqParam.getPresetId/getBandSteps` `0x101449a08` / `0x101449adc`; wrapper `0x101468f2c` | Reply `57`, inquiry, preset, count, values. Device's six-band, 21-step capability establishes the centered editor range |
| ANC capability | Shared helper `0x1015fce94`; Auto profile getter `0x101614d18` | Count 2; records from 3: mode, minimum, maximum, step |
| ANC Auto profile | Processor getters `0x10160362c` / `724` / `81c` / `914`; SET factory `0x10162ed14` | Inquiry `15`, change status 2, total effect 3, mode 4, NC value 5, voice mode 6, level 7 |
| ANC dual profile | Getters `0x101605db4` / `eac` / `fa4`; SET factory `0x101612764` | Inquiry `17`, change status 2, total effect 3, mode 4, voice mode 5, level 6 |
| Legacy ANC profile | `NcAsmParam.restore/write` `0x1012db470` / `0x1012db8b0` | Inquiry `02`, effect, NC setting type/value, ASM setting type/id/value; preserve device-reported setting types |
| ANC availability | `NcAsmRetStatus.getAvailability` `0x1016391e4`; `EnableDisable.initialize` `0x1016da394` | Status byte 2: enabled `00`, disabled `01`, out of range `FF` |

The Auto profile's `NcValue` enum at `0x10161c884` is OFF `00`, SINGLE `01`, DUAL `02`, AUTO `03`, AUTO_SINGLE `04`, AUTO_DUAL `05`. Modes NC / Ambient are `00` / `01`; voice Normal / Voice are `00` / `01`. Value-change status `00` means changing and `01` means changed. All these are constructor byte-code values; Java enum ordinals must never be substituted for wire values.

Runtime tests independently corroborated core fields against the user's WF-1000XM4. Its advertised support function `68` selects inquiry `15`. Battery, ANC, EQ writes, restoration, and reconnect passed in the recorded local test. Other model controls have reference declarations and metadata anchors, but generally no per-field assembly audit or hardware execution evidence.

## Public-source boundary

The generated catalogue uses pinned MIT protocol declarations from SonyHeadphonesClient plus compact names/addresses as metadata provenance. It distinguishes a named class from a validated contract and an implemented feature. Ship source, notices, generated public catalogue, and sanitized tests. Do not publish the supplied IPA, extracted assets/binaries, full private dumps, hardware addresses, session logs, tool SDK distributions, Ghidra projects, or local screenshots containing device data.

SonyBridge is MIT at `8c81a2775a76097f4938fbc835411bd59088014c`; SonyHeadphonesClient is MIT at `f11d686332e9aaf7630f9fb8a104b70c5d6f342c`. The modern protocol headers cover four tables and more declared controls than the original bridge. Use the modern pinned declarations as reference material and audit typed handlers against metadata/hardware; avoid replacing the working transport wholesale. Retain both licenses for copied code/declarations. Neither repository's code license establishes redistribution rights for Sony product photographs, trademarks, the IPA, or bundled Sony assets. This is a provenance observation, not a legal determination.
