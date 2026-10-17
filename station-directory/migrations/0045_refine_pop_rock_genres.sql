-- Add reusable primary genres identified by the Pop and Rock station audit.
INSERT OR IGNORE INTO music_genres(name,description) VALUES
('Classic Rock','Rock favourites and anthems from earlier decades.'),
('Contemporary Hits','Current chart hits and recent mainstream favourites.'),
('Heavy Metal','Heavy metal, hard rock and related heavier styles.'),
('K-Pop','Korean pop and closely related Asian pop music.'),
('Soft Rock','Softer rock, adult-oriented rock and melodic favourites.');
