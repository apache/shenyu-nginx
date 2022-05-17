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
local str_null = string.char(0)

function _M.new(balancer_type)
    local balancer_type = (balancer_type or "roundrobin")
    if balancer_type == "chash" then
        _M.init = function(self, server_list)
            local servers, nodes = {}, {}
            for serv, weight in pairs(server_list) do
                local id = string.gsub(serv, ":", str_null)

                servers[id] = serv
                nodes[id] = weight
            end

            _M.balancer = require("resty.chash"):new(nodes)
            _M.servers = servers
        end

        _M.reinit = function(self, server_list)
            local servers, nodes = {}, {}
            for serv, weight in pairs(server_list) do
                local id = string.gsub(serv, ":", str_null)

                servers[id] = serv
                nodes[id] = weight
            end

            _M.balancer:reinit(nodes)
            _M.servers = servers
        end

        _M.find = function(self, key)
            local id = _M.balancer:find(key)
            return _M.servers[id]
        end
    elseif balancer_type == "roundrobin" then
        _M.init = function(self, servers)
            _M.balancer = require("resty.roundrobin"):new(servers)
        end

        _M.reinit = function(self, servers)
            _M.balancer:reinit(servers)
        end

        _M.find = function(self, key)
            return _M.balancer:find()
        end
    else
        log(ERR, "unknown balancer_type[" .. balancer_type .. "]")
        return
    end

    return _M
end

return _M
