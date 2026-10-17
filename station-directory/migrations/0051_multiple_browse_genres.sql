-- Permit a station to appear in additional controlled Discover genre lists.
ALTER TABLE stations ADD COLUMN browse_genres_json TEXT NOT NULL DEFAULT '[]' CHECK(json_valid(browse_genres_json));

UPDATE stations
SET browse_genres_json='["Retail"]',
    editorial_notes=trim(editorial_notes || ' Added Retail as a secondary Discover genre on 2026-10-15. Tradie remains the primary genre.'),
    version=version+1,
    updated_at=strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    updated_by='genre-audit'
WHERE id='station_fbbe19492e7c' AND version=8 AND music_genre='Tradie';

INSERT INTO audit_log(id,actor_id,actor_email,action,station_id,details_json,created_at)
VALUES(
  'bunnings-tradio-multiple-genres-2026-10-15','system','system@wireless.local',
  'station.browse_genres_updated','station_fbbe19492e7c',
  '{"primary_genre":"Tradie","additional_browse_genres":["Retail"],"version":9}',
  strftime('%Y-%m-%dT%H:%M:%fZ','now')
);

UPDATE catalogue_meta
SET revision=revision+1,updated_at=strftime('%Y-%m-%dT%H:%M:%fZ','now')
WHERE id=1;
