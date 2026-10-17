-- Controlled primary music styles, shared by the editor and public catalogue.
CREATE TABLE music_genres (
  name TEXT PRIMARY KEY CHECK(length(name) BETWEEN 1 AND 80),
  description TEXT NOT NULL DEFAULT ''
);
INSERT INTO music_genres(name,description) VALUES
('Australian Hits','Music from Australian artists across pop and rock.'),
('Classic Hits','Familiar hits from past decades, including dedicated decade stations.'),
('Classical & Jazz','Classical music, jazz and fine-music programming.'),
('Country','Australian and international country music.'),
('Dance & Electronic','Dance music, electronic music, DJ mixes and remixes.'),
('Easy Listening','Relaxed favourites and softer music.'),
('Eclectic','A broad mix of specialist music styles and programmes.'),
('Pop','Contemporary pop and chart favourites.'),
('R&B & Hip-Hop','Rhythm and blues, hip-hop and related music.'),
('Rock','Rock, alternative rock and classic rock.');
ALTER TABLE stations ADD COLUMN music_genre TEXT REFERENCES music_genres(name);
CREATE INDEX stations_music_genre ON stations(music_genre,status);
