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
local util = require("shenyu.register.core.utils")
local struct = require("shenyu.register.core.struct")
local tcp = ngx.socket.tcp
local ngx_log = ngx.log
local ipairs = ipairs
local _M = {}
local mt = { __index = _M }
local _timeout = 60 * 1000
local pack = struct.pack
local unpack = struct.unpack
--实例化一个zk客户端.
function _M.new(self)
    local tcp, err = tcp()
    if not tcp then
        return nil, err
    end
    return setmetatable({ tcp = tcp, timeout = _timeout }, mt)
end

--连接zookeeper.
function _M.connect(self, host)
    local tcp = self.tcp
    if not tcp then
        return nil, "not initialized tpc."
    end
    local ip_port = util.paras_host(host, ":")
    local ip = ip_port[1]
    local port = ip_port[2]
    local ok, err = tcp:connect(ip, port)
    if not ok then
        ngx_log(ngx.DEBUG, "connect host:" .. host .. err)
        return ok, err;
    end
    local req = pack(">iililic16", 44, 0, 0, 0, 0, 0, "")
    local bytes, err = self:_send(req)
    if not bytes then
        return nil, err
    end
    
    local resp, err = tcp:receive(4)
    if not resp then
        return nil, err
    end
    
    local len = unpack(">i", resp)
    if len then
        resp, err = tcp:receive(len)
        if not resp then
            return nil, err;
        end
    end
    
    local v, t, sid, pl = unpack(">iilis", resp)
    self.sn = 0
    self.session_timeout = t
    return true;
end

--发送数据
function _M._send(self, req)
    local tcp = self.tcp
    local resp, err = tcp:send(req)
    if not resp then
        return nil, err
    end
    return resp;
end

return _M
