# Public repository privacy

The initial public source and its reachable commit history were checked on 2026-10-14. The scan found no personal email addresses, user-specific home paths, Bluetooth addresses, private keys or recognizable access tokens. Published commits use a GitHub no-reply address. The included PNGs contain no text or EXIF metadata; the interface screenshots were also visually reviewed, with paired-device names collapsed.

The project owner's GitHub username is intentionally public as the repository owner and commit identity. The product model, firmware, UI screenshots and battery percentages are public demonstration information. The review does not establish a guarantee that every possible personal identifier can be detected automatically.

## Before publishing changes

Run `python3 scripts/check-public-privacy.py` before pushing. It checks tracked working files, every reachable Git blob and author/committer emails. Errors identify the file and rule, never the matched private value. New contributors should use their GitHub no-reply commit email. Any intentional public attribution that triggers a rule requires a documented manual review before changing the guard.

Enable the local pre-push guard with `git config --local core.hooksPath .githooks`. CI repeats the check with full Git history. CI runs after publication; the local hook is the check that prevents a push. The hook and scanner are heuristics, so visually review every new screenshot and inspect new formats for metadata as well.

Do not commit the IPA, extracted app files, raw Bluetooth captures, paired-device names, authentication configuration, development tools or device-specific research reports. Keep those outside this public checkout. The source packager uses an allowlist; diagnostics and build output are excluded. Never share tokens or unredacted captures in issues.

If private information is discovered after publishing, deleting the current file is insufficient: history, forks and caches can retain it. Revoke any exposed credential first and coordinate history cleanup. Do not reproduce the sensitive data in a public report.
