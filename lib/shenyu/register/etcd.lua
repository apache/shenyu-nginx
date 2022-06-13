--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--    http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local _M = {}

local http = require("resty.http")
local json = require("cjson.safe")
local ngx_balancer = require("ngx.balancer")

local balancer = require("shenyu.register.balancer")

local ngx = ngx

local re = ngx.re.match
local ngx_timer_at = ngx.timer.at
local ngx_worker_exiting = ngx.worker.exiting
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64

local log = ngx.log
local ERR = ngx.ERR
local INFO = ngx.INFO

_M.start_key = "/shenyu/register/instance/ "
_M.end_key = "/shenyu/register/instance/~"
_M.revision = -1
_M.time_at = 0

-- <= 3.2 /v3alpha
-- == 3.3 /v3beta
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

local function parse_base_url(base_url)
    local m, err = re(base_url, [=[([^\/]+):\/\/([\da-zA-Z.-]+|\[[\da-fA-F:]+\]):?(\d+)?(\/)?$]=], "jo")
    if not m then
        return nil, "failed to parse etcd base_url[" .. base_url .. "], " .. (err or "unknown")
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

local function parse_value(value)
    local obj = json.decode(decode_base64(value))
    return obj.host .. ":" .. obj.port
end

local function fetch_shenyu_instances(conf)
    local range_request = {
        key = encode_base64(_M.start_key),
        range_end = encode_base64(_M.end_key),
    }

    local httpc = http.new()
    local res, err = httpc:request_uri(conf.base_url .. conf.prefix .. "/kv/range", {
        method = "POST",
        body = json.encode(range_request),
    })
    if not res then
        return nil, "failed to list shenyu instances from etcd, " .. (err or "unknown")
    end

    if res.status >= 400 then
        if not res.body then
            return nil, "failed to send range_request to etcd, " .. (err or "unknown")
        end
        return nil, "failed to send range_request to etcd, " .. res.body
    end

    local _revision = _M.revision
    local shenyu_instances = _M.shenyu_instances

    local kvs = json.decode(res.body).kvs
    if not kvs then
        return nil, "get the empty shenyu instances from etcd."
    end

    local server_list = {}
    for _, kv in pairs(kvs) do
        local ver = tonumber(kv.mod_revision)
        if _revision < ver then
            _revision = ver
        end

        local key = parse_value(kv.value)
        server_list[key] = 1
        shenyu_instances[kv.key] = key
    end

    _M.revision = _revision + 1
    _M.shenyu_instances = shenyu_instances

    local _servers = json.encode(server_list)
    _M.storage:set("server_list", _servers)
    _M.storage:set("revision", _M.revision)

    _M.balancer:init(server_list)
    return true
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
    if response == nil or response.result == nil then
        return
    end
    local events = response.result.events
    if not events then
        return
    end
    log(INFO, "watch response: " .. response_body)

    local shenyu_instances = _M.shenyu_instances
    -- message Event {
    --   enum EventType {
    --     PUT = 0;
    --     DELETE = 1;
    --   }
    --   EventType type = 1;
    --   KeyValue kv = 2;
    --   KeyValue prev_kv = 3;
    -- }

    local _revision = _M.revision
    for _, event in pairs(events) do
        local kv = event.kv
        _revision = tonumber(kv.mod_revision)

        -- event.type: delete
        if event.type == "DELETE" then
            log(INFO, "remove upstream node of shenyu, key: " .. kv.key)
            shenyu_instances[kv.key] = nil
        else
            local updated = parse_value(kv.value)
            log(INFO, "update upstream node of shenyu: " .. updated)
            shenyu_instances[kv.key] = update
        end
    end

    if _M.revision < _revision then
        local server_list = {}
        for _, value in pairs(shenyu_instances) do
            server_list[value] = 1
        end
        log(INFO, "updated upstream nodes successful.")

        local _servers = json.encode(server_list)
        _M.storage:set("server_list", _servers)
        _M.storage:set("revision", _M.revision)

        _M.balancer:init(server_list)

        _M.revision = _revision + 1
        _M.shenyu_instances = shenyu_instances
    end
end

local function sync(premature)
    if premature or ngx_worker_exiting() then
        return
    end

    local time_at = 1
    local storage = _M.storage

    local lock = storage:get("_lock")
    local ver = storage:get("revision")

    if not lock and ver > _M.revision then
        local server_list = storage:get("server_list")
        local servers = json.decode(server_list)
        if _M.revision <= 1 then
            _M.balancer:init(servers)
        else
            _M.balancer:reinit(servers)
        end
        time_at = 0
        _M.revision = ver
    end

    local ok, err = ngx_timer_at(time_at, sync)
    if not ok then
        log(ERR, "failed to start sync ", err)
    end
end

local function watch(premature, watching)
    if premature or ngx_worker_exiting() then
        return
    end

    if not watching then
        if not _M.etcd_conf then
            _M.storage:set("_lock", true)

            local conf, err = parse_base_url(_M.etcd_base_url)
            if not conf then
                log(ERR, err)
                return err
            end
            _M.etcd_conf = conf
        end

        local ok, err = fetch_shenyu_instances(_M.etcd_conf)
        if not ok then
            log(ERR, err)
            _M.time_at = 3
        else
            watching = true
            _M.storage:set("_lock", false)
        end
    else
        local conf = _M.etcd_conf
        local httpc = http.new()
        local ok, err = httpc:connect({
            scheme = conf.scheme,
            host = conf.host,
            port = tonumber(conf.port),
        })
        if not ok then
            log(ERR, "failed to connect to etcd server", err)
            _M.time_at = 3
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
                key = encode_base64(_M.start_key),
                range_end = encode_base64(_M.end_key),
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
            _M.time_at = 3
            goto continue
        end

        local reader = res.body_reader
        local buffer_size = 8192

        _M.time_at = 0
        repeat
            local buffer, err = reader(buffer_size)
            if err then
                if err ~= "timeout" then
                    log(ERR, err)
                end
                goto continue
            end

            if buffer then
                parse_watch_response(buffer)
            end
        until not buffer
        local ok, err = httpc:set_keepalive()
        if not ok then
            log(ERR, "failed to set keepalive: ", err)
        end
    end

    :: continue ::
    local ok, err = ngx_timer_at(_M.time_at, watch, watching)
    if not ok then
        log(ERR, "failed to start watch: ", err)
    end
    return
end

-- conf = {
--   balance_type = "chash",
--   etcd_base_url = "http://127.0.0.1:2379",
-- }
function _M.init(conf)
    _M.storage = conf.shenyu_storage
    _M.balancer = balancer.new(conf.balancer_type)

    if ngx.worker.id() == 0 then
        _M.shenyu_instances = {}
        _M.etcd_base_url = conf.etcd_base_url

        -- Start the etcd watcher
        local ok, err = ngx_timer_at(0, watch)
        if not ok then
            log(ERR, "failed to start watch: " .. err)
        end
        return
    end

    local ok, err = ngx_timer_at(2, sync)
    if not ok then
        log(ERR, "failed to start sync ", err)
    end
end

function _M.pick_and_set_peer(key)
    local server = _M.balancer:find(key)
    ngx_balancer.set_current_peer(server)
end

return _M
