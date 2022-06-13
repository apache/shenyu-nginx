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

local function login(username, password)
    local httpc = http.new()
    local res, err = httpc:request_uri(nacos_base, {
        method = "POST",
        path = "/nacos/v1/auth/login",
        query = "username=" .. username .. "&password=" .. password,
    })
    if not res then
        return nil, err
    end

    if res.status >= 400 then
        return nil, res.body
    end

    return json.decode(res.body).accessToken
end

local function get_server_list(service_name, group_name, namespace_id, clusters)
    local server_list = {}
    local res, err = httpc:request_uri(nacos_base, {
        method = "GET",
        path = "/nacos/v1/ns/instance/list",
        query = "serviceName=" .. service_name ..
                "&groupName=" .. group_name ..
                "&namespaceId=" .. namespace_id ..
                "&clusters=" .. clusters ..
                "&healthOnly=true",
        headers = {
            ["accessToken"] = _M.access_token,
        }
    })

    if not res then
        log(ERR, "failed to get server list from nacos.", err)
        return
    end

    if res.status == 200 then
        local list_inst_resp = json.encode(res.body)

        local hosts = list_inst_resp.hosts
        for inst in pairs(hosts) do
            server_list[inst.instanceId] = inst.weight
        end
        server_list["_length_"] = #hosts

        return server_list, list_inst_resp.lastRefTime
    end
    log(ERR, res.body)
    return
end

-- conf = {
--   balance_type = "chash",
--   nacos_base_url = "http://127.0.0.1:8848",
--   username = "nacos",
--   password = "nacos",
--   namespace = "",
--   service_name = "",
--   group_name = "",
-- }
function _M.init(conf)
    _M.storage = conf.shenyu_storage
    _M.balancer = balancer.new(conf.balancer_type)

    if ngx.worker.id() == 0 then
        _M.shenyu_instances = {}
        _M.nacos_base_url = conf.nacos_base_url

        _M.namespace = conf.namespace
        _M.group_name = conf.group_name
        _M.cluster_name = conf.cluster_name
        _M.service_name = conf.service_name
        if not conf.namespace then
            _M.namespace = "DEFAULT"
        end
        if not conf.group_name then
            _M.group_name = "DEFAULT_GROUP"
        end
        if not conf.service_name then
            _M.service_name = "shenyu-instances"
        end

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

local function subscribe(premature, initialized)
    if premature or ngx_worker_exiting() then
        return
    end

    if not initialized then
        local token, err = login(_M.username, _M.password)
        if not token then
            log(ERR, err)
            goto continue
        end
        _M.access_token = token

        local server_list, revision = get_server_list(_M.service_name, _M.group_name, _M.namespace, _M.clusters)
        if not server_list then
            goto continue
        end
        local servers_length = server_list["_length_"]
        server_list["_length_"] = nil
        _M.servers_length = servers_length

        _M.balancer:init(server_list)
        _M.revision = revision

        local server_list_in_json = json.encode(server_list)
        _M.storage:set("server_list", server_list_in_json)
        _M.storage:set("revision", revision)

        initialized = true
    else
        local server_list, revision = get_server_list(_M.service_name, _M.group_name, _M.namespace, _M.clusters)
        if not server_list then
            goto continue
        end

        local updated = false
        local servers_length = server_list["_length_"]
        server_list["_length_"] = nil

        if _M.servers_length == servers_length then
            local services = _M.server_list
            for srv, weight in pairs(server_list) do
                if services[srv] ~= weight then
                    updated = true
                    break
                end
            end
        else
            updated = true
        end

        if not updated then
            goto continue
        end

        _M.balancer:reinit(server_list)
        _M.revision = revision

        local server_list_in_json = json.encode(server_list)
        _M.storage:set("server_list", server_list_in_json)
        _M.storage:set("revision", revision)
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
        else
            _M.balancer:reinit(servers)
        end
        _M.revision = ver
    end

    local ok, err = ngx_timer_at(2, sync)
    if not ok then
        log(ERR, "failed to start sync: ", err)
    end
end

function _M.pick_and_set_peer(key)
    local server = _M.balancer:find(key)
    ngx_balancer.set_current_peer(server)
end

return _M
