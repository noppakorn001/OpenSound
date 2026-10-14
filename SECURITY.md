# Security policy

OpenSound is a local, unofficial headphone controller. It trusts macOS Bluetooth pairing and only issues implemented, capability-gated commands. It has no Sony account login, web client, telemetry uploader, firmware flasher, elevated helper, or automatic update installer.

Report vulnerabilities privately to the repository maintainer using the hosting provider's private vulnerability reporting feature when available. Include the affected revision, model/firmware, minimal sanitized fixture, expected behavior and observed impact. Never attach account secrets, the proprietary IPA, Bluetooth addresses or unredacted pairing history. The project has not published a contact address or guaranteed response SLA.

Run `bash scripts/security-test.sh` to exercise malformed input with AddressSanitizer/UndefinedBehaviorSanitizer and the diagnostic log protections. Read [the security review](docs/SECURITY_REVIEW.md) for findings, fixes and remaining limits.

Diagnostic packet recording is disabled by default. A developer can opt in with `WF_PROTOCOL_LOG=/absolute/path/to/a-new-file.jsonl`. The file must not already exist; it is created with owner-only permissions, no final-component symlink following, and an 8 MiB limit. Failure to open/write the diagnostic file disables logging and does not stop headphone operation. Captures may contain paired-device names and addresses: do not publish them. Existing top-level local analysis JSON/captures/screenshots were restricted to owner-only access during this review; their contents were not redacted or rewritten.

The local app is ad-hoc signed with hardened runtime enabled, and is not notarized or App Sandbox-contained. Run only code you trust. The checksum in the headphone protocol detects accidental corruption; it is not a cryptographic authentication mechanism. Physical-device tests and sanitizer runs do not establish universal model compatibility or absence of vulnerabilities.
