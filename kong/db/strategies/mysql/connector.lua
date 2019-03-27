local logger       = require "kong.cmd.utils.log"
local mysql        = require "kong.tools.mysql"

local setmetatable = setmetatable
local concat       = table.concat
--local pairs        = pairs
--local type         = type
local ngx          = ngx
local get_phase    = ngx.get_phase
local null         = ngx.null
local log          = ngx.log
local match        = string.match
local cjson        = require "cjson"
local cjson_safe   = require "cjson.safe"
local stringx      = require "pl.stringx"
local arrays       = require "pgmoon.arrays"
local encode_array = arrays.encode_array
local error        = error
local concat       = table.concat
local sub          = string.sub
local gsub         = string.gsub
local gmatch       = string.gmatch
local fmt          = string.format
local string_len = string.len
local update_time  = ngx.update_time
local now          = ngx.now

local WARN                          = ngx.WARN
local SQL_INFORMATION_SCHEMA_TABLES = [[
SELECT table_name
  FROM information_schema.tables
 WHERE table_schema = database();
]]
local PROTECTED_TABLES = {
  schema_migrations = true,
  schema_meta       = true,
  locks             = true,
}

local function now_updated()
  update_time()
  return now()
end


local function iterator(rows)
  local i = 0
  return function()
    i = i + 1
    return rows[i]
  end
end

local setkeepalive


local function connect(config)
  local phase  = get_phase()
  if phase == "init" or phase == "init_worker" or ngx.IS_CLI then
    -- Force LuaSocket usage in the CLI in order to allow for self-signed
    -- certificates to be trusted (via opts.cafile) in the resty-cli
    -- interpreter (no way to set lua_ssl_trusted_certificate).
    config.socket_type = "luasocket"

  else
    config.socket_type = "nginx"
  end

  local connection = mysql.new()

  connection.convert_null = true
  connection.NULL         = null

  local ok, err = connection:connect(config)
  if not ok then
    return nil, err
  end

  connection:set_timeout(3000)

  return connection
end



setkeepalive = function(connection)
  if not connection or not connection.sock then
    return nil, "no active connection"
  end

  local ok, err
  if connection.sock_type == "luasocket" then
    ok, err = connection:close()
    if not ok then
      if err then
        log(WARN, "unable to close mysql connection (", err, ")")

      else
        log(WARN, "unable to close mysql connection")
      end

      return nil, err
    end

  else
    ok, err = connection:set_keepalive(1000,10)
    if not ok then
      if err then
        log(WARN, "unable to set keepalive for mysql connection (", err, ")")

      else
        log(WARN, "unable to set keepalive for mysql connection")
      end

      return nil, err
    end
  end

  return true
end

local _mt = {}


_mt.__index = _mt


function _mt:escape_identifier(field)
  return ngx.quote_sql_str(field)
end


function _mt:escape_literal(field)
  return ngx.quote_sql_str(tostring(field))
end


function _mt:get_stored_connection()
  if self.connection and self.connection.sock then
    return self.connection
  end

  local connection, err = connect(self.config)
  if not connection then
    return nil
  end
  return connection
end


function _mt:init()
  local res, err = self:query("select version() as server_version_num;")
  local ver = res and res[1] and res[1].server_version_num
  if not ver then
    return nil, "failed to retrieve server_version_num: " .. err
  end

  local verlist = stringx.split(ver,".")
  self.major_version       = tostring(verlist[1])
  self.major_minor_version = fmt("%u.%u", verlist[1], verlist[2])
  return true
end


function _mt:infos()
  local db_ver
  if self.major_minor_version then
    db_ver = match(self.major_minor_version, "^(%d+%.%d+)")
  end

  return {
    strategy = "mysql",
    db_name  = self.config.database,
    db_desc  = "database",
    db_ver   = db_ver or "unknown",
  }
end


function _mt:connect()
  if self.connection and self.connection.sock then
    return true
  end

  local connection, err = connect(self.config)
  if not connection then
    return nil, err
  end

  self.connection = connection

  return true
end


function _mt:connect_migrations()
  return self:connect()
end


function _mt:close()
  local conn = self:get_stored_connection()
  if not conn then
    return true
  end

  -- local _, err = setkeepalive(conn)

  self:store_connection(nil)

  -- if err then
  --   return nil, err
  -- end

  return true
end


function _mt:setkeepalive()
  local ok, err = setkeepalive(self.connection)

  self.connection = nil

  if not ok then
    return nil, err
  end

  return true
end


function _mt:query(sql)
  local connection, errtmp
  if self.connection and self.connection.sock then
    connection = self.connection
  end

  connection, errtmp = connect(self.config)
  if not connection then
    return nil, errtmp
  end

  local res, err = connection:query(sql)
  
  local ml = {}
  while err == "again" do
    local res1, err1, errcode1, sqlstate1 = connection:read_result()
    err = err1
    if not res1 then
        logger.verbose("bad result #" .. tostring(err1))
    else
        table.insert(ml,res1)
    end
  end
  if err then
    logger.verbose("sql:" .. sql .. " err:" .. cjson.encode(err))
  end
  if #ml > 0 then
    res = ml[#ml-1]
  end

  if res and #res > 0 then
    for i=1,#res do
      if type(res[i]) == "table" then
        for k,v in pairs(res[i]) do
          if k == 'created_at' or k == 'updated_at' then
            local resTmpe,err = connection:query('SELECT UNIX_TIMESTAMP(\"' .. v .. '\") AS tmp;')
            if resTmpe and resTmpe[1] then
              res[i][k] = tonumber(resTmpe[1]['tmp'])
            end
          elseif k == 'regex_priority' then
            res[i][k] = tonumber(v)
          elseif k == 'strip_path' or k == 'preserve_host' then
            res[i][k] = true
            if v == 0 then
              res[i][k] = false
            end
          elseif type(v) == "string" then
            local m = cjson_safe.decode(v)
            if type(m) == "table" then
              res[i][k] = m
            end
          end
        end
      end
    end
  end

  logger.verbose("anssas:" .. cjson.encode(res) .. " tostring:" .. tostring(connection.state))
  setkeepalive(connection)

  return res, err
end


function _mt:iterate(sql)
  local res, err = self:query(sql)
  if not res then
    return nil, err, partial, num_queries
  end

  if res == true then
    return iterator { true }
  end

  return iterator(res)
end


function _mt:reset()
  local user = self:escape_identifier(self.config.user)
  local ok, err = self:query(concat {
    "BEGIN;\n",
    "DROP SCHEMA IF EXISTS public CASCADE;\n",
    "CREATE SCHEMA IF NOT EXISTS public AUTHORIZATION " .. user .. ";\n",
    "GRANT ALL ON SCHEMA public TO " .. user .. ";\n",
    "COMMIT;\n",
  })

  if not ok then
    return nil, err
  end

  return true
end


function _mt:truncate()
  local i, table_names = 0, {}

  for row in self:iterate(SQL_INFORMATION_SCHEMA_TABLES) do
    local table_name = row.table_name
    if table_name ~= "schema_migrations" then
      i = i + 1
      table_names[i] = self:escape_identifier(table_name)
    end
  end

  if i == 0 then
    return true
  end

  local truncate_statement = {
    "TRUNCATE TABLE ", concat(table_names, ", "), " RESTART IDENTITY CASCADE;"
  }

  local ok, err = self:query(truncate_statement)
  if not ok then
    return nil, err
  end

  return true
end


function _mt:truncate_table(table_name)
  local truncate_statement = concat {
    "TRUNCATE ", self:escape_identifier(table_name), " RESTART IDENTITY CASCADE;"
  }

  local ok, err = self:query(truncate_statement)
  if not ok then
    return nil, err
  end

  return true
end


function _mt:setup_locks(_, _)
  logger.verbose("creating 'locks' table if not existing...")

  local ok, err = self:query([[
  CREATE TABLE IF NOT EXISTS locks (
    `key`    varchar(1000) PRIMARY KEY,
    `owner`  TEXT,
    `ttl`    timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX locks_ttl_idx(ttl)
  );]])

  if not ok then
    return nil, err
  end

  logger.verbose("successfully created 'locks' table")

  return true
end


function _mt:insert_lock(key, ttl, owner)
  local ttl_escaped = concat {
                        "FROM_UNIXTIME(",
                        self:escape_literal(tonumber(fmt("%.3f", now_updated() + ttl))),
                        ")"
                      }

  local sql = concat {
                       "BEGIN;\n",
                       "  DELETE FROM locks\n",
                       "        WHERE ttl < CURRENT_TIMESTAMP;\n",
                       "  INSERT IGNORE INTO locks (`key`, `owner`, `ttl`)\n",
                       "       VALUES (", self:escape_literal(key),   ", ",
                                          self:escape_literal(owner), ", ",
                                          ttl_escaped, ");\n",
                       "COMMIT;\n",
  }

  local res, err = self:query(sql)
  if not res then
    return nil, err
  end

  if res.affected_rows == 1 then
    return true
  end

  return false
end


function _mt:read_lock(key)
  local sql = concat {
    "SELECT *\n",
    "  FROM locks\n",
    " WHERE `key` = ", self:escape_literal(key), "\n",
    "   AND ttl >= CURRENT_TIMESTAMP\n",
    " LIMIT 1;"
  }

  local res, err = self:query(sql)
  if not res then
    return nil, err
  end

  return res[1] ~= nil
end


function _mt:remove_lock(key, owner)
  local sql = concat {
    "DELETE FROM locks\n",
    "      WHERE `key`   = ", self:escape_literal(key), "\n",
         "   AND `owner` = ", self:escape_literal(owner), ";"
  }

  local res, err = self:query(sql)
  if not res then
    return nil, err
  end

  return true
end


function _mt:schema_migrations()
  local conn = self:get_stored_connection()
  if not conn then
    error("no connection")
  end

  local has_schema_meta_table
  for row in self:iterate(SQL_INFORMATION_SCHEMA_TABLES) do
    local table_name = row.table_name
    if table_name == "schema_meta" then
      has_schema_meta_table = true
      break
    end
  end

  if not has_schema_meta_table then
    -- database, but no schema_meta: needs bootstrap
    return nil
  end

  local sql = concat({
    "SELECT *\n",
    "  FROM schema_meta\n",
    " WHERE `key` = ",  self:escape_literal("schema_meta"), ";"
  })
  local rows, err = self:query(sql)
  if not rows then
    return nil, err
  end

  for _, row in ipairs(rows) do
    if row.pending == null then
      row.pending = nil
    end
  end

  -- no migrations: is bootstrapped but not migrated
  -- migrations: has some migrations
  return rows
end


function _mt:schema_bootstrap(kong_config, default_locks_ttl)
  local conn = self:get_stored_connection()
  if not conn then
    error("no connection")
  end

  -- create schema meta table if not exists

  logger.verbose("creating 'schema_meta' table if not existing...")

  local res, err = self:query([[
    CREATE TABLE IF NOT EXISTS schema_meta (
      `key`            varchar(256),
      `subsystem`      varchar(256),
      `last_executed`  TEXT,
      `executed`       TEXT,
      `pending`        TEXT,

      PRIMARY KEY (`key`, `subsystem`)
    );
    ]])

  if not res then
    return nil, err
  end

  logger.verbose("successfully created 'schema_meta' table")

  local ok
  ok, err = self:setup_locks(default_locks_ttl, true)
  if not ok then
    return nil, err
  end

  return true
end


function _mt:schema_reset()
  return self:reset()
end


function _mt:run_up_migration(name, up_sql)
  if type(name) ~= "string" then
    error("name must be a string", 2)
  end

  if type(up_sql) ~= "string" then
    error("up_sql must be a string", 2)
  end

  if string_len(up_sql) <= 4 then
    return true
  end

  local conn = self:get_stored_connection()
  if not conn then
    error("no connection")
  end

  local sql = stringx.strip(up_sql)
  if sub(sql, -1) ~= ";" then
    sql = sql .. ";"
  end

  local sqlOrg = concat {
    "BEGIN;\n",
    sql, "\n",
    "COMMIT;\n",
  }

  local res, err = self:query(sql)
  if not res then
    self:query("ROLLBACK;")
    return nil, err
  end

  return true
end


function _mt:record_migration(subsystem, name, state)
  if type(subsystem) ~= "string" then
    error("subsystem must be a string", 2)
  end

  if type(name) ~= "string" then
    error("name must be a string", 2)
  end

  local conn = self:get_stored_connection()
  if not conn then
    error("no connection")
  end

  local key_escaped  = self:escape_literal("schema_meta")
  local subsystem_escaped = self:escape_literal(subsystem)
  local name_escaped = self:escape_literal(name)
  local name_array   = self:escape_literal(cjson.encode({ name }))

  local sql
  if state == "executed" then
    sql = concat({
      "REPLACE INTO schema_meta (`key`, `subsystem`, `last_executed`, `executed`)\n",
      "     VALUES (", key_escaped, ", ", subsystem_escaped, ", ", name_escaped, ", ", name_array, ");\n",
    })

  elseif state == "pending" then
    sql = concat({
      "REPLACE INTO schema_meta (`key`, `subsystem`, `pending`)\n",
      "     VALUES (", key_escaped, ", ", subsystem_escaped, ", ", name_array, ");\n",
    })

  elseif state == "teardown" then
    sql = concat({
      "REPLACE INTO schema_meta (`key`, `subsystem`, `last_executed`, `executed`)\n",
      "     VALUES (", key_escaped, ", ", subsystem_escaped, ", ", name_escaped, ", ", name_array, ");\n",
    })

  else
    error("unknown 'state' argument: " .. tostring(state))
  end

  local res, err = self:query(sql)
  if not res then
    return nil, err
  end

  return true
end


local _M = {}

function _M.new(kong_config)
  local config = {
    host = kong_config.mysql_host,
    port = kong_config.mysql_port,
    user = kong_config.mysql_user,
    password = kong_config.mysql_password,
    database = kong_config.mysql_database,
    max_packet_size=1024*1024
  }

  local db = mysql.new()

  return setmetatable({
    config            = config,
    escape_identifier = db.escape_identifier,
    escape_literal    = db.escape_literal,
  }, _mt)
end


return _M
