--[[
Openresty IP Blacklist
Return 403(FORBIDDEN) if client IP in the blacklist

redis key prefix: ip_blacklist
--]]
local base = require "access_control.mods.base"
local cfg = require "access_control.mods.ip_blacklist.config"
local gcfg = require "access_control.config"
local iputils = require "access_control.utils.iputils"
local logger_mod = require "access_control.utils.logger"
local logger = logger_mod:new("ip_blacklist")

local _M = {}
setmetatable(_M, {__index = base})

local mod_redis_key_prefix = "ip_blacklist"

function _M.set_ip(dict, ip, expireat)
    if expireat == 0 then
        dict:set(ip, 1)
    else
        local ex = expireat - math.floor(ngx.now())
        if ex <= 0 then
            logger:warn("The ip expired: " .. ip)
        else
            dict:set(ip, 1, ex)
        end
    end
end

-- 覆盖shared.dict
function _M.sync_shared_dict(self, dict_name, data)
    local dict = ngx.shared[dict_name]

    if type(data) ~= "table" then
        logger:err("Data must table type")
        return
    end

    -- 清空dict
    -- TODO: 是否能一次覆盖所有
    dict:flush_all()

    -- 写入
    for key, val in pairs(data) do
        if not val or not val.expireat then
            logger:warn("No value in the key: " .. key)
        else
            local ext = val.expireat
            if not key:find("/") then
                -- ip addr
                self.set_ip(dict, key, ext)
            else
                -- cidr
                local ip_list = iputils.cidr2ips(key)
                for _, ip in ipairs(ip_list) do
                    self.set_ip(dict, ip, ext)
                end
            end
        end
    end
end

function _M.on_sync(self)
    local new_ip_blacklist

    -- 从redis或缓存文件读取数据
    new_ip_blacklist = self:fetch_data(mod_redis_key_prefix, gcfg.cache_file_basepath .. cfg.cache_file)

    -- 同步共享内存字典
    self:sync_shared_dict(cfg.dict_name, new_ip_blacklist)
end

function _M.on_filter(self)
    local ip = self.get_user_ip()
    local ip_blacklist = ngx.shared[cfg.dict_name]

    if ip_blacklist:get(ip) then
        logger:warn("Banned IP detected and refused access: " .. ip)
        return ngx.exit(ngx.HTTP_FORBIDDEN)
    end
end

return _M
