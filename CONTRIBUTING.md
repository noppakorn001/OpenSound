# Contributing to OpenSound

You may fork, modify, redistribute and use the OpenSound code commercially under the [MIT license](LICENSE). No purchase, Sony account, proprietary IPA, research workspace or maintainer approval is needed to build a fork. See [licensing and artwork](docs/LICENSING.md) for the separate status of Sony product renders.

## Your first change

1. Fork [noppakorn001/OpenSound](https://github.com/noppakorn001/OpenSound/fork) on GitHub, then clone **your fork** locally.
2. In that checkout, add the original project as an upstream remote:

   ```sh
   git remote add upstream https://github.com/noppakorn001/OpenSound.git
   git switch -c describe-your-change
   git config --local core.hooksPath .githooks
   ```

3. Set a GitHub no-reply commit email in this checkout before committing. Copy your own no-reply address from GitHub Settings → Emails; do not copy the maintainer's identity. The privacy guard requires no-reply commit identities.
4. Follow [development setup](docs/DEVELOPMENT.md), make a focused change and run the relevant checks.
5. Stage only intended files, inspect `git diff --cached`, commit, run `python3 scripts/check-public-privacy.py`, and push your branch to your fork.
6. Open a pull request against `noppakorn001/OpenSound:main`. Describe the problem, resulting behavior and validation. Documentation-only changes do not require Bluetooth hardware tests.

To update your branch, fetch upstream and merge `upstream/main`. Avoid unrelated formatting changes. The maintainer reviews pull requests; opening an issue first is useful for large architectural changes but is not required for small fixes. No separate contributor agreement or CLA is required. By submitting a contribution, you confirm you have the right to contribute it and license your original code/documentation under MIT; retain notices and compatible licenses for third-party work. Do not submit artwork with uncertain redistribution rights.

## Useful contributions

- Improve English documentation, accessibility and reproducible bug reports.
- Add sanitized protocol fixtures and malformed-input tests.
- Implement a missing capability format with evidence and readback.
- Report a new model using the device compatibility issue form.
- Review [missing features](docs/MISSING_FEATURES.md) and [device support](docs/DEVICE_SUPPORT.md) before starting a feature.

All visible app strings remain English. The portrait interface, Menu Bar access, capability-gated controls and explicit write confirmation are intentional. Check [the interface guide](docs/INTERFACE.md) before changing those behaviors.

## Protocol and device changes

For a new model, include model/firmware, protocol table, advertised support identifiers, successful reads, failed reads and writes confirmed by device readback. A transport ACK alone does not prove a setting was accepted. Restore original settings after a live test. Do not claim all-model compatibility from a device name or static declaration.

For a protocol change, cite a pinned, compatibly licensed reference or precise metadata provenance, describe the field layout, and test truncated payloads, invalid enums, unsupported capabilities and preservation of unrelated fields. Never send guessed offsets or undocumented update commands to a device. Firmware flashing and cloud/account services remain outside the current implementation.

## Privacy and review

Do not contribute proprietary IPA contents, extracted artwork, credentials, Sony account information, Bluetooth addresses, personal device names or unredacted logs. Read [publication privacy](docs/PUBLICATION_PRIVACY.md) and manually review screenshots. The pre-push hook checks tracked files, history and commit identities; it cannot detect every private detail. GitHub CI runs after publication and cannot prevent an initial disclosure.

Use [issues](https://github.com/noppakorn001/OpenSound/issues) for sanitized bugs, model reports and feature proposals. Use [private vulnerability reporting](https://github.com/noppakorn001/OpenSound/security/advisories/new) for security issues. See [support](SUPPORT.md) and [community conduct](CODE_OF_CONDUCT.md).
