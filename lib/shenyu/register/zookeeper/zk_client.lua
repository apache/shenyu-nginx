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
local const = require("shenyu.register.zookeeper.zk_const")
local proto = require("shenyu.register.zookeeper.zk_proto")
local tcp = ngx.socket.tcp
local ngx_log = ngx.log
local ipairs = ipairs
local now = ngx.now
local exiting = ngx.worker.exiting
local sleep = ngx.sleep
local strbyte = string.byte
local strsub = string.sub
local strlen = string.len
local _M = {}
local mt = { __index = _M }
local _timeout = 60 * 1000
local pack = struct.pack
local unpack = struct.unpack
local connect_timeout = 6000
--实例化一个zk客户端.
function _M.new(self)
    local sock, err = tcp()
    if not tcp then
        return nil, err
    end
    return setmetatable({ sock = sock, timeout = _timeout }, mt)
end

--连接zookeeper.
function _M.connect(self, host)
    local sock = self.sock
    if not sock then
        return nil, "not initialized tpc."
    end
    local ip_port = util.paras_host(host, ":")
    local ip = ip_port[1]
    local port = ip_port[2]
    local ok, err = sock:connect(ip, port)
    if not ok then
        ngx_log(ngx.DEBUG, "connect host:" .. host .. err)
        return ok, err
    end
    local req = pack(">iililic16", 44, 0, 0, connect_timeout, 0, 0, "")
    local bytes, err = self:_send(req)
    if not bytes then
        return nil, err
    end
    
    local resp, err = self:_receive(4)
    if not resp then
        return nil, err
    end
    
    local len = self._rspLen(resp)
    if len then
        resp, err = self:_receive(len)
        if not resp then
            return nil, err
        end
    end
    
    local v, t, sid, pl = unpack(">iilis", resp)
    self.xid = 0
    self.session_timeout = t
    self.ping_time = (t / 3) / 1000
    self.host = host
    self.session_id = sid
    return "OK"
end

function _M.keepalive(self)
    local last_time = 0
    while true do
        if exiting() then
            self:_close()
            return true
        end
        local can_ping = now() - last_time > self.ping_time
        if can_ping then
            local ok, err = self:_ping()
            if err then
                return nil, err
            end
            last_time = now()
        end
        -- //表示200ms.
        sleep(0.2)
    end
end

function _M._ping(self)
    local req = pack(">iII", 8, const.XID_PING, const.ZOO_PING_OP)
    local ok, err = self:_send(req)
    if ok then
        local len = self._rspLen(self:_receive(4))
        if len then
            local bytes = self:_receive(len)
            local xid = unpack(">i", bytes)
            if xid == const.XID_PING then
                ngx_log(
                        ngx.DEBUG,
                        "Got ping zookeeper response host:" ..
                                self.host .. " for sessionId:" .. util.long_to_hex_string(self.session_id)
                )
            end
        end
    end
    return ok, err
end

function _M._rspLen(resp)
    if not resp then
        return nil, "resp error"
    end
    -- body
    return unpack(">i", resp)
end

function _M._receive(self, len)
    -- body
    local sock = self.sock
    return sock:receive(len)
end

--发送数据
function _M._send(self, req)
    local sock = self.sock
    local resp, err = sock:send(req)
    if not resp then
        return nil, err
    end
    return resp, err
end

local function unpack_strings(str)
    local size = strlen(str)
    local pos = 0
    local str_set = {}
    local index = 1
    while size > pos do
        local len = unpack(">i", strsub(str, 1 + pos, 4 + pos))
        local s = unpack(">c" .. len, strsub(str, 5 + pos, 5 + pos + len - 1))
        str_set[index] = s
        index = index + 1
        pos = pos + len + 4
    end
    return str_set
end

function _M.get_children(self, path)
    local d, e = self:_get_children(path)
    if not d then
        return d.path
    end
    return nil, e
end

function _M._get_children(self, path)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end
    local path_len = strlen(path)
    local h_len = 12 + path_len + 1
    local xid = self.xid + 1
    local req = pack(">iiiic" .. path_len .. "b", h_len, xid, const.ZOO_GET_CHILDREN, path_len, path, strbyte(0))
    local bytes, err = self:_send(req)
    local len = self._rspLen(self:_receive(4))
    if len then
        bytes, err = self:_receive(len)
        if strlen(bytes) > 16 then
            local xid, zxid, err, count = unpack(">ilii", bytes)
            self.xid = xid + 1
            local paths = unpack_strings(strsub(bytes, 21))
            return {
                xid = xid,
                zxid = zxid,
                count = count,
                path = paths
            }
        end
    else
        return nil, "get_children error"
    end
    return nil, "get_children error"
end

function _M.add_watch(self, path)
    -- body
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end
    local d, e = self:_get_children(path)
    if e then
        return d, e
    end
    print("监听的zxid" .. d.zxid)
    local zxid = d.zxid
    local path_len = strlen(path)
    local h_len = 20 + 4 + 0 + 4 + 0 + 4 + path_len
    --[len,xid,opcode,zxid,dw_len,dw,ew_len,ew,cw_len,cw]
    --[int,int,int,long,int,string,int,string,int string]
    --i,i,i,l,i,c[len],i,c[len],i,c[len]
    local req = pack(">iiilic0ic0ic" .. path_len, h_len, const.XID_SET_WATCHES, const.ZOO_SET_WATCHES, zxid, 0, "", 0, "", path_len, path)
    print("发送请求了.....")
    local bytes, err = self:_send(req)
    if not bytes then
        print(err)
    end
    
    print("监听成功")
end

function _M._close(self)
    -- body
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end
    return sock:close()
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

return _M
