# Release 0.1.0 — blocked

**Status:** pending external credentials  
**Scope:** W10 T10.1 packaging script delivered; formal notarization not executed in CI or agent environment.

## Blocker

Developer ID Application certificate, Apple Team ID, and Keychain profile `temperature-monitor-notary` are maintainer-supplied secrets and are not available in this repository.

## Local delivery (complete)

W01–W09 local ad-hoc App: `build/TemperatureMonitor.app`  
Hardware qualification: `docs/validation/product-hardware/Mac16,13-24G419/14cac6f…/`

## To produce notarized ZIP (maintainer machine)

```sh
export DEVELOPER_ID_APPLICATION="Developer ID Application: …"
export APPLE_TEAM_ID="…"
# Keychain profile temperature-monitor-notary must exist (xcrun notarytool store-credentials)
bash scripts/package-release.sh
```

Expected artifacts: `build/TemperatureMonitor-notarized.zip`, `build/release-manifest.json`, updated manifest under this directory.
