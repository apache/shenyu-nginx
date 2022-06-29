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

local _M = {}

REQUEST_HEADER = {
    xid = 0,
    type = 0,
    pack = function(self, bytes)
        return pack('>II', bytes, self.xid, self.type)
    end,
    
    unpack = function(self, bytes, start_idx)
        local vars, s_idx, err
        unpack('>II', bytes, start_idx)
        if not err then
            self.xid, self.type = va_unpack(vars)
        end
    end
}

RSP_HEAD = {
    len = 0,
    xid = 0,
}

return _M