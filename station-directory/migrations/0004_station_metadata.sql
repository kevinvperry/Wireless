ALTER TABLE stations ADD COLUMN frequency TEXT NOT NULL DEFAULT '';
ALTER TABLE stations ADD COLUMN tagline TEXT NOT NULL DEFAULT '';
ALTER TABLE stations ADD COLUMN genres_json TEXT NOT NULL DEFAULT '[]' CHECK(json_valid(genres_json));
ALTER TABLE stations ADD COLUMN contact_json TEXT NOT NULL DEFAULT '{}' CHECK(json_valid(contact_json));
