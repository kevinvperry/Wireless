PRAGMA foreign_keys = ON;
CREATE TABLE catalogue_meta (id INTEGER PRIMARY KEY CHECK(id=1), revision INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL);
INSERT INTO catalogue_meta VALUES(1,1,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
CREATE TABLE stations (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL CHECK(length(name) BETWEEN 1 AND 160),
  network TEXT NOT NULL DEFAULT '',
  country TEXT NOT NULL DEFAULT 'AU' CHECK(length(country)=2),
  state TEXT NOT NULL DEFAULT '',
  cities_json TEXT NOT NULL DEFAULT '[]' CHECK(json_valid(cities_json)),
  tags_json TEXT NOT NULL DEFAULT '[]' CHECK(json_valid(tags_json)),
  description TEXT NOT NULL DEFAULT '',
  website_url TEXT NOT NULL DEFAULT '',
  logo_url TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','archived')),
  preferred_stream_id TEXT,
  research_id TEXT UNIQUE,
  aliases_json TEXT NOT NULL DEFAULT '[]' CHECK(json_valid(aliases_json)),
  editorial_notes TEXT NOT NULL DEFAULT '',
  version INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  updated_by TEXT NOT NULL DEFAULT 'research-import'
);
CREATE INDEX stations_catalogue ON stations(status,name COLLATE NOCASE,id);
CREATE INDEX stations_network ON stations(status,network);
CREATE INDEX stations_state ON stations(status,state);
CREATE TABLE streams (
  id TEXT PRIMARY KEY,
  station_id TEXT NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
  url TEXT NOT NULL,
  label TEXT NOT NULL DEFAULT '',
  format TEXT NOT NULL DEFAULT 'unknown' CHECK(format IN ('hls','mp3','aac','flac','ogg','other','unknown')),
  codec TEXT NOT NULL DEFAULT '',
  bitrate_kbps REAL,
  sample_rate_hz INTEGER,
  channels INTEGER,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0,1)),
  verification_status TEXT NOT NULL DEFAULT 'unverified' CHECK(verification_status IN ('audio_decoded','unverified','failed')),
  checked_at TEXT,
  decoded_seconds REAL,
  request_headers_json TEXT NOT NULL DEFAULT '{}' CHECK(json_valid(request_headers_json)),
  source_name TEXT NOT NULL DEFAULT '',
  source_url TEXT NOT NULL DEFAULT '',
  evidence_json TEXT NOT NULL DEFAULT '{}' CHECK(json_valid(evidence_json)),
  UNIQUE(station_id,url)
);
CREATE INDEX streams_station ON streams(station_id,enabled);
CREATE TABLE editors (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE NOT NULL COLLATE NOCASE,
  display_name TEXT NOT NULL DEFAULT '',
  role TEXT NOT NULL CHECK(role IN ('admin','editor')),
  password_hash TEXT,
  disabled INTEGER NOT NULL DEFAULT 0 CHECK(disabled IN (0,1)),
  must_change_password INTEGER NOT NULL DEFAULT 0 CHECK(must_change_password IN (0,1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY,
  editor_id TEXT NOT NULL REFERENCES editors(id) ON DELETE CASCADE,
  csrf_token TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX sessions_expiry ON sessions(expires_at);
CREATE TABLE login_limits (key TEXT PRIMARY KEY, attempts INTEGER NOT NULL, resets_at INTEGER NOT NULL);
CREATE TABLE audit_log (
  id TEXT PRIMARY KEY,
  actor_id TEXT NOT NULL,
  actor_email TEXT NOT NULL,
  action TEXT NOT NULL,
  station_id TEXT,
  details_json TEXT NOT NULL CHECK(json_valid(details_json)),
  created_at TEXT NOT NULL
);
CREATE INDEX audit_recent ON audit_log(created_at DESC);
CREATE TABLE import_runs (id TEXT PRIMARY KEY, source TEXT NOT NULL, imported_at TEXT NOT NULL, record_count INTEGER NOT NULL);
