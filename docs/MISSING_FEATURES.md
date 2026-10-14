# OpenSound missing features audit

Audited 2026-10-14 against the implemented runtime, the pinned four-table protocol inventory, Sound Connect 13.2.0 metadata and recorded WF-1000XM4 hardware evidence. The inventory's 249 inquiry entries are protocol declarations across model families and include shared speaker/update subsystems; they are not 249 independent, verified UI functions. A static class/selector match does not establish a complete runnable workflow.

## WF-1000XM4 priorities

| Feature or behavior | Present state | Work still required |
|---|---|---|
| Battery, ANC/Ambient/Off, basic EQ and Clear Bass | Implemented and physically tested | Broader disconnect/in-case and firmware coverage |
| DSEE, wearing pause, Speak-to-Chat options, left-touch assignment, guidance toggle, headphone volume | Implemented; nine additional writes/readbacks/restorations passed | Longer-running usage and more firmware/model tests |
| Right touch assignment | Advertised choices and current state visible; writes not confirmed | Resolve actual command/workflow behavior. Both keys reported enabled; retry with both earbuds worn and temporary left Volume assignment still failed; original values restored |
| Connection quality and automatic power-off | Writes/readbacks/restorations passed on the test unit | More model/firmware and connection-loss coverage |
| Multipoint and source switching | Reads available; writes were not confirmed and original values retained | Resolve headset rejection conditions and verify during actual A2DP playback; latest retry stopped before writes because Bluetooth was unavailable |
| Assistant selector | Advertised control and reads available | Actual write/readback/restoration testing |
| Ear-tip fitting and wearing setup | No end-to-end UI | Capability binding, start/status/result sequence, hardware testing |
| Adaptive Sound Control | No Mac policy engine | Activity/location rules, permissions, privacy policy and safe automatic-change workflow |
| 360 Reality Audio personalization / head-tracking services | No complete native workflow | Model capability handling plus required platform/service integration; do not equate EQ with spatial audio |
| Voice/notification language and volume | Guidance toggle present; volume handler only when advertised | Language capability inventory, selection/download semantics and notification settings, tested readback |
| Custom EQ slot naming/saving and Find Your Equalizer | Manual editor and advertised preset selector present | Distinct save-to-slot and comparison workflow; do not claim every Custom slot is editable |
| Playback actions and call volume | Music/headphone volume present | Reviewed play/pause/skip command workflow and separate call-volume capability handling |
| Automatic reconnect and start at login | Configurable reconnect/backoff, remembered device and sleep/wake handling; Menu Bar persists after window close | Start-at-login preference is still missing. Full physical sleep/wake and across-firmware testing remains necessary; no automatic login installation is performed |

## Other Sony model families

Additional ANC profiles, different band counts/gain ranges, ULT effects, BGM/upmix, NC optimizer, head gestures and calibration, adaptive-volume variants, button/custom action maps, Quick Access and Auto Play, pairing-management actions, speaker-only features, BLE-only devices, LE Audio profile control and safe-listening/exposure workflows still need dedicated typed implementations or complete host workflows. Existing head-gesture/vibration/adaptive-volume handlers have no physical validation on a matching model.

The app discovers model candidates and chooses a Sony SDP service; a name or product photo alone does not establish compatibility. Unknown formats remain unavailable. A generic SET descriptor stays disabled until its capability binding, current-value schema, preservation rules and readback checks are implemented and validated.

Sony Account/cloud and firmware updating are deliberately excluded by the requested headphone-control-first scope. They are not included in the missing local-control implementation commitment.

See `FEATURE_COVERAGE.md` for the implemented matrix, `DEVICE_SUPPORT.md` for hardware boundaries and `SECURITY_REVIEW.md` for the corresponding safety limits.
