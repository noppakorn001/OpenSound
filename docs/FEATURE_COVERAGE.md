# OpenSound feature coverage

OpenSound implements a selected, typed subset of Sound Connect's headphone controls. It does not yet implement every feature from the IPA or prove compatibility with every Sony model. Features are enabled only when the connected headphone advertises the relevant capability and returns a valid current value. Changes require device readback; an ACK alone is insufficient.

## Current application controls

| Control | Current implementation | WF-1000XM4 evidence |
|---|---|---|
| Left/right/case battery | Read-only percentages and charging state; missing case information remains unavailable | Hardware reads verified |
| ANC, Ambient Sound, Off | Capability-selected ANC profile, supported ambient level and Focus on Voice | Writes/readback, byte-for-byte restoration and reconnect verified |
| EQ presets, five bands and Clear Bass | Device-advertised presets; manual editor requires the supported six-band, 21-step capability | Preset/manual writes, readback and restoration verified |
| DSEE | Typed device setting; current value preserved until confirmed readback | Write/readback and original-value restoration passed |
| Connection quality | Typed device setting | Write/readback and original-value restoration passed |
| Pause when removed | Typed device setting | Write/readback and original-value restoration passed |
| Speak to Chat | Type 1/type 2 profile selection; enable, sensitivity and resume time; Type 1 voice focus | Type 1 enable, sensitivity, resume time and voice focus writes/readback/restoration passed; Type 2 untested |
| Automatic power off | Advertised modes/timers; capability-filtered options | Write/readback and original-value restoration passed |
| Headphone volume | Maximum value obtained from device capability | Write/readback and original-value restoration passed |
| Left touch assignment | Nested capability parser; presets come from the key's advertised list | Write/readback and original-value restoration passed |
| Right touch assignment | Current assignment and advertised choices read; requested changes require confirmation | Tested requests were not applied; app reported readback failure and original value remained intact |
| Voice guidance | Table 2 setting; preserves the existing language choice | On/off write/readback and original-value restoration passed |
| Voice guidance volume | Typed Table 2 setting when supported | Implemented; not advertised by this tested unit |
| Multipoint source switching | Typed Table 2 setting with device failure reason | Write/readback rejected in current audio/call state; original value retained |
| Paired devices | Read-only pairing history | Hardware response parsed and displayed |
| Headphone voice assistant | Device-advertised choices; provider account setup is separate | Capability/current value read; write not tested |
| Device-named general settings | Typed boolean/list capability parser; preserves device labels/options | WF-1000XM4 multipoint option read; requested change was not confirmed and original value retained |
| Head gestures, vibration and adaptive volume | Typed handlers selected by advertised capability | Implemented; no matching hardware validation |
| Model, firmware version and active codec | Read-only device information; macOS negotiates the audio codec | Hardware reads verified |

Nine additional setting changes passed confirmed readback and original-value restoration. One right-touch assignment test failed to apply; repeated alternate requests also left the original value unchanged. This limitation remains visible rather than being counted as a successful write. `RELEASE_VALIDATION.json` contains a sanitized test summary.

These application handlers are separate from the generated protocol descriptors. A declared handler does not automatically enable a descriptor or establish compatibility with a different model.

## Remaining feature coverage

| Feature family | Status |
|---|---|
| Additional ANC profiles, EQ layouts, ULT/sound effects, BGM/upmix and connection variants | Protocol declarations catalogued; further typed handlers and physical model tests required |
| Wearing diagnostics, ear-tip fitting tests, NC optimization, head-tracking and Sound AR | Catalogued; complete device/runtime workflow not implemented |
| Adaptive Sound Control activity/location rules and automatic mode policies | Headphone declarations catalogued; a macOS activity/location policy engine is missing |
| Quick Access, Auto Play and voice-assistant provider setup | Phone/service integration missing; local device selectors do not implement these external services |
| LE Audio, BLE-only control transport and profile switching | Protocol declarations catalogued; transport/host integration not established |
| Pairing-management actions, reset, factory reset and other one-shot actions | Dedicated reviewed action workflows remain missing |
| Safe listening, exposure history and device-specific listening safeguards | Catalogued; complete workflow not implemented |
| Sony Account, cloud services and firmware updating | Excluded by the user's requested scope |

The generated inventory records 249 inquiry declarations, 230 advertised function identifiers and 1,294 packet contracts across four protocol tables. `control-descriptors.json` has 239 SET declarations, including 196 fixed-layout candidates and 117 exact declared RET counterparts. Every generated descriptor remains disabled by default. These counts describe investigation coverage, not implemented controls. See `PROTOCOL_INVENTORY.md`, `CONTROL_DESCRIPTOR_API.md` and `REVERSE_ENGINEERING.md` for provenance and limitations.

The release uses paired-device discovery rather than a model whitelist, and the WF-1000XM4 has physical validation for core controls and the successful additional settings listed above. See `DEVICE_SUPPORT.md` for the support boundary.

OpenSound 0.4.0 adds tested reconnect scheduling and privacy-collapsed pairing names. Connection quality and automatic power-off each passed a fresh write/readback/restoration test. Two multipoint changes failed readback; source switching reported A2DP-not-connected and calling result codes during testing. These failures are not counted as successful writes.
