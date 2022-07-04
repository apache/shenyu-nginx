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

local http = require("resty.http")
local json = require("cjson")
local ngx_balancer = require("ngx.balancer")

local balancer = require("shenyu.register.balancer")

local ngx_timer_at = ngx.timer.at
local ngx_worker_exiting = ngx.worker.exiting

local log = ngx.log
local ERR = ngx.ERR

local _M = {}

_M._VERSION="0.1"

local function get_server_list()
    local httpc = http.new()   

    local res, err = httpc:request_uri(_M.uri, {
        method = "GET",  
        path = _M.path,

    })  

    if not res then
        log(ERR, "failed to request.")
        return nil, err
    end

    if res.status == 200 then
        local upstreams = {}
        local kvs = json.decode(res.body)

        for _, v in ipairs(kvs) do
            local instanceId = ""
            instanceId = instanceId .. v.ServiceAddress .. ":" .. v.ServicePort
            upstreams[instanceId] = 1
        end

        return upstreams, err
    end

    return nil, err
end

local function sync(premature)

    if premature or ngx_worker_exiting() then
        return
    end

    local storage = _M.storage

    local server_list = storage:get("server_list")
    local servers = json.decode(server_list)

    _M.balancer:reinit(servers)

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

        local server_list, err = get_server_list()

        if not server_list then
            log(ERR, "", err)
            goto continue
        end

        _M.balancer:init(server_list)

        local server_list_in_json = json.encode(server_list)
        _M.storage:set("server_list", server_list_in_json)

        initialized = true
    else
        local server_list, err = get_server_list()

        if not server_list then
            log(ERR, "", err)
            goto continue
        end

        _M.balancer:reinit(server_list)

        local server_list_in_json = json.encode(server_list)
        _M.storage:set("server_list", server_list_in_json)
    end


    :: continue ::
    local ok, err = ngx_timer_at(2, subscribe, initialized)
    if not ok then
        log(ERR, "failed to subscribe: ", err)
    end

    return


end


function _M:pick_and_set_peer(key)
    local server = _M.balancer:find(key)
    ngx_balancer.set_current_peer(server)
end


function _M.init(conf)

    _M.uri = conf.uri
    _M.path = conf.path
    _M.storage = conf.shenyu_storage
    _M.balancer = balancer.new(conf.balancer_type)
    if 0 == ngx.worker.id() then
        local ok, err = ngx_timer_at(0, subscribe)
        if not ok then
            log(ERR, "failed to start watch: ", err)
            return
        end
    end

    local ok, err = ngx_timer_at(2, sync)
    if not ok then
        log(ERR, "failed to start sync ", err)
    end

end

return _M