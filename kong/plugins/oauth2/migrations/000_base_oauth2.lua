return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "oauth2_credentials" (
        "id"             UUID                         PRIMARY KEY,
        "created_at"     TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "name"           TEXT,
        "consumer_id"    UUID                         REFERENCES "consumers" ("id") ON DELETE CASCADE,
        "client_id"      TEXT                         UNIQUE,
        "client_secret"  TEXT,
        "redirect_uri"   TEXT
      );

      CREATE INDEX IF NOT EXISTS "oauth2_credentials_consumer_idx" ON "oauth2_credentials" ("consumer_id");
      CREATE INDEX IF NOT EXISTS "oauth2_credentials_secret_idx"   ON "oauth2_credentials" ("client_secret");



      CREATE TABLE IF NOT EXISTS "oauth2_authorization_codes" (
        "id"                    UUID                         PRIMARY KEY,
        "created_at"            TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "credential_id"         UUID                         REFERENCES "oauth2_credentials" ("id") ON DELETE CASCADE,
        "service_id"            UUID                         REFERENCES "services" ("id") ON DELETE CASCADE,
        "api_id"                UUID                         REFERENCES "apis" ("id") ON DELETE CASCADE,
        "code"                  TEXT                         UNIQUE,
        "authenticated_userid"  TEXT,
        "scope"                 TEXT
      );

      CREATE INDEX IF NOT EXISTS "oauth2_authorization_userid_idx" ON "oauth2_authorization_codes" ("authenticated_userid");



      CREATE TABLE IF NOT EXISTS "oauth2_tokens" (
        "id"                    UUID                         PRIMARY KEY,
        "created_at"            TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "credential_id"         UUID                         REFERENCES "oauth2_credentials" ("id") ON DELETE CASCADE,
        "service_id"            UUID                         REFERENCES "services" ("id") ON DELETE CASCADE,
        "api_id"                UUID                         REFERENCES "apis" ("id") ON DELETE CASCADE,
        "access_token"          TEXT                         UNIQUE,
        "refresh_token"         TEXT                         UNIQUE,
        "token_type"            TEXT,
        "expires_in"            INTEGER,
        "authenticated_userid"  TEXT,
        "scope"                 TEXT
      );

      CREATE INDEX IF NOT EXISTS "oauth2_token_userid_idx" ON "oauth2_tokens" ("authenticated_userid");
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS oauth2_credentials(
        id            uuid PRIMARY KEY,
        created_at    timestamp,
        consumer_id   uuid,
        client_id     text,
        client_secret text,
        name          text,
        redirect_uri  text
      );
      CREATE INDEX IF NOT EXISTS ON oauth2_credentials(client_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_credentials(consumer_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_credentials(client_secret);



      CREATE TABLE IF NOT EXISTS oauth2_authorization_codes(
        id                   uuid PRIMARY KEY,
        created_at           timestamp,
        service_id           uuid,
        api_id               uuid,
        credential_id        uuid,
        authenticated_userid text,
        code                 text,
        scope                text
      ) WITH default_time_to_live = 300;
      CREATE INDEX IF NOT EXISTS ON oauth2_authorization_codes(code);
      CREATE INDEX IF NOT EXISTS ON oauth2_authorization_codes(api_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_authorization_codes(service_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_authorization_codes(credential_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_authorization_codes(authenticated_userid);



      CREATE TABLE IF NOT EXISTS oauth2_tokens(
        id                   uuid PRIMARY KEY,
        created_at           timestamp,
        service_id           uuid,
        api_id               uuid,
        credential_id        uuid,
        access_token         text,
        authenticated_userid text,
        refresh_token        text,
        scope                text,
        token_type           text,
        expires_in           int
      );
      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(api_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(service_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(access_token);
      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(refresh_token);
      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(credential_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(authenticated_userid);
    ]],
  },

  mysql = {
    up = [[
      CREATE TABLE IF NOT EXISTS oauth2_credentials(
        id varchar(50),
        name varchar(100),
        consumer_id varchar(50) ,
        client_id varchar(100) UNIQUE,
        client_secret varchar(200) UNIQUE,
        redirect_uri varchar(1000),
        redirect_uris text,
        created_at timestamp   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        CONSTRAINT oauth2_cred_consumerid_fk FOREIGN KEY (consumer_id) REFERENCES consumers(id) ON DELETE CASCADE , 
        INDEX oauth2_credentials_consumer_idx(consumer_id),
        INDEX oauth2_credentials_client_idx(client_id),
        INDEX oauth2_credentials_secret_idx(client_secret)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;

      CREATE TABLE IF NOT EXISTS oauth2_authorization_codes(
        id varchar(50),
        credential_id varchar(50)  ,
        code varchar(100) UNIQUE,
        authenticated_userid varchar(100),
        scope varchar(200),
        api_id varchar(50) ,
        service_id varchar(50) , 
        created_at timestamp   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        ttl timestamp   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        CONSTRAINT oauth2_authtoken_cred_fk FOREIGN KEY (credential_id) REFERENCES oauth2_credentials(id) ON DELETE CASCADE , 
        CONSTRAINT oauth2_authtoken_apiid_fk FOREIGN KEY (api_id) REFERENCES apis(id) ON DELETE CASCADE , 
        INDEX oauth2_autorization_code_idx(code),
        INDEX oauth2_authorization_userid_idx(authenticated_userid),
        INDEX oauth2_authorization_credential_id_idx(credential_id),
        INDEX oauth2_authorization_service_id_idx(service_id),
        INDEX oauth2_authorization_api_id_idx(api_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;

      CREATE TABLE IF NOT EXISTS oauth2_tokens(
        id varchar(50),
        credential_id varchar(50)  ,
        access_token varchar(200) UNIQUE,
        token_type varchar(50),
        refresh_token varchar(200) UNIQUE,
        expires_in int,
        authenticated_userid varchar(100),
        scope varchar(200),
        api_id varchar(50),
        service_id varchar(50), 
        created_at timestamp   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        ttl timestamp   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        CONSTRAINT oauth2_token_cred_fk FOREIGN KEY (credential_id) REFERENCES oauth2_credentials(id) ON DELETE CASCADE , 
        CONSTRAINT oauth2_token_apiid_fk FOREIGN KEY (api_id) REFERENCES apis(id) ON DELETE CASCADE , 
        INDEX oauth2_accesstoken_idx(access_token),
        INDEX oauth2_token_refresh_idx(refresh_token),
        INDEX oauth2_token_userid_idx(authenticated_userid),
        INDEX oauth2_tokens_credential_id_idx(credential_id),
        INDEX oauth2_tokens_service_id_idx(service_id),
        INDEX oauth2_tokens_api_id_idx(api_id)
      )ENGINE=InnoDB DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;
    ]],
  }
}
