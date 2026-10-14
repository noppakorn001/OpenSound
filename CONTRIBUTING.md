# Contributing

Use a GitHub no-reply commit email and run `python3 scripts/check-public-privacy.py` before pushing. Enable the local guard with `git config --local core.hooksPath .githooks`. See [publication privacy](docs/PUBLICATION_PRIVACY.md) for the checks and their limitations.

Build with `scripts/build.sh`, run `scripts/test.sh`, and run `python3 tests/FeatureCatalogTests.py`. Keep all visible app strings in English. The portrait interface and capability-based controls are intentional.

For a new headphone model, report its model and firmware, selected MDR protocol table, advertised support identifiers, successful reads, failed reads, and changes confirmed by readback. A transport ACK alone does not prove that a setting was accepted. Test restoration of the original settings. Do not claim all-model compatibility from a device name or static declaration.

For a protocol change, cite the pinned MIT reference or exact local binary metadata used, record the field layout, and add tests for truncated payloads, invalid enums, unsupported capabilities, and preservation of unrelated fields. Do not send guessed offsets or undocumented update commands to a device.

Do not contribute proprietary IPA contents, extracted artwork, credentials, Sony account information, Bluetooth addresses, or unredacted logs. Keep firmware flashing and cloud features outside the headphone-control implementation until separately designed and reviewed.

Use `scripts/package-source.sh` for the public source package. Changes to the protocol catalogue should retain provenance and clearly distinguish declarations from implemented and hardware-tested behavior.
