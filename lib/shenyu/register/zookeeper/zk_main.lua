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

local function watch(premature, path)
    print("一个好好的path" .. path)
    local ok, err = zc:connect()
    if ok then
        ok, err = xpcall(zc:add_watch(path, function(f)
            for i, v in ipairs(f) do
                print("拿到数据了" .. v)
            end
        end), function(err)
            ngx_log(ngx.ERR, "zookeeper start watch error..." .. tostring(err))
        end)
    end
    return ok, err
end

function _M.init(config)
    zc = zk_cluster:new(config)
    if ngx.worker.id() == 0 then
        -- Start the zookeeper watcher
        local ok, err = ngx_timer_at(2, watch, config.watch_path)
        if not ok then
            ngx_log(ERR, "failed to start watch: " .. err)
        end
        return
    end
end
return _M
