return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "keyauth_credentials" (
        "id"           UUID                         PRIMARY KEY,
        "created_at"   TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "consumer_id"  UUID                         REFERENCES "consumers" ("id") ON DELETE CASCADE,
        "key"          TEXT                         UNIQUE
      );

      CREATE INDEX IF NOT EXISTS "keyauth_consumer_idx" ON "keyauth_credentials" ("consumer_id");
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS keyauth_credentials(
        id          uuid PRIMARY KEY,
        created_at  timestamp,
        consumer_id uuid,
        key         text
      );
      CREATE INDEX IF NOT EXISTS ON keyauth_credentials(key);
      CREATE INDEX IF NOT EXISTS ON keyauth_credentials(consumer_id);
    ]],
  },

  mysql = {
    up = [[
      CREATE TABLE IF NOT EXISTS keyauth_credentials(
        id varchar(50),
        consumer_id varchar(50),
        `key` varchar(100) UNIQUE,
        created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        CONSTRAINT keyauth_consumerid_fk FOREIGN KEY (consumer_id) REFERENCES consumers(id) ON DELETE CASCADE ,  
        PRIMARY KEY (id),
        INDEX keyauth_key_idx(`key`),
        INDEX keyauth_credentials_consumer_id_idx(consumer_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;
    ]]
  }
}
