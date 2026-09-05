-- up
CREATE TABLE users (id TEXT PRIMARY KEY, email TEXT NOT NULL, legacy_plan TEXT);
-- down
DROP TABLE users;
