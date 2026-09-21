#!/usr/bin/env python3
"""Derive observations from raw rows; never assign unspecified pass thresholds."""
import csv
import json
import math
import pathlib
import statistics
import sys
from collections import Counter, defaultdict

root = pathlib.Path(sys.argv[1])
with (root / "timing.csv").open() as stream:
    timings = list(csv.DictReader(stream))
with (root / "sampling-results.csv").open() as stream:
    readings = list(csv.DictReader(stream))

def distribution(values):
    if not values:
        return None
    values = sorted(values)
    return {"count": len(values), "median": statistics.median(values),
            "p95": values[math.ceil(0.95 * len(values)) - 1], "max": max(values)}

groups = defaultdict(list)
for row in timings:
    groups[(int(row["cpu_interval_ms"]), row["group"])].append(row)
group_summary = []
for (interval, group), rows in sorted(groups.items()):
    starts = [int(row["batch_start_ns"]) for row in rows]
    group_summary.append({
        "cpuIntervalMS": interval, "group": group,
        "intervalMS": distribution([(b - a) / 1e6 for a, b in zip(starts, starts[1:])]),
        "batchReadMS": distribution([(int(row["batch_end_ns"]) - int(row["batch_start_ns"])) / 1e6 for row in rows]),
        "latenessMS": distribution([int(row["lateness_ns"]) / 1e6 for row in rows]),
    })
sensor_rows = defaultdict(list)
for row in readings:
    sensor_rows[(row["provider"], row["raw_id"])].append(row)
sensor_summary = []
for (provider, identifier), rows in sorted(sensor_rows.items()):
    values = [float(row["celsius"]) for row in rows if row["celsius"]]
    if not all(math.isfinite(value) for value in values):
        raise SystemExit(f"Nonfinite numeric CSV value in {provider}:{identifier}")
    sensor_summary.append({
        "provider": provider, "rawID": identifier, "rows": len(rows), "finiteRows": len(values),
        "statuses": dict(Counter(row["status"] for row in rows)),
        "minimumCelsius": min(values) if values else None,
        "maximumCelsius": max(values) if values else None,
        "distinctNumericValues": len(set(values)),
        "mappingAndFreshness": "not inferred from variation or repeated values",
    })

phases = json.loads((root / "summary.json").read_text())
for phase in phases:
    selected = [row for row in readings if int(row["cpu_interval_ms"]) == phase["cpuIntervalMS"]]
    assert len(selected) == phase["readings"], "Raw row count disagrees with summary"
    assert sum(bool(row["celsius"]) for row in selected) == phase["finiteReadings"]
    for group, expected in phase["expectedOpportunities"].items():
        observed = len(groups[(phase["cpuIntervalMS"], group)])
        assert observed == phase["startedBatches"][group]
        assert expected - observed == phase["missedOpportunities"][group]

result = {"method": "median; nearest-rank p95; monotonic timestamps; same values remain valid numeric readings",
          "groups": group_summary, "sensors": sensor_summary, "phases": phases}
(root / "analysis.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({"rows": len(readings), "batches": len(timings), "sensors": len(sensor_summary),
                  "cpuTiming": [group for group in group_summary if group["group"] == "cpu_candidates"]}, indent=2))
