--[[
       使用openresty实现基于uri的限流功能
       nginx配置: 
       http {
           lua_shared_dict uri_limit_map 10m;
           lua_shared_dict qps_limit_store 10m;
       }
       author: frank chen
--]]
local limit_req = require "resty.limit.req"
local base = require "access_control.mods.base"
local common_cfg = require "access_control.config"
local logger_mod = require "access_control.utils.logger"
local logger = logger_mod:new("traffic_control")

local uri_limit_map = ngx.shared["uri_limit_map"]
local redis_key_prefix = "traffic_limit"
local cache_file_path = common_cfg.cache_file_basepath .. "traffic_limit_setting.json"

local _M = {}
setmetatable(_M, {__index = base})

--[[
       redis同步配置回调
--]]
function _M.on_sync(self)
    logger:info("updating traffic limiting config")

    -- 从redis或缓存文件读取数据
    local config_list = self:fetch_data(redis_key_prefix, cache_file_path)

    -- 更新共享内存
    if config_list == nil or next(config_list) == nil then
        logger:warn("NO CONFIG DATA FOUND FROM REDIS OR CACHE FILE")
        return
    end

    uri_limit_map:flush_all()
    for k, v in pairs(config_list) do
        local limit = tonumber(v)
        if limit == nil then
            logger:warn("non-number value " .. v .. " for key " .. k)
        else
            uri_limit_map:set(k, limit)
        end
    end
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
        logger:err("failed to instantiate a resty.limit.req object: " .. err .. ", uri: " .. uri)
        return nil
    end
    return result
end

--[[
       核心函数，对uri实行限流
--]]
function _M.on_filter(self)
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
        logger:err("failed to limit req: " .. err)
        return ngx.exit(500)
    end

    if delay >= 0.001 then
        -- 当 $qps_limit < QPS < qps_limit + $burst时, 为了保持QPS == $qps_limit，这里delay一段时间
        logger:debug("delay it here a bit to conform to the connection limit, time: " .. delay)
        ngx.sleep(delay)
    end
end

return _M
