# Release 0.1.0 — waived (local-only delivery)

**Status:** not required  
**Decision:** 2026-09-23 maintainer — app runs locally only; no Mac App Store; no notarized distribution to other users.

## Delivery tier

| Tier | Status |
|------|--------|
| Local ad-hoc App (`build/TemperatureMonitor.app`) | **complete** (W08/W09) |
| Notarized ZIP (`TemperatureMonitor-notarized.zip`) | **waived** |

`scripts/package-release.sh` remains optional tooling if distribution requirements change later. It is not a project exit gate.

## Build locally

```sh
bash scripts/build-app.sh
open build/TemperatureMonitor.app
```

Hardware qualification: `docs/validation/product-hardware/Mac16,13-24G419/14cac6f…/`
