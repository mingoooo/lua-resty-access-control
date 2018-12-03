local base = require "access_control.mods.base"
local cfg = require "access_control.mods.ip_blacklist.config"
local gcfg = require "access_control.config"

local _M = {}
setmetatable(_M, {__index = base})

-- 覆盖shared.dict
function _M.sync_shared_dict(dict_name, data)
    local dict = ngx.shared[dict_name]

    if type(data) ~= "table" then
        ngx.log(ngx.ERR, "Data must table type")
        return
    end

    -- 清空dict
    -- TODO: 是否能一次覆盖所有
    ngx.log(ngx.DEBUG, "Flush blacklist")
    dict:flush_all()

    -- 写入
    for key, ext in pairs(data) do
        if not ext then
            ngx.log(ngx.WARN, "No value in the key: " .. k)
        else
            if ext == "0" then
                ngx.log(ngx.DEBUG, "Set for " .. dict_name .. " key: " .. key .. ", expire: 0")
                dict:set(key, 1)
            else
                local ex = ext - math.floor(ngx.now())
                if ex <= 0 then
                    ngx.log(ngx.WARN, "The key expired: " .. key)
                else
                    ngx.log(ngx.DEBUG, "Set for " .. dict_name .. " key: " .. key .. ", expire: " .. ex)
                    dict:set(key, 1, ex)
                end
            end
        end
    end
end

function _M.on_sync(self)
    ngx.log(ngx.DEBUG, "Begin of update blacklist")
    local new_ip_blacklist

    -- 从redis或缓存文件读取数据
    new_ip_blacklist = self:fetch_data(cfg.redis_key_prefix, gcfg.cache_file_basepath .. cfg.cache_file)

    -- 同步共享内存字典
    self.sync_shared_dict(cfg.dict_name, new_ip_blacklist)

    ngx.log(ngx.DEBUG, "End of update blacklist")
end

function _M.on_filter(self)
    local ip = self.get_user_ip()
    ngx.log(ngx.DEBUG, "User IP: " .. ip)
    local ip_blacklist = ngx.shared[cfg.dict_name]

    if ip_blacklist:get(ip) then
        ngx.log(ngx.WARN, "Banned IP detected and refused access: " .. ip)
        return ngx.exit(ngx.HTTP_FORBIDDEN)
    end
end

return _M
