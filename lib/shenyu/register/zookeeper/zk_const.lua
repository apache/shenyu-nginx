--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"), you may not use this file except in compliance with
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

local _M = {}

-- XID
_M.XID_WATCH_EVENT = -1

_M.XID_PING = -2

_M.XID_SET_WATCHES = -8

--op code

_M.ZOO_GET_CHILDREN = 8

_M.ZOO_PING_OP = 11

_M.ZOO_GET_CHILDREN2 = 12

_M.ZOO_SET_WATCHES = 101

_M.ZOO_ADD_WATCH = 106

_M.ZK_WATCH_PATH = "/shenyu/register/instance";

--Definition of error codes.
local error_code = {
    "0", "-1", "-2", "-3", "-4", "-5", "-6", "-7", "-8", "-100",
    "-101", "-102", "-103", "-108", "-110", "-111", "-112",
    "-113", "-114", "-115", "-118", "-119" }


--errorcode
local error_msg = {
    err0 = "Ok",
    err1 = "System error",
    err2 = "Runtime inconsistency",
    err3 = "Data inconsistency",
    err4 = "Connection loss",
    err5 = "Marshalling error",
    err6 = "Operation is unimplemented",
    err7 = "Operation timeout",
    err8 = "Invalid arguments",
    err9 = "API errors.",
    err101 = "Node does not exist",
    err102 = "Not authenticated",
    err103 = "Version conflict",
    err108 = "Ephemeral nodes may not have children",
    err110 = "The node already exists",
    err111 = "The node has children",
    err112 = "The session has been expired by the server",
    err113 = "Invalid callback specified",
    err114 = "Invalid ACL specified",
    err115 = "Client authentication failed",
    err118 = "Session moved to another server, so operation is ignored",
    err119 = "State-changing request is passed to read-only server",
}
for i = 1, #error_code do
    local cmd = "err" .. (error_code[i] * -1)
    _M[cmd] = error_msg.cmd
end

function _M.get_err_msg(code)
    if not code then
        return "unknown"
    end
    return error_msg["err" .. (code * -1)]
end

return _M