local _M = {}

local http = require("resty.http")
local json = require("cjson")


local ngx = ngx

local ngx_timer_at = ngx.timer.at
local ngx_worker_exiting = ngx.worker.exiting


local log = ngx.log
local ERR = ngx.ERR
local INFO = ngx.INFO


function  _M:get_server_list()

    local httpc = http:new()

    local res, err = httpc:request_uri(_M.base_url, {
        method = "GET",
        path = _M.path,
        headers = {["Accept"]="application/json"},
    })
    if not res then
        log(ERR, "failed to get server list from eureka. ", err)
    end

    local service = {}

    if res.status == 200 then

        local list_inst_resp = json.decode(res.body)
        local application = list_inst_resp.application
        for k, v in ipairs(application) do

            local instances = v["instance"]

            for i, instance in pairs(instances) do
                local status = instance["status"]
                if status == "UP" then
                    local ipAddr = instance["ipAddr"]
                    local port = instance["port"]["$"]
                    log(INFO, "ipAddr: ", ipAddr)
                    log(INFO, "port: ", port)
                    service[i] = {ip=ipAddr, port=port}
                end
            end
        end
    end

    _M.storage:set("demo", json.encode(service))


end


function _M:get_upstreams()
    local upstreams_str = _M.storage:get("demo");
    local tmp_upstreams = json.decode(upstreams_str);
    return tmp_upstreams;
end



function _M.init(conf)
    _M.storage = conf.upstream_list
    _M.base_url = conf.base_url
    _M.path = conf.path

end