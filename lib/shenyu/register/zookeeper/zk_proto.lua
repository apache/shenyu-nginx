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
local struct = require("shenyu.register.core.struct")
local pack = struct.pack
local unpack = struct.unpack
local tbunpack = struct.tbunpack
local strbyte = string.byte
local strlen = string.len
local strsub = string.sub

local _M = {}

local _base = {
    new = function(self, o)
        o = o or {}
        setmetatable(o, self)
        return o
    end
}

local _request_header =
    _base:new {
    xid = 0,
    type = 0,
    pack = function(self)
        return pack(">II", self.xid, self.type)
    end
}

local _get_children_request =
    _base:new {
    path = "",
    watch = 0,
    pack = function(self)
        local path_len = strlen(self.path)
        return pack(">ic" .. path_len .. "b", path_len, self.path, strbyte(self.watch))
    end
}

local _ping_request =
    _base:new {
    pack = function(self)
        local stream = {}
        return table.concat(stream)
    end
}

local _connect_request =
    _base:new {
    protocol_version = 0,
    last_zxid_seen = 0,
    timeout = 0,
    session_id = 0,
    password = "",
    pack = function(self)
        return pack(">lilic16", 0, 0, 0, 0, "")
    end
}

function _M.serialize(self, h, request)
    local h_bytes = h:pack()
    local r_bytes = request:pack()
    local len = h_bytes:len() + r_bytes:len()
    local len_bytes = pack(">i", len)
    return len_bytes .. h_bytes .. r_bytes
end

_M.get_children_request = _get_children_request
_M.request_header = _request_header
_M.ping_request = _ping_request
_M.connect_request = _connect_request

--basics of response.
local _reply_header =
    _base:new {
    xid = 0, -- int
    zxid = 0, -- long
    err = 0, -- int
    unpack = function(self, bytes, start_index)
        local vars, end_index = unpack(">ili", bytes, start_index)
        self.xid, self.zxid, self.err = tbunpack(vars)
        return self, end_index
    end
}

local _connect_response =
    _base:new {
    proto_ver = 0,
    timeout = 0,
    session_id = 0,
    password = "",
    unpack = function(self, bytes, start_index)
        local vars, end_index = unpack(">iilS", bytes, start_index)
        self.proto_ver, self.timeout, self.session_id, self.password = tbunpack(vars)
        return self, end_index
    end
}

local function unpack_strings(str)
    local size = strlen(str)
    local pos = 0
    local str_set = {}
    local index = 1
    while size > pos do
        local vars = unpack(">i", strsub(str, 1 + pos, 4 + pos))
        local len = tbunpack(vars)
        vars = unpack(">c" .. len, strsub(str, 5 + pos, 5 + pos + len - 1))
        local s = tbunpack(vars)
        str_set[index] = s
        index = index + 1
        pos = pos + len + 4
    end
    return str_set
end

local _get_children_response =
    _base:new {
    paths = {},
    unpack = function(self, bytes, start_index)
        self.paths = unpack_strings(strsub(bytes, 21))
        return self
    end
}

local _watch_event =
    _base:new {
    type = 0,
    state = 0,
    paths = {},
    unpack = function(self, bytes, start_index)
        local vars = unpack(">ii", bytes, start_index)
        self.type, self.state = tbunpack(vars)
        self.paths = unpack_strings(strsub(bytes, 25))
        return self
    end
}

_M.reply_header = _reply_header
_M.connect_response = _connect_response
_M.get_children_response = _get_children_response
_M.watch_event = _watch_event

return _M
