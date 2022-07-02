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
local const = require("shenyu.register.zookeeper.zk_const")
local proto = require("shenyu.register.zookeeper.zk_proto")
local connection = require("shenyu.register.zookeeper.connection")
local ngx_log = ngx.log
local now = ngx.now
local exiting = ngx.worker.exiting
local sleep = ngx.sleep
local strlen = string.len
local _timeout = 60 * 1000
local _M = {}
local mt = {__index = _M}

function _M.new(self)
    local conn_, err = connection:new()
    if not conn_ then
        return nil, "initialized connection error" .. err
    end
    conn_:set_timeout(_timeout)
    conn_:set_keepalive()
    return setmetatable({conn = conn_}, mt)
end

function _M.connect(self, host)
    -- body
    local conn = self.conn
    local iptables = util.paras_host(host, ":")
    local ip = iptables[1]
    local port = iptables[2]
    local byt = conn:connect(ip, port)
    if not byt then
        return nil, "connection error" .. host
    end
    local bytes, err = proto:serialize(proto.request_header, proto.connect_request)
    local b, err = conn:write(bytes)
    if not b then
        return nil, "connect error " .. ip + ":" .. port
    end
    local len = conn:read_len()
    if not len then
        return nil, "error"
    end
    local bytes = conn:read(len)
    if not bytes then
        return nil, "connection read error"
    end
    local rsp = proto.connect_response:unpack(bytes, 1)
    if not rsp then
        return nil, "error"
    end
    self.xid = 0
    local t = rsp.timeout
    self.session_timeout = rsp.timeout
    self.ping_time = (t / 3) / 1000
    self.host = host
    self.session_id = rsp.session_id
    local tostring =
        "proto_ver:" ..
        rsp.proto_ver ..
            "," .. "timeout:" .. rsp.timeout .. "," .. "session_id:" .. util.long_to_hex_string(rsp.session_id)
    ngx_log(ngx.INFO, tostring)
    return true, nil
end

function _M.get_children(self, path)
    return self:_get_children(path, 0)
end

function _M._get_children(self, path, is_watch)
    local conn = self.conn
    if not conn then
        return nil, "not initialized connection"
    end
    local xid = self.xid + 1
    local h = proto.request_header
    h.xid = xid
    h.type = const.ZOO_GET_CHILDREN
    local r = proto.get_children_request
    r.path = path
    r.watch = is_watch
    local req = proto:serialize(h, r)
    local bytes, err = conn:write(req)
    if not bytes then
        return bytes, "write bytes error"
    end
    --  If other data is received, it means that the data of the _get_children command has not been received
    ::continue::
    local rsp_header, bytes, end_index = conn:read_headler()
    if not rsp_header then
        return nil, "read headler error"
    end
    if rsp_header.err ~= 0 then
        ngx_log(ngx.ERR, "zookeeper remote error: " .. const.get_err_msg(rsp_header.err) .. "," .. path)
        return nil, const.get_err_msg(rsp_header.err)
    end
    if strlen(bytes) > 16 and rsp_header.xid > 0 then
        self.xid = rsp_header.xid + 1
        local get_children_response = proto.get_children_response:unpack(bytes, end_index)
        return {
            xid = rsp_header.xid,
            zxid = rsp_header.zxid,
            path = get_children_response.paths
        }
    end
    if rsp_header.xid == const.XID_PING then
        goto continue
    end
    return nil, "get_children error"
end

function _M.add_watch(self, path)
    -- body
    local d, e = self:_get_children(path, 1)
    if not d then
        return d, e
    end
    self.watch = true
    return d, nil
end

local function reply_read(self, callback)
    local conn = self.conn
    local h = proto.request_header
    h.xid = const.XID_PING
    h.type = const.ZOO_PING_OP
    local req = proto:serialize(h, proto.ping_request)
    local ok, err = conn:write(req)
    if ok then
        local h, bytes, end_start = conn:read_headler()
        if h.xid == const.XID_PING then
            ngx_log(
                ngx.DEBUG,
                "Got ping zookeeper response host:" ..
                    self.host .. " for sessionId:" .. util.long_to_hex_string(self.session_id)
            )
        elseif h.xid == const.XID_WATCH_EVENT then
            --decoding
            local watch_event = proto.watch_event:unpack(bytes, end_start)
            -- local xid, done, err, type, state = unpack(">iliii", bytes)
            -- local eventPath = unpack_strings(strsub(bytes, 25))
            local t = watch_event.paths[1]
            local d, e = self:add_watch(t)
            if d then
                callback(d.path)
            end
        end
    end
    return ok, err
end

function _M.watch_receive(self, callback)
    local last_time = 0
    while true do
        if exiting() then
            self.conn.close()
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
        sleep(0.2)
    end
end

return _M
