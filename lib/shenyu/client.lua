local http = require "http"
local json = require("cjson.safe")
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local lrucache = require("resty.lrucache.pureffi")

local ngx_time = ngx.time
local ngx_timer_at = ngx.timer.at
local ngx_worker_exiting = ngx.worker.exiting

local re = ngx.re.match

local ngx = ngx
local log = ngx.log
local ERR = ngx.ERR
local WARN = ngx.WARN
local INFO = ngx.INFO

local _M = {
  start_key = "/shenyu/register/instance/ ",
  end_key = "/shenyu/register/instance/~",
  revision = 0,
}

-- lua_shared_dict shenyu_server_list 1m
-- local _M.server_list = ngx.shared.shenyu_server_list

-- conf = {
--   balance_type = "chash",
--   shenyu_server_list = {},
--   etcd_base_url = "http://127.0.0.1:2379",
-- }
function _M.init(conf)
  if ngx.worker.id ~= 0 then
    return
  end

  if conf.balancer_type == "chash" then
    local balancer = require("resty.chash")
    _M.build_upstream_servers = function(servers)
      log(ERR, "not support yet.")
    end
    _M.balancer = balancer
  else
    local balancer = require("resty.roundrobin")
    _M.build_upstream_servers = function(servers)
      balancer:reinit(servers)
    end
    _M.balancer = balancer
  end

  -- Start the etcd watcher
  --local ok, err = ngx_timer_at(0, watch)
  --if not ok then
  --    log(ERR, "failed to start watch: " .. err)
  --end
end


function pick_and_set_peer()
  local server = _M.balancer.find()
  balancer.set_current_peer(server)
end


local function parse_base_url(base_url)
  local m, err = re(base_url, [=[([^\/]+):\/\/([\da-zA-Z.-]+|\[[\da-fA-F:]+\]):?(\d+)?(\/)?$]=], "jo")
  if not m then
    log(ERR, err)
  end

  local base_url = m[1] .. "://" .. m[2] .. ":" .. m[3]
  return {
    scheme = m[1],
    host = m[2],
    port = tonumber(m[3]),
    base_url = base_url,
    prefix = detect_etcd_version(base_url),
  }
end


-- <= 3.2 /v3alpha
-- = 3.3 /v3beta
-- >= 3.4 /v3
local function detect_etcd_version(base_url)
  local httpc = http.new()
  local res, err = httpc:request_uri(base_url .. "/version")
  if not res then
    log(ERR, "failed to get version from etcd server.", err)
  end

  local m
  local response = json.decode(res.body)
  m, err = re(response.etcdcluster, "^(\\d+)\\.(\\d+)\\.(\\d+)$")
  if not m then
    log(ERR, "failed to resolve etcd version.", err)
  end

  if tonumber(m[1]) ~= 3 then
    log(ERR, "support etcd v3 only.")
  end

  local ver_minor = tonumber(m[2])
  if ver_minor <= 2 then
    return "/v3alpha"
  elseif ver_minor == 3 then
    return "/v3beta"
  else
    return "/v3"
  end
end


local function fetch_shenyu_instances(etcd_conf, shenyu_server_list)
  local server_list = shenyu_server_list

  local range_request = {
    key = encode_base64(start_key),
    range_end = encode_base64(end_key),
  }
  local httpc = http.new()
  local res, err = httpc.request_uri(etcd_conf.base_url .. etcd_conf.prefix .. "/kv/range", {
    method = "POST",
    body = json.encode(range_request),
  })

  if not res then
    log(ERR, "failed to list shenyu instances from etcd", err)
  end

  -- server_list = {
  --   ["host:port"] = {
  --     host,
  --     port,
  --     ...
  --   }
  -- }
  local kvs = json.decode(res.body).kvs
  for _, kv in pairs(kvs) do
    update_revision(kv.mod_revision)
    server_list:set(kv.key, parse_value(kv.value))
  end

  build_server_list(server_list)
end


local function update_revision(mode_revision, force)
  if force and revision > mod_revision then
    log(ERR, "failed to update revision because the revision greater than specific")
    return
  end
  revision = mod_revision
end


local function watch(premature, etcd_conf, watching)
  if premature or ngx_worker_exiting() then
    return
  end

  local httpc = http.new()
  if not watching then
    local etcd_conf = parse_base_url(conf.etcd_base_url)

    _M.server_list = conf.shenyu_server_list
    fetch_shenyu_instances(etcd_conf, server_list)
    return
  end

  local ok, err = httpc:connect(etcd_conf.host, etcd_conf.port, {
    scheme = etcd_conf.scheme,
  })
  if not ok then
    -- return nil, "faliled to connect to etcd server", err
    log(ERR, "faliled to connect to etcd server", err)
  end

  -- message WatchCreateRequest {
  --   bytes key = 1;
  --   bytes range_end = 2;
  --   int64 start_revision = 3;
  --   bool progress_notify = 4;
  --   enum FilterType {
  --     NOPUT = 0;
  --     NODELETE = 1;
  --   }
  --   repeated FilterType filters = 5;
  --   bool prev_kv = 6;
  -- }
  local request = {
    create_request = {
      key = encode_base64(start_key),
      range_end = encode_base64(end_key),
      start_revision = _M.revision,
    }
  }

  local res, err = httpc:request({
    path = "/v3/watch",
    method = "POST",
    body = json.encode(request),
  })
  if not res then
    log(ERR, "failed to watch keys under '/shenyu/register/instance/'", err)
  end

  local reader = res.body_reader
  local buffer_size = 8192

  repeat
  	local buffer, err = reader(buffer_size)
  	if err then
      if err == "timeout" then
        ngx.log(ngx.ERROR, "============", err)
      end
      ngx.log(ngx.ERROR, err)
  	end

  	if buffer then
      print(buffer)
      parse_watch_response(buffer)
    end
  until not buffer

  local ok, err = ngx_timer_at(1, watch, etcd_conf, true)
  if not ok then
      log(ERR, "faield start watch: ", err)
  end
end

local function parse_watch_response(response_body)
  -- message WatchResponse {
  --   ResponseHeader header = 1;
  --   int64 watch_id = 2;
  --   bool created = 3;
  --   bool canceled = 4;
  --   int64 compact_revision = 5;

  --   repeated mvccpb.Event events = 11;
  -- }
  local response = json.decode(response_body)
  local events = response.events

  -- not updated
  if not events then
    return
  end

  local server_list = _M.shenyu_server_list
  -- message Event {
  --   enum EventType {
  --     PUT = 0;
  --     DELETE = 1;
  --   }
  --   EventType type = 1;
  --   KeyValue kv = 2;
  --   KeyValue prev_kv = 3;
  -- }
  for _, event in pairs(events) do
    local kv = event.kv
    update_revision(kv.mod_revision, true)

    -- event.type: delete
    if event.type == 1 then
      log(INFO, "remove shenyu server instance[" .. kv.key .. "].")
      server_list:delete(kv.key)
    else
      server_list:set(kv.key, 1)
    end
  end

  build_upstream_servers(server_list)
end


return _M
