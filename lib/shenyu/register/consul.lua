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
local balancer = require("ngx.balancer")

local new_timer = ngx.timer.at
local log = ngx.log
local ERR = ngx.ERR

local _M = {}

_M._VERSION="0.1"

function _M:sync()
    local httpc = http.new()   

    local resp, err = httpc:request_uri(_M.uri, {
        method = "GET",  
        path = _M.path,

    })  

    local kvs = json.decode(resp.body)
    local upstreams = {}
    for i, v in ipairs(kvs) do
        log(ERR, v.ServiceAddress)
        log(ERR, v.ServicePort)
        upstreams[i] = {ip=v.ServiceAddress, port=v.ServicePort}
    end
    _M.storage:set("server_list",  json.encode(upstreams))

end

function _M:get_server_list()
    local upstreams_str = _M.storage:get("server_list");
    local tmp_upstreams = json.decode(upstreams_str);
    return tmp_upstreams;
end

function _M:pick_and_set_peer()
    local tmp_upstreams = _M.get_server_list();
    local ip_port = tmp_upstreams[math.random(1, table.getn(tmp_upstreams))];
    balancer.set_current_peer(ip_port.ip, ip_port.port);
end


function _M.init(conf)

    _M.uri = conf.uri
    _M.path = conf.path
    _M.storage = conf.shenyu_storage

    if 0 == ngx.worker.id() then
        local ok, err = new_timer(5, _M:sync())
        if not ok then
            log(ERR, "failed to create timer: ", err)
            return
        end
    end
end

return _M