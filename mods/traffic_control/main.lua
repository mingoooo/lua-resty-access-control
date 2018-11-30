--[[
       使用openresty实现基于uri的限流功能
       author: frank chen
       
--]]
local limit_req = require "resty.limit.req"
local base = require "access_control.mods.base"


local uri_limit_map = ngx.shared["uri_limit_map"]

local _M = {}
setmetatable(_M, {__index = base})

local function logInfo(msg)
    ngx.log(ngx.INFO, "[TXCTRL] ", msg)
end

local function logError(msg)
    ngx.log(ngx.ERR, "[TXCTRL] ", msg)
end

--[[
       redis同步配置回调
--]]
function _M.sync(self)
    logInfo("Begin update traffic limiting config")

    -- 从redis或缓存文件读取数据
    local config_list = self:fetch_data("traffic_limit", "/tmp/traffic_limit_setting.json")

    -- 更新共享内存
    if config_list ~= nil then
        for k, v in pairs(config_list) do
            if (type(v) == "number") then
                uri_limit_map:set(k, v)
            end
        end
    do

    logInfo("End update traffic limiting config")
end

--[[
       为uri创建limit_req
--]]
local function new_limit_req(uri) 
    -- 限制uri的QPS为qps_limit并允许突发QPS为$burst，即如果qps_limit < QPS < qps_limit + burst，则delay处理，如果QPS > $qps_limit + $burst，则直接拒绝请求
    local qps_limit = uri_limit_map:get(uri)
    if qps_limit == nil then
        return nil
    end
    local burst = uri_limit_map:get(uri) * 0.1
    local result, err = limit_req.new("qps_limit_store", qps_limit, burst)
    if not result then
        logError("failed to instantiate a resty.limit.req object: "..err..", uri: "..uri)
        return nil
    end
    return result
end

--[[
       核心函数，对uri实行限流
--]]
function _M.filter(self)
    local uri = ngx.var.uri
    local limit_req = new_limit_req(uri)
    if (limit_req == nil) then
        return
    end
    
    local delay, err = limit_req:incoming(uri, true)
    if not delay then
        if err == "rejected" then
            -- where the throttling goes
            return ngx.exit(503)
        end
        logError("failed to limit req: "..err)
        return ngx.exit(500)
    end
    
    if delay >= 0.001 then
        -- 当 $qps_limit < QPS < qps_limit + $burst时, 为了保持QPS == $qps_limit，这里delay一段时间
        logInfo("delay it here a bit to conform to the connection limit, time: "..delay)
        ngx.sleep(delay)
    end
end

return _M