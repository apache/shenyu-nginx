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
local ngx_timer_at = ngx.timer.at
local xpcall = xpcall
local ngx_log = ngx.log
local zc;
local _M = {}

local function watch(path)
    xpcall(zc:add_watch(path, function(f)
        for i, v in ipairs(f) do
            print("拿到数据了"..v)
        end
    end), function(err)
        ngx_log(ngx.ERR, err)
    end)
end

local function sync(self, premature)
    local ok, err = zc:connect()
    if ok then
        watch("/shenyu/registry")
    end
    print("......")
end

function _M.init()
    zc = zk_cluster:new({ servers = { "127.0.0.1:2181" } })
    ngx_timer_at(2, sync)
end
return _M
