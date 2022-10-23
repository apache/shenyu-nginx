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
local str = require("shenyu.register.core.string")
local _M = {}

--Delimited string
function _M.paras_host(host, delimiter)
    return str.split(host, delimiter)
end

function _M.long_to_hex_string(long)
    return string.format("0x%06x", long)
end

-- table len
function _M.table_len(args)
    -- body
    local n = 0
    if args then
        n = #args
    end
    return n
end

return _M
