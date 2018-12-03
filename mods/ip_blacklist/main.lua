local base = require "access_control.mods.base"
local cfg = require "access_control.mods.ip_blacklist.config"
local gcfg = require "access_control.config"
local logger = require "access_control.utils.logger"
logger.mod_name = "ip_blacklist"

local _M = {}
setmetatable(_M, {__index = base})

local mod_redis_key_prefix = "ip_blacklist"

-- 覆盖shared.dict
function _M.sync_shared_dict(dict_name, data)
    local dict = ngx.shared[dict_name]

    if type(data) ~= "table" then
        logger:err("Data must table type")
        return
    end

    -- 清空dict
    -- TODO: 是否能一次覆盖所有
    logger:debug("Flush blacklist")
    dict:flush_all()

    -- 写入
    for key, ext in pairs(data) do
        if not ext then
            logger:warn("No value in the key: " .. key)
        else
            if ext == "0" then
                logger:debug("Set for " .. dict_name .. " key: " .. key .. ", expire: 0")
                dict:set(key, 1)
            else
                local ex = ext - math.floor(ngx.now())
                if ex <= 0 then
                    logger:warn("The key expired: " .. key)
                else
                    logger:debug("Set for " .. dict_name .. " key: " .. key .. ", expire: " .. ex)
                    dict:set(key, 1, ex)
                end
            end
        end
    end
end

function _M.on_sync(self)
    logger:debug("Begin of update blacklist")
    local new_ip_blacklist

    -- 从redis或缓存文件读取数据
    new_ip_blacklist = self:fetch_data(mod_redis_key_prefix, gcfg.cache_file_basepath .. cfg.cache_file)

    -- 同步共享内存字典
    self.sync_shared_dict(cfg.dict_name, new_ip_blacklist)

    logger:debug("End of update blacklist")
end

function _M.on_filter(self)
    local ip = self.get_user_ip()
    logger:debug("User IP: " .. ip)
    local ip_blacklist = ngx.shared[cfg.dict_name]

    if ip_blacklist:get(ip) then
        logger:warn("Banned IP detected and refused access: " .. ip)
        return ngx.exit(ngx.HTTP_FORBIDDEN)
    end
end

return _M
