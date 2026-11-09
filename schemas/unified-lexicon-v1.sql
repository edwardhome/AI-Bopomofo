-- AI-Bopomofo portable lexicon SQLite 1.0.0. Copyright (c) 2026 contributors. MIT.
PRAGMA application_id=1095320140;
PRAGMA user_version=1;
CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE entries (entry_id TEXT PRIMARY KEY, position INTEGER NOT NULL UNIQUE, term_type TEXT NOT NULL, reading TEXT NOT NULL, text TEXT NOT NULL, payload TEXT NOT NULL);
CREATE TABLE relations (source_id TEXT NOT NULL, target_id TEXT NOT NULL, kind TEXT NOT NULL, PRIMARY KEY (source_id, target_id, kind));
