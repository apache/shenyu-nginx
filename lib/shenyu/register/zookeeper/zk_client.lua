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
--instantiate a zk client.
function _M.new(self)
    local sock, err = tcp()
    if not tcp then
        return nil, err
    end
    return setmetatable({ sock = sock, timeout = _timeout, watch = false }, mt)
end

--connect zookeeper.
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
    local req = pack(">iililic16", 44, 0, 0, 0, 0, 0, "")
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
    return self:_get_children(path, 0)
end

function _M._get_children(self, path, is_watch)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end
    local path_len = strlen(path)
    local h_len = 12 + path_len + 1
    local xid = self.xid + 1
    local req = pack(">iiiic" .. path_len .. "b", h_len, xid, const.ZOO_GET_CHILDREN, path_len, path, strbyte(is_watch))
    local bytes, err = self:_send(req)
    if not bytes then
        return bytes, err
    end
    --  If other data is received, it means that the data of the _get_children command has not been received
    :: continue ::
    bytes, err = self:_receive(4)
    if not bytes then
        return bytes, err
    end
    local len = self._rspLen(bytes)
    if len then
        bytes, err = self:_receive(len)
        local d = proto.reply_header:unpack(bytes)
        if d.err ~= 0 then
            ngx_log(ngx.ERR, "zookeeper remote error: " .. const.get_err_msg(d.err) .. "," .. path)
            return nil, const.get_err_msg(d.err)
        end
        if strlen(bytes) > 16 and d.xid > 0 then
            self.xid = d.xid + 1
            local paths = unpack_strings(strsub(bytes, 21))
            return {
                xid = d.xid,
                zxid = d.zxid,
                path = paths
            }
        end
        if d.xid == const.XID_PING then
            goto continue
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
    local d, e = self:_get_children(path, 1)
    if not d then
        return d, e
    end
    self.watch = true
    return d, nil
end

local function reply_read(self, callback)
    local req = pack(">iII", 8, const.XID_PING, const.ZOO_PING_OP)
    local ok, err = self:_send(req)
    if ok then
        local rsp, err = self:_receive(4)
        if not rsp then
            return rsp, err
        end
        local len = self._rspLen(rsp)
        if len then
            local bytes = self:_receive(len)
            local xid = unpack(">i", bytes)
            if xid == const.XID_PING then
                ngx_log(ngx.DEBUG,
                        "Got ping zookeeper response host:" ..
                                self.host .. " for sessionId:" .. util.long_to_hex_string(self.session_id)
                )
            elseif xid == const.XID_WATCH_EVENT then
                --decoding
                local xid, done, err, type, state = unpack(">iliii", bytes)
                local eventPath = unpack_strings(strsub(bytes, 25))
                local t = eventPath[1]
                local d, e = self:add_watch("" .. t)
                if d then
                    callback(d.path)
                end
            end
        end
    end
    return ok, err
end

function _M.watch_receive(self, callback)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end
    local last_time = 0
    while true do
        if exiting() then
            self:_close()
            return true
        end
        local can_ping = now() - last_time > self.ping_time
        if can_ping then
            local ok, err = reply_read(self, callback)
            if err then
                return nil, err
            end
            last_time = now()
        end
        -- self:_receive1()
        -- //表示200ms.
        sleep(0.2)
    end
end

function _M._close(self)
    -- body
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end
    return sock:close()
end

function _M.set_timeouts(self, connect_timeout, send_timeout, read_timeout)
    local sock = rawget(self, "sock")
    if not sock then
        error("not initialized", 2)
        return
    end
    
    sock:settimeouts(connect_timeout, send_timeout, read_timeout)
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
