import GRDB

enum Migrations {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE project (
                  id          TEXT PRIMARY KEY,
                  name        TEXT NOT NULL,
                  color       TEXT NOT NULL,
                  updated_at  INTEGER NOT NULL,
                  deleted_at  INTEGER,
                  dirty       INTEGER NOT NULL DEFAULT 1
                );

                CREATE TABLE tag (
                  id          TEXT PRIMARY KEY,
                  name        TEXT NOT NULL,
                  updated_at  INTEGER NOT NULL,
                  deleted_at  INTEGER,
                  dirty       INTEGER NOT NULL DEFAULT 1
                );

                CREATE TABLE time_block (
                  id          TEXT PRIMARY KEY,
                  title       TEXT NOT NULL DEFAULT '',
                  notes       TEXT NOT NULL DEFAULT '',
                  project_id  TEXT,
                  tag_ids     TEXT NOT NULL DEFAULT '[]',
                  start_at    INTEGER NOT NULL,
                  end_at      INTEGER,
                  updated_at  INTEGER NOT NULL,
                  deleted_at  INTEGER,
                  dirty       INTEGER NOT NULL DEFAULT 1,
                  CHECK (end_at IS NULL OR end_at > start_at)
                );

                CREATE INDEX time_block_start ON time_block (start_at);
                CREATE UNIQUE INDEX time_block_one_running ON time_block ((1)) WHERE end_at IS NULL AND deleted_at IS NULL;

                CREATE TABLE sync_state (
                  id              INTEGER PRIMARY KEY CHECK (id = 1),
                  server_url      TEXT,
                  cursor          TEXT,
                  last_synced_at  INTEGER
                );
                """)
        }
        return migrator
    }
}
