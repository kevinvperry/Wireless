CREATE TABLE mutation_locks (station_id TEXT NOT NULL, expected_version INTEGER NOT NULL, mutation_id TEXT NOT NULL UNIQUE, PRIMARY KEY(station_id,expected_version));
