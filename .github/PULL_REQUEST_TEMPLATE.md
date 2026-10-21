## Change

Describe the concrete problem and resulting behavior. Link an issue if applicable.

## Validation

List checks you ran and their results. Mark checks as not applicable when appropriate (for example, documentation-only changes).

- Protocol/reconnect: `bash scripts/test.sh`
- Catalogue: `python3 tests/FeatureCatalogTests.py`
- Security: `bash scripts/security-test.sh`
- Source export: `python3 tests/SourceExportTests.py`
- Build: `bash scripts/build.sh`
- Privacy: `python3 scripts/check-public-privacy.py`

For hardware changes, specify model/firmware, capability evidence, confirmed readback and restoration. Never attach raw captures or device addresses.

## Contribution checks

- [ ] I have the right to contribute this work under the project's documented licensing terms and retained third-party notices.
- [ ] I removed personal information, credentials, proprietary binaries and unlicensed artwork.
- [ ] Compatibility claims distinguish implemented, offline-tested and hardware-verified behavior.
