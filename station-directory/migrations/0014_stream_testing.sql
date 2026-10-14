CREATE TABLE stream_tests (
  stream_id TEXT PRIMARY KEY REFERENCES streams(id) ON DELETE CASCADE,
  station_id TEXT NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
  requested_url TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','testing','completed','failed')),
  requested_at TEXT NOT NULL,
  started_at TEXT,
  completed_at TEXT,
  requested_by TEXT NOT NULL DEFAULT '',
  result_json TEXT NOT NULL DEFAULT '{}' CHECK(json_valid(result_json)),
  error TEXT NOT NULL DEFAULT ''
);
CREATE INDEX stream_tests_pending ON stream_tests(status,requested_at);
