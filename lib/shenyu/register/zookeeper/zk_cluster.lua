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
local zkclient              = require("shenyu.register.zookeeper.zk_client")
local util                  = require("shenyu.register.core.utils")
local ngx_log               = ngx.log
local ipairs                = ipairs
local _M                    = {}
local mt                    = {__index = _M}
local timeout               = 60 * 1000
local table_len             = util.tlen
local connects              = {}

function _M.newInst(self, zkconfig)
    -- body
    return setmetatable({servers = zkconfig.servers, timeout = timeout}, mt)
end

function _M.connect(self)
    local servers = self.servers
    if not servers then
        return nil, "servers is null"
    end
    --    初始化
    local conn, err = zkclient:new()
    if not conn then
        ngx_log(ngx.ERR, "初始化zkClient失败" .. err)
    end
    for _, _host in ipairs(servers) do
        ngx_log(ngx.INFO, "连接 zookeeper host : " .. _host)
        local ok, err = conn:connect(_host)
        if not ok then
            ngx_log(ngx.INFO, "尝试连接 zookeeper 失败 host : " .. _host .. err)
        else
            self.conn = conn
            return conn
        end
    end
    ngx_log(ngx.ERR, "连接 zookeeper 失败")
    return nil
end

return _M
