-- Normative design schema, copied into the production package at task W03.
-- One disposable monitoring database per application session.
PRAGMA foreign_keys = ON;
PRAGMA page_size = 4096;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 0;
PRAGMA cache_size = -8192;
PRAGMA mmap_size = 0;
PRAGMA wal_autocheckpoint = 1000;
PRAGMA max_page_count = 262144;
PRAGMA user_version = 1;

CREATE TABLE session (
    session_id TEXT PRIMARY KEY NOT NULL,
    started_wall_ns INTEGER NOT NULL,
    model TEXT NOT NULL,
    os_build TEXT NOT NULL,
    app_version TEXT NOT NULL
);
CREATE TABLE sources (
    source_id TEXT PRIMARY KEY NOT NULL,
    session_id TEXT NOT NULL REFERENCES session(session_id),
    provider TEXT NOT NULL CHECK(provider IN ('smc','hid','nvme','iops')),
    raw_key TEXT NOT NULL COLLATE BINARY,
    registry_id TEXT,
    connection_generation INTEGER NOT NULL,
    kind TEXT NOT NULL CHECK(kind IN ('cpuZone','ssd','battery')),
    encoding TEXT NOT NULL,
    unit_evidence TEXT NOT NULL,
    mapping_version TEXT NOT NULL,
    evidence TEXT NOT NULL CHECK(evidence IN ('referenceClassified','targetQualified','unknown'))
);
CREATE TABLE series (
    series_id TEXT PRIMARY KEY NOT NULL,
    session_id TEXT NOT NULL REFERENCES session(session_id),
    metric_id TEXT NOT NULL,
    definition_version INTEGER NOT NULL CHECK(definition_version > 0),
    kind TEXT NOT NULL CHECK(kind IN ('cpuMain','cpuZone','ssd','battery')),
    display_name TEXT NOT NULL,
    formula TEXT NOT NULL CHECK(formula IN ('identity','max')),
    UNIQUE(session_id, metric_id, definition_version)
);
CREATE TABLE series_members (
    series_id TEXT NOT NULL REFERENCES series(series_id),
    source_id TEXT NOT NULL REFERENCES sources(source_id),
    ordinal INTEGER NOT NULL,
    PRIMARY KEY(series_id, source_id),
    UNIQUE(series_id, ordinal)
);
CREATE TABLE segments (
    series_id TEXT NOT NULL REFERENCES series(series_id),
    segment INTEGER NOT NULL,
    start_elapsed_ns INTEGER NOT NULL,
    start_wall_ns INTEGER NOT NULL,
    reason TEXT NOT NULL,
    PRIMARY KEY(series_id, segment)
);
CREATE TABLE raw_samples (
    sample_id TEXT PRIMARY KEY NOT NULL,
    series_id TEXT NOT NULL,
    segment INTEGER NOT NULL,
    elapsed_ns INTEGER NOT NULL CHECK(elapsed_ns >= 0),
    wall_ns INTEGER NOT NULL,
    period_ms INTEGER NOT NULL CHECK(period_ms IN (50,100,200,500,1000)),
    value_c REAL NOT NULL,
    freshness TEXT NOT NULL CHECK(freshness IN ('unknown','sourceTimestamp')),
    source_wall_ns INTEGER,
    FOREIGN KEY(series_id, segment) REFERENCES segments(series_id, segment)
);
CREATE INDEX raw_by_time ON raw_samples(elapsed_ns);
CREATE INDEX raw_by_series_time ON raw_samples(series_id, elapsed_ns);
CREATE TABLE sample_members (
    derived_sample_id TEXT NOT NULL REFERENCES raw_samples(sample_id) ON DELETE CASCADE,
    source_sample_id TEXT NOT NULL,
    PRIMARY KEY(derived_sample_id, source_sample_id)
    -- source_sample_id deliberately not a FK: member may expire milliseconds earlier.
);
CREATE TABLE ema_samples (
    sample_id TEXT PRIMARY KEY NOT NULL,
    series_id TEXT NOT NULL,
    segment INTEGER NOT NULL,
    elapsed_ns INTEGER NOT NULL,
    wall_ns INTEGER NOT NULL,
    value_c REAL NOT NULL,
    FOREIGN KEY(series_id, segment) REFERENCES segments(series_id, segment)
);
CREATE INDEX ema_by_time ON ema_samples(elapsed_ns);
CREATE INDEX ema_by_series_time ON ema_samples(series_id, elapsed_ns);
CREATE TABLE aggregates (
    series_id TEXT NOT NULL,
    segment INTEGER NOT NULL,
    width_s INTEGER NOT NULL CHECK(width_s IN (1,10,60)),
    start_elapsed_ns INTEGER NOT NULL,
    end_elapsed_ns INTEGER NOT NULL,
    min_c REAL NOT NULL,
    max_c REAL NOT NULL,
    sum_c REAL NOT NULL,
    latest_c REAL NOT NULL,
    latest_elapsed_ns INTEGER NOT NULL,
    latest_sample_id TEXT NOT NULL,
    sample_count INTEGER NOT NULL CHECK(sample_count > 0),
    coverage_ns INTEGER NOT NULL CHECK(coverage_ns >= 0),
    partial INTEGER NOT NULL CHECK(partial IN (0,1)),
    PRIMARY KEY(series_id, segment, width_s, start_elapsed_ns),
    FOREIGN KEY(series_id, segment) REFERENCES segments(series_id, segment),
    CHECK(end_elapsed_ns > start_elapsed_ns),
    CHECK(min_c <= max_c),
    CHECK(coverage_ns <= end_elapsed_ns - start_elapsed_ns)
);
CREATE INDEX aggregates_by_age ON aggregates(width_s, end_elapsed_ns);
CREATE INDEX aggregates_by_query ON aggregates(series_id, width_s, start_elapsed_ns);
-- Historical REQ table names are read-only views, not duplicate stored rows.
CREATE VIEW samples_1s AS SELECT *, sum_c/sample_count AS avg, latest_c AS latest, sample_count AS count FROM aggregates WHERE width_s=1;
CREATE VIEW samples_10s AS SELECT *, sum_c/sample_count AS avg, latest_c AS latest, sample_count AS count FROM aggregates WHERE width_s=10;
CREATE VIEW samples_1m AS SELECT *, sum_c/sample_count AS avg, latest_c AS latest, sample_count AS count FROM aggregates WHERE width_s=60;
CREATE TABLE trend_samples (
    series_id TEXT NOT NULL,
    segment INTEGER NOT NULL,
    elapsed_ns INTEGER NOT NULL,
    wall_ns INTEGER NOT NULL,
    slope_c_per_s REAL,
    direction TEXT NOT NULL CHECK(direction IN ('rising','falling','stable','insufficient')),
    point_count INTEGER NOT NULL CHECK(point_count >= 0),
    PRIMARY KEY(series_id, segment, elapsed_ns),
    FOREIGN KEY(series_id, segment) REFERENCES segments(series_id, segment),
    CHECK((direction='insufficient' AND slope_c_per_s IS NULL) OR (direction!='insufficient' AND slope_c_per_s IS NOT NULL))
);
CREATE INDEX trends_by_age ON trend_samples(elapsed_ns);
CREATE TABLE gaps (
    gap_id TEXT PRIMARY KEY NOT NULL,
    series_id TEXT NOT NULL REFERENCES series(series_id),
    start_elapsed_ns INTEGER NOT NULL,
    end_elapsed_ns INTEGER,
    reason TEXT NOT NULL,
    CHECK(end_elapsed_ns IS NULL OR end_elapsed_ns >= start_elapsed_ns)
);
CREATE INDEX gaps_by_age ON gaps(end_elapsed_ns);
CREATE TABLE committed_batches (
    batch_id TEXT PRIMARY KEY NOT NULL,
    committed_elapsed_ns INTEGER NOT NULL,
    payload_sha256 TEXT NOT NULL
);
