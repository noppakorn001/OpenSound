# OpenSound security review

Review date: 2026-10-14. Scope: current SwiftUI UI, Objective-C++ bridge and IOBluetooth transport, C++ framing/parsers/writers, app bundle, build scripts, source packaging, and CI configuration. This is a source and local-runtime review by the implementation agent, not an independent penetration test or certification. Sony firmware, macOS Bluetooth internals, proprietary cloud APIs and the full IPA binary are outside this security review.

## Threat model and data flow

The main untrusted input is Bluetooth data from a paired device, including packet sizes, enums, counted arrays, model strings, setting labels and pairing history. Commands pass from the English UI through a serial bridge worker to a discovered Sony RFCOMM service; decoded device data returns to the main thread. Both protocol tables use bounded frames and explicit reply opcode/inquiry matching. The device remains the authority for setting readback.

The shipped app has no application-defined internet client, web view, shell execution, downloaded-code loader, account credentials or telemetry upload. Its linked dependencies are Apple system frameworks and system Swift/C++ libraries. The code does not bundle or execute the supplied IPA. Research tools and vendor checkouts are excluded from the public package. Device product images are static bundled PNGs; app-selected paths come from bundle URLs, not arbitrary headphone-supplied filesystem paths.

## Findings and changes

| ID | Severity within this threat model | Finding | Resolution |
|---|---|---|---|
| OS-01 | Medium | Optional packet logging could truncate an existing path, follow a symlink and inherit permissive default permissions; logs may contain pairing identifiers | Fixed: exclusive POSIX creation, final-component no-follow, close-on-exec, mode 0600, no-overwrite, 8 MiB bound. Logging is opt-in and failures disable recording |
| OS-02 | Medium | An invalid matching battery/ANC/EQ reply could leave an older cached value available for write confirmation; Off preset could compare nil as zero | Fixed: invalidate matching cached state before and after GET, decode the actual reply again, require a present EQ value before declaring preset success |
| OS-03 | Medium | Invalid UTF-8 in headphone-defined labels could become nil inside a dictionary and cause an Objective-C exception | Fixed: length-aware UTF-8 conversion, fallback labels, remove control characters; anonymous pairing entries no longer fall back to displaying a Bluetooth address |
| OS-04 | Low | Quit could wait through queued work and transaction timeouts, especially with no responsive device | Fixed: cancellation flag, discard pending work during shutdown, stop accepting new work, bound the caller's wait to two seconds. Channel cleanup stays on its worker. OS synchronous Bluetooth calls remain governed by macOS |
| OS-05 | Low | Descriptor helpers assumed at least two bytes and a four-byte Speak-to-Chat payload | Fixed: explicit bounds before indexing, guarded writer; regression tests include malformed descriptors |
| OS-06 | Low | A general-setting current parameter type could differ from the capability type | Fixed: verify boolean/list type consistency and current device availability before general-setting writes |
| OS-07 | Low | Repeated device-refresh requests could accumulate while the worker was busy | Fixed: the UI coalesces device scans; setting actions and polling already serialize through the busy state |
| OS-08 | Build integrity | The app used ad-hoc signing without hardened runtime; CI used movable Action tags and persisted checkout credentials | Fixed: hardened runtime signing, immutable official Action commit pins, contents-read CI permissions and no persisted checkout credentials |
| OS-09 | Reliability | V2 single-device battery parsing and some timeout paths omitted single-battery state | Fixed: parse single battery and invalidate the appropriate legacy/V2 battery state on read failures; disconnect/error snapshots clear device state |

No exploitable critical or high-severity issue was established during this review. This is a statement about the inspected code and performed tests, not a guarantee. Changes described as fixed must remain covered by the tests below.

## Verification

- Existing framing/protocol regression suite: 423 checks with AddressSanitizer and UndefinedBehaviorSanitizer.
- Security suite: 100,000 deterministic random and mutated malformed inputs across framing, battery, ANC, EQ, handshake, support functions, touch assignment, pairing history and general settings; oversized delimiter stream and recovery; malformed descriptor and type-mismatch cases.
- Diagnostic log tests: 0600 permissions, 8 MiB cap, existing-file preservation and symlink-target preservation. Tests use disposable local files and do not connect to headphones.
- Clang static analyzer: Core protocol and both Native runtime implementation files; no analyzer diagnostics in the final run.
- Bundle checks: strict code-sign verification, ad-hoc+hardened-runtime flags, ARM64 PIE executable, system-only dylib references, no permissive signing entitlements.
- Real-device regression and Menu Bar lifecycle evidence are recorded separately in `RELEASE_VALIDATION.json`; successful prior tests are distinguished from newly repeated checks.
- Source archive uses a fixed source allowlist and excludes IPA, extracted files, private captures, development tools, vendor/reference checkouts and compiled output.

## Remaining limits

1. The app is not App Sandbox-contained and is not Developer ID-signed/notarized. Hardened runtime restricts code-loading behavior but does not contain ordinary file access. Public distribution still needs a deliberate signing/notarization workflow.
2. Bluetooth link authentication/encryption and permissions are delegated to macOS pairing. The Sony framing checksum is a byte sum, not a MAC. No application-level cryptographic proof of headset identity is implemented. A malicious paired peripheral remains an input threat.
3. The protocol has no application nonce or strong request identity. Opcode/inquiry/table matching, serial requests, alternating ACK state and duplicate suppression reduce ambiguity; a delayed reply with the same command shape cannot always be distinguished cryptographically from the next request.
4. Diagnostic data is plaintext, opt-in, owner-only and size-bounded; there is no encrypted storage or automatic retention policy. Top-level existing local analysis JSON/captures/screenshots were changed to mode 0600 during this review, but historical contents were not retroactively sanitized. Only the allowlisted source archive is suitable for public review.
5. Fuzzing is bounded and deterministic, not exhaustive or coverage-guided. No long-running RF adversarial test, independent audit, compromised-headset test, macOS Bluetooth penetration test or formal verification was performed.
6. Actual hardware validation covers one WF-1000XM4 firmware 2.3.1 unit. Unsupported layouts fail closed, but additional typed handlers and other model firmware need separate tests. Right-touch reassignment still has failed readback and must not be described as working.
7. Connection quality, automatic power-off, multipoint and assistant changes have implemented paths but not confirmed write/restoration tests on this device. Volume/EQ changes require user action; the app does not automatically increase volume or adjust sound on startup.
8. All-model BLE/LE Audio transport, safe listening, activity/location policies, Sony cloud/account and firmware workflows are absent or excluded; no device safety policy is implied by these missing controls.

The official Action refs used for CI pins were read from GitHub on the review date: checkout `11d5960a326750d5838078e36cf38b85af677262`, upload-artifact `ea165f8d65b6e75b540449e92b4886f43607fa02`. Protocol reference remains SonyHeadphonesClient `f11d686332e9aaf7630f9fb8a104b70c5d6f342c` and SonyBridge `8c81a2775a76097f4938fbc835411bd59088014c`, with retained MIT notices.
