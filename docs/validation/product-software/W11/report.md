# W11 product software validation

**Status:** in progress (T11.1 started)  
**Source SHA:** `0b720deb1d7fe170e55999f2709a3665634746da`  
**Delivery scope:** local ad-hoc App complete; notarized ZIP waived (W10)

## T11.1 progress

| Metric | Count |
|--------|------:|
| Active requirements | 132 |
| Local acceptance bound | 123 |
| Waived (REQ-127 / TC-RELEASE) | 1 |
| Pending (TC-ACCEPTANCE meta, REQ-099..106) | 8 |

Catalog maps 19 TC groups to CI/hardware/mixed reports; only TC-ACCEPTANCE remains pending until the full matrix is reviewed.

## Tooling

- `docs/contracts/acceptance-evidence-catalog-v1.json` — TC → report/CI mapping
- `scripts/bind-acceptance-evidence.py` — applies catalog to `acceptance-v1.json` and syncs `17-traceability.md`
- `python3 scripts/validate-handoff.py --product-acceptance` — validates bound evidence paths and SHA fields

## Remaining

- Bind software TC groups (SCHEDULE..ERROR) where all mapped TCs for each REQ are evidenced
- Bind hardware TC groups (PLATFORM, LIFECYCLE) from W09 atomic qualification
- Bind UI TC evidence from W07/W08 reports
- TC-ACCEPTANCE meta reqs (099–106) after full matrix complete
- T11.2 independent review
- T11.3 delivery report at `docs/validation/product-software/W11/<head>/delivery.md`
