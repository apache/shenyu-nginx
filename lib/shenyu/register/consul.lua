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

local new_timer = ngx.timer.at
local log = ngx.log
local ERR = ngx.ERR

local _M = {}

_M._VERSION="0.1"

local function sync()
    local httpc = http.new()   

    local resp, err = httpc:request_uri(_M.uri, {
        method = "GET",  
        path = _M.path,

    })  

    local kvs = json.decode(resp.body)
    local upstreams = {}

    for i, v in ipairs(kvs) do
        local instanceId = ""
        instanceId = instanceId .. v.ServiceAddress .. ":" .. v.ServicePort
        upstreams[instanceId] = 1
    end
    _M.balancer:init(upstreams)

end

function _M:pick_and_set_peer(key)
    local server = _M.balancer:find(key)
    ngx_balancer.set_current_peer(server);
end


function _M.init(conf)

    _M.uri = conf.uri
    _M.path = conf.path
    _M.storage = conf.shenyu_storage
    _M.balancer = balancer.new(conf.balancer_type)
    if 0 == ngx.worker.id() then
        local ok, err = new_timer(5, sync)
        if not ok then
            log(ERR, "failed to create timer: ", err)
            return
        end
    end
end

return _M