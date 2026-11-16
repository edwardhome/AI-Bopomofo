-- Copyright (c) 2026 AI-Bopomofo contributors. MIT.
PRAGMA application_id=1095320140;
PRAGMA user_version=2;
CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE origins (id TEXT PRIMARY KEY, subject_id TEXT NOT NULL, source TEXT NOT NULL, reference TEXT NOT NULL);
CREATE TABLE concepts (id TEXT PRIMARY KEY, definition TEXT NOT NULL, domain TEXT NOT NULL);
CREATE TABLE forms (id TEXT PRIMARY KEY, text TEXT NOT NULL, kind TEXT NOT NULL);
CREATE TABLE names (id TEXT PRIMARY KEY, concept_id TEXT NOT NULL, form_id TEXT NOT NULL, source TEXT NOT NULL);
CREATE TABLE readings (id TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE pronunciations (id TEXT PRIMARY KEY, name_id TEXT NOT NULL, reading_id TEXT NOT NULL, source TEXT NOT NULL);
CREATE TABLE bindings (id TEXT PRIMARY KEY, name_id TEXT NOT NULL, reading_id TEXT NOT NULL, code TEXT NOT NULL, term_type TEXT NOT NULL, source TEXT NOT NULL);
CREATE TABLE relations (id TEXT PRIMARY KEY, source_id TEXT NOT NULL, target_id TEXT NOT NULL, kind TEXT NOT NULL, source TEXT NOT NULL);
CREATE TABLE legacy_links (source_id TEXT NOT NULL, target_id TEXT NOT NULL, PRIMARY KEY (source_id, target_id));
