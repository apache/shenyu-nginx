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

local ngx_timer_at = ngx.timer.at
local ngx_worker_exiting = ngx.worker.exiting


local log = ngx.log
local ERR = ngx.ERR
local INFO = ngx.INFO

_M.access_token = nil

local function login()
    local httpc = http.new()
    local res, err = httpc:request_uri(_M.nacos_base_url, {
        method = "POST",
        path = "/nacos/v1/auth/login",
        query = "username=" .. _M.username .. "&password=" .. _M.password,
    })
    if not res then
        return nil, err
    end

    if res.status >= 400 then
        return nil, res.body
    end

    log(INFO, "login nacos in username: '" .. _M.username .. "' successfully.")
    return json.decode(res.body).accessToken
end

local function get_server_list()
    local httpc = http.new()
    local res, err = httpc:request_uri(_M.nacos_base_url, {
        method = "GET",
        path = "/nacos/v1/ns/instance/list",
        query = "serviceName=" .. _M.service_name
                .. "&groupName=" .. _M.group_name
                .. "&namespaceId=" .. _M.namespace
                .. "&clusters=" .. _M.clusters
                .. "&healthOnly=true"
                .. "accessToken=" .. _M.access_token
    })
    if not res then
        log(ERR, "failed to get server list from nacos. ", err)
        return
    end

    if res.status == 200 then
        local server_list = {}
        local list_inst_resp = json.decode(res.body)

        local hosts = list_inst_resp.hosts
        if not hosts then
            return {}, 0, 0
        end

        for _, inst in pairs(hosts) do
            local key = inst.ip .. ":" .. inst.port
            server_list[key] = inst.weight
        end

        return server_list, list_inst_resp.lastRefTime, #hosts
    end
    log(ERR, res.body)
    return
end

local function subscribe(premature, initialized)
    if premature or ngx_worker_exiting() then
        return
    end

    if not initialized then
        local token, err = login()
        if not token then
            log(ERR, err)
            goto continue
        end
        _M.access_token = token

        local server_list, revision, servers_length = get_server_list()
        if not server_list or servers_length == 0 then
            goto continue
        end

        _M.balancer:init(server_list)
        _M.revision = revision
        _M.servers_length = servers_length

        local server_list_in_json = json.encode(server_list)
        log(INFO, "initialize upstream: " .. server_list_in_json .. " , revision: " .. revision)

        _M.storage:set("server_list", server_list_in_json)
        _M.storage:set("revision", revision)

        initialized = true
    else
        local server_list, revision, servers_length = get_server_list()
        if not server_list or servers_length == 0 then
            goto continue
        end

        local updated = true
        if _M.servers_length == servers_length then
            local services = _M.server_list
            for srv, weight in pairs(server_list) do
                if services[srv] ~= weight then
                    break
                end
            end
            updated = false
        end

        if not updated then
            goto continue
        end

        _M.balancer:reinit(server_list)
        _M.revision = revision
        _M.server_list = server_list

        local server_list_in_json = json.encode(server_list)
        log(INFO, "update upstream: " .. server_list_in_json .. " , revision: " .. revision)

        _M.storage:set("server_list", server_list_in_json)
        _M.storage:set("revision", revision)
        _M.servers_length = servers_length
    end

    :: continue ::
    local ok, err = ngx_timer_at(2, subscribe, initialized)
    if not ok then
        log(ERR, "failed to subscribe: ", err)
    end
    return
end

local function sync(premature)
    if premature or ngx_worker_exiting() then
        return
    end

    local storage = _M.storage
    local ver = storage:get("revision")

    if ver > _M.revision then
        local server_list = storage:get("server_list")
        local servers = json.decode(server_list)
        if _M.revision < 1 then
            _M.balancer:init(servers)
            log(INFO, "initialize upstream in workers, upstream: " .. server_list)
        else
            _M.balancer:reinit(servers)
            log(INFO, "update upstream in workers, upstream: " .. server_list)
        end
        _M.revision = ver
    end

    local ok, err = ngx_timer_at(1, sync)
    if not ok then
        log(ERR, "failed to start sync: ", err)
    end
end

-- conf = {
--   balance_type = "chash",
--   nacos_base_url = "http://127.0.0.1:8848",
--   username = "nacos",
--   password = "nacos",
--   namespace = "",
--   service_name = "",
--   group_name = "",
--   clusters = "",
-- }
function _M.init(conf)
    _M.storage = conf.shenyu_storage
    _M.balancer = balancer.new(conf.balancer_type)

    _M.revision = 0

    if ngx.worker.id() == 0 then
        _M.nacos_base_url = conf.nacos_base_url
        _M.username = conf.username
        _M.password = conf.password
        _M.namespace = conf.namespace
        _M.group_name = conf.group_name
        _M.service_name = conf.service_name
        _M.clusters = conf.clusters

        if not conf.clusters then
            _M.clusters = ""
        end
        if not conf.namespace then
            _M.namespace = ""
        end
        if not conf.group_name then
            _M.group_name = "DEFAULT_GROUP"
        end
        if not conf.service_name then
            _M.service_name = "shenyu-instances"
        end

        _M.server_list = {}
        _M.storage:set("revision", 0)

        -- subscribed by polling, privileged
        local ok, err = ngx_timer_at(0, subscribe)
        if not ok then
            log(ERR, "failed to start watch: " .. err)
        end
        return
    end

    -- synchronize server_list from privileged processor to workers
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
