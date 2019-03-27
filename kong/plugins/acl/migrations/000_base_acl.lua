return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "acls" (
        "id"           UUID                         PRIMARY KEY,
        "created_at"   TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "consumer_id"  UUID                         REFERENCES "consumers" ("id") ON DELETE CASCADE,
        "group"        TEXT
      );

      CREATE INDEX IF NOT EXISTS "acls_consumer_id" ON "acls" ("consumer_id");
      CREATE INDEX IF NOT EXISTS "acls_group"       ON "acls" ("group");
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS acls(
        id          uuid PRIMARY KEY,
        created_at  timestamp,
        consumer_id uuid,
        group       text
      );
      CREATE INDEX IF NOT EXISTS ON acls(group);
      CREATE INDEX IF NOT EXISTS ON acls(consumer_id);
    ]],
  },

  mysql = {
    up = [[
      CREATE TABLE IF NOT EXISTS acls(
        `id` varchar(50) NOT NULL,
        `consumer_id` varchar(50),
        `group` varchar(500),
        `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        `cache_key` varchar(255),
        PRIMARY KEY (`id`),
        INDEX acls_group_idx(`group`),
        INDEX acls_consumer_id_idx(`consumer_id`),
        CONSTRAINT acls_consumerid_fk FOREIGN KEY (consumer_id) REFERENCES consumers(id) ON DELETE CASCADE,
        INDEX acls_cache_key_idx(`cache_key`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;
    ]]
  }
}
