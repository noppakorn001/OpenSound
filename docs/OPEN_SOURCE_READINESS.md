# Open-source readiness review

Review date: 2026-10-21. This records repository preparation, not independent legal or security certification.

## What a contributor can do

- Fork the public `noppakorn001/OpenSound` repository; GitHub reports `private: false`, `allow_forking: true`, `archived: false`.
- Use, modify, distribute and sell the MIT-licensed code subject to retaining its notices; no CLA or separate maintainer permission is required.
- Build an ad-hoc signed app from the checked-in source without the proprietary IPA, private research tools, credentials or a paid signing account.
- Follow the fork/branch/pull-request workflow, development source map, issue forms, support policy and community conduct policy.
- Report security issues privately; GitHub private vulnerability reporting is enabled.

## Licensing boundary

The owner confirmed the generated cow logo may be licensed under MIT. Adapted MIT code retains both upstream licenses. Sony product-render redistribution rights remain unconfirmed, and their depiction in interface screenshots has the same limitation. The owner chose to retain these images with that status disclosed. The code is open source; the repository's complete artwork collection is **not** certified as freely redistributable. See [licensing](LICENSING.md).

Forks can build and export without the Sony artwork using `OPENSOUND_DEVICE_IMAGES=none`. The resulting app keeps the MIT cow icon and uses generic system headphone symbols. The reduced source archive also excludes interface screenshots; it retains source and notices.

## Validation performed

- C++ protocol suite: 437 sanitizer checks passed; Swift reconnect policy tests passed.
- Security suite: 100,000 malformed-input cases and diagnostic log protection checks passed.
- Feature catalogue: 8 tests completed, with optional regeneration skipped because no private reference checkout was supplied.
- Source export: 11 regression tests passed, including untracked-file exclusion, file/directory symlink rejection, path traversal rejection, private-file/content blocking, image omission, archive re-export and detection of secrets left in the Git index after cleaning the working copy.
- Built the app from a separately extracted image-free source archive with no `.git`, IPA or private tools. Ad-hoc signature verification passed. Re-exporting that archive passed.
- Checked that image-free rebuilding removes stale bundled renders; the default local build retains all 14 renders as requested.
- Re-ran protocol/reconnect checks after moving the extracted checkout, verifying the module-cache path fix.
- The working copy, staged files and reachable history passed the privacy guard before publication. This heuristic check does not guarantee detection of every possible identifier; no new screenshots or raw device captures were published.

CI repeats offline tests, privacy checks, image-free source export, app build and DMG creation. Existing release security manifests describe their dated snapshots and are not silently rewritten as audits of this update. No new hardware compatibility claims were added.
