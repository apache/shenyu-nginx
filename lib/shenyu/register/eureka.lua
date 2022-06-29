local _M = {}

local http = require("resty.http")
local json = require("cjson")
local ngx_balancer = require("ngx.balancer")

local balancer = require("shenyu.register.balancer")

local ngx = ngx

local ngx_timer_at = ngx.timer.at
local ngx_worker_exiting = ngx.worker.exiting


local log = ngx.log
local ERR = ngx.ERR
local INFO = ngx.INFO


local function get_server_list()

    local httpc = http:new()

    local res, err = httpc:request_uri(_M.base_url, {
        method = "GET",
        path = _M.path,
        headers = {["Accept"]="application/json"},
    })
    if not res then
        log(ERR, "failed to get server list from eureka. ", err)
        return
    end

    local service = {}
    service.upstreams = {}

    if res.status == 200 then

        local list_inst_resp = json.decode(res.body)

        for k, v in ipairs(list_inst_resp) do

            local passing = true

            local instances = v["instance"]

            for i, instance in pairs(instances) do
                local status = instance["status"]
                if status == "UP" then
                    local ipAddr = instance["ipAddr"]
                    local port = instance["port"]["$"]
                    log(INFO, "ipAddr: ", ipAddr)
                    log(INFO, "port: ", port)
                    table.insert(service.upstreams, {ip=ipAddr, port=port})
                end
            end
        end
    end

    return service


end



function _M.init(conf)
    _M.storage = conf.shenyu_storage

    _M.balancer = balancer.new(conf.balancer_type)


end