-- up
ALTER TABLE users DROP COLUMN legacy_plan;
-- down
-- (column data cannot be restored)
