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
local util = require("shenyu.register.core.utils")
local ngx_log = ngx.log
local ipairs = ipairs
local _M = {}
local mt = { __index = _M }
local timeout = 60 * 1000
local table_len = util.tlen
local connects = {}

function _M.new(self, zkconfig)
    -- body
    return setmetatable({ servers = zkconfig.servers, timeout = timeout }, mt)
end

function _M.connect(self)
    local servers = self.servers
    if not servers then
        return nil, "servers is null"
    end
    --    初始化
    local conn, err = zkclient:new()
    if not conn then
        ngx_log(ngx.ERR, "Failed to initialize zk Client" .. err)
    end
    conn:set_timeout(timeout)
    for _, _host in ipairs(servers) do
        ngx_log(ngx.INFO, "try to connect to zookeeper host : " .. _host)
        local ok, err = conn:connect(_host)
        if not ok then
            ngx_log(ngx.INFO, "Failed to connect to zookeeper host : " .. _host .. err)
        else
            ngx_log(ngx.INFO, "Successful connection to zookeeper host : " .. _host)
            self.conn = conn
            return conn
        end
    end
    ngx_log(ngx.ERR, "Failed to connect to zookeeper")
    return nil
end

function _M.get_children(self, path)
    local conn = self.conn
    if not conn then
        ngx_log(ngx.ERR, "conn not initialized")
    end
    local data, error = conn:get_children(path)
    if not data then
        return nil, error
    end
    for _, value in ipairs(data) do
        print("value:" .. value)
    end
    return data, nil
end

local function _watch_receive(self, callback)
    local conn = self.conn
    if not conn then
        ngx_log(ngx.ERR, "conn not initialized")
    end
    return conn:watch_receive(callback)
end

function _M.add_watch(self, path, callback)
    local conn = self.conn
    if not conn then
        ngx_log(ngx.ERR, "conn not initialized")
    end
    local data, err = conn:add_watch(path)
    if data then
        callback(data.path)
        return _watch_receive(self, callback)
    end
    return data, err
end

function _M.set_keepalive(self)
    local conn = self.conn
    if not conn then
        ngx_log(ngx.ERR, "conn not initialized")
    end
    return conn:set_keepalive()
end

return _M
