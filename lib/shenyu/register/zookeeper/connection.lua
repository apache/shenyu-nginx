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
local proto = require("shenyu.register.zookeeper.zk_proto")
local struct = require("shenyu.register.core.struct")
local tcp = ngx.socket.tcp
local pack = struct.pack
local unpack = struct.unpack
local tbunpack = struct.tbunpack
local ngx_log = ngx.log
local _timeout = 60 * 1000
local _M = {}
local mt = {__index = _M}

function _M.new(self)
    local sock, err = tcp()
    if not tcp then
        return nil, err
    end
    return setmetatable({sock = sock, timeout = _timeout}, mt)
end

function _M.connect(self, ip, port)
    -- body
    local sock = self.sock
    if not sock then
        return nil, "not initialized tcp."
    end
    local ok, err = sock:connect(ip, port)
    if not ok then
        ngx_log(ngx.DEBUG, "connect host:" .. ip .. err)
        return ok, err
    end
    return ok, nil
end

function _M.write(self, req)
    -- body
    local sock = self.sock
    if not sock then
        return nil, "not initialized tpc."
    end
    return sock:send(req)
end

function _M.read(self, len)
    -- body
    local sock = self.sock
    if not sock then
        return nil, "not initialized tpc."
    end
    return sock:receive(len)
end

function _M.read_len(self)
    local b, err = self:read(4)
    if not b then
        return nil, "error"
    end
    local len = tbunpack(unpack(">i", b))
    return len
end

function _M.read_headler(self)
    local len = self:read_len()
    local b, err = self:read(len)
    if not b then
        return nil, "error"
    end
    local h, end_index = proto.reply_header:unpack(b, 1)
    if not h then
        return nil, nil, 0
    end
    return h, b, end_index
end

function _M.close()
    -- body
    local sock = self.sock
    if not sock then
        return nil, "not initialized tpc."
    end
    sock.close()
end

function _M.set_timeout(self, timeout)
    -- body
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end
    sock:settimeout(timeout)
end

function _M.set_keepalive(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:setkeepalive(...)
end

function _M.set_timeouts(self, connect_timeout, send_timeout, read_timeout)
    local sock = self.sock
    if not sock then
        error("not initialized", 2)
        return
    end

    sock:settimeouts(connect_timeout, send_timeout, read_timeout)
end

return _M
