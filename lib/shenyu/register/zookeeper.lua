--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an"AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local zk_cluster = require("shenyu.register.zookeeper.zk_cluster")
local const = require("shenyu.register.zookeeper.zk_const")
local balancer = require("shenyu.register.balancer")
local ngx_balancer = require("ngx.balancer")
local ngx_timer_at = ngx.timer.at
local xpcall = xpcall
local ngx_log = ngx.log
local math = string.match
local zc
local _M = {
    isload = 0,
    nodes = {}
}

local function watch_data(data)
    ---@type table
    local server_lists = {}
    -- body
    for index, value in ipairs(data) do
        if math(value, ":") then
            server_lists[value] = 1
        end
    end
    ---@type table
    local s_nodes = _M.nodes
    for host, index in pairs(server_lists) do
        if not s_nodes[host] then
            ngx_log(ngx.INFO, "add shenyu server:" .. host)
        end
    end
    for host, index in pairs(s_nodes) do
        if not server_lists[host] then
            ngx_log(ngx.INFO, "remove shenyu server:" .. host)
        end
    end
    if (_M.isload > 1) then
        _M.balancer:reinit(server_lists)
    else
        _M.balancer:init(server_lists)
    end
    _M.isload = _M.isload + 1
    _M.nodes = server_lists
end

local function watch(premature, path)
    local ok, err = zc:connect()
    if ok then
        ok, err =
            xpcall(
            zc:add_watch(path, watch_data),
            function(err)
                ngx_log(ngx.ERR, "zookeeper start watch error..." .. tostring(err))
            end
        )
    end
    return ok, err
end

function _M.init(config)
    _M.storage = config.shenyu_storage
    _M.balancer = balancer.new(config.balancer_type)
    zc = zk_cluster:new(config)
    if ngx.worker.id() == 0 then
        -- Start the zookeeper watcher
        local ok, err = ngx_timer_at(2, watch, const.ZK_WATCH_PATH)
        if not ok then
            ngx_log(ngx.ERR, "failed to start watch: " .. err)
        end
        return
    end
end

function _M.pick_and_set_peer(key)
    local server = _M.balancer:find(key)
    if not server then
        ngx_log(ngx.ERR, "not find shenyu server..")
        return
    end
    ngx_balancer.set_current_peer(server)
end
return _M
