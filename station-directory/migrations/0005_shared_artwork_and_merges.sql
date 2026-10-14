ALTER TABLE stations ADD COLUMN merge_archive_json TEXT NOT NULL DEFAULT '[]' CHECK(json_valid(merge_archive_json));
CREATE TABLE artwork_assets (
  id TEXT PRIMARY KEY,
  object_key TEXT UNIQUE NOT NULL,
  url TEXT UNIQUE NOT NULL,
  content_type TEXT NOT NULL,
  byte_count INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  created_by TEXT NOT NULL
);
CREATE INDEX artwork_assets_recent ON artwork_assets(created_at DESC);
