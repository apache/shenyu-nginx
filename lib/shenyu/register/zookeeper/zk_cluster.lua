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
-- limitations un
local zkclient = require("shenyu.register.zookeeper.zk_client")
local ngx_log = ngx.log
local ipairs = ipairs
local _M = {}
local mt = {__index = _M}

function _M.new(self, zk_config)
    -- body
    return setmetatable({servers = zk_config.servers}, mt)
end

function _M.connect(self)
    local servers = self.servers
    if not servers then
        return nil, "servers is null"
    end
    -- initialize
    ---@type
    local client, err = zkclient:new()
    if not client then
        ngx_log(ngx.ERR, "Failed to initialize zk Client" .. err)
        return nil, err
    end
    for _, _host in ipairs(servers) do
        ngx_log(ngx.INFO, "try to connect to zookeeper host : " .. _host)
        local ok, err = client:connect(_host)
        if not ok then
            ngx_log(ngx.INFO, "Failed to connect to zookeeper host : " .. _host .. err)
        else
            ngx_log(ngx.INFO, "Successful connection to zookeeper host : " .. _host)
            self.client = client
            return client
        end
    end
    ngx_log(ngx.ERR, "Failed to connect to zookeeper")
    return nil
end

function _M.get_children(self, path)
    local client = self.client
    if not client then
        ngx_log(ngx.ERR, "conn not initialized")
    end
    local data, error = client:get_children(path)
    if not data then
        return nil, error
    end
    return data, nil
end

local function _watch_receive(self)
    local client = self.client
    if not client then
        ngx_log(ngx.ERR, "conn not initialized")
    end
    return client:watch_receive()
end

function _M.add_watch(self, path, listener)
    local client = self.client
    if not client then
        ngx_log(ngx.ERR, "conn not initialized")
    end
    local data, err = client:add_watch(path,listener)
    if data then
        listener(data.path)
        return _watch_receive(self)
    end
    return data, err
end

return _M
