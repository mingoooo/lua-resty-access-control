local base = require "access_filter.mods.base"
local cfg = require "access_filter.mods.ip_blacklist.config"

local _M = {}
setmetatable(_M, {__index = base})

-- 覆盖shared.dict
function _M.sync_shared_dict(dict_name, data)
    local dict = ngx.shared[dict_name]

    -- 清空dict
    -- TODO: 是否能一次覆盖所有
    ngx.log(ngx.DEBUG, "Flush blacklist")
    dict:flush_all()

    -- 写入
    for k, ext in pairs(data) do
        if not ext then
            ngx.log(ngx.WARN, "No value in the key: " .. k)
        else
            local _, _, key = string.match(k, "(.*):(.*):(.*)")

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

function _M.sync(self)
    ngx.log(ngx.DEBUG, "Begin of update blacklist")
    local new_ip_blacklist

    -- 连接redis
    local ok, err = self:connect_redis(cfg.redis_host, cfg.redis_port, cfg.redis_connect_timeout)
    if not ok then
        -- 加载缓存文件
        new_ip_blacklist = self.load_file(cfg.cache_file)
    else
        -- 从redis拉取数据
        new_ip_blacklist = self:fetch_data(cfg.redis_key_prefix, cfg.cache_file)
    end

    -- 同步共享内存字典
    self.sync_shared_dict(cfg.dict_name, new_ip_blacklist)

    -- 备份到缓存文件
    self.dump_file(cfg.cache_file, new_ip_blacklist)

    -- keepalive
    self:keepalive_redis()
    ngx.log(ngx.DEBUG, "End of update blacklist")
end

function _M.filter(self)
    local ip = self.get_user_ip()
    ngx.log(ngx.DEBUG, "User IP: " .. ip)
    local ip_blacklist = ngx.shared[cfg.dict_name]

    if ip_blacklist:get(ip) then
        ngx.log(ngx.WARN, "Banned IP detected and refused access: " .. ip)
        return ngx.exit(ngx.HTTP_FORBIDDEN)
    end
end

return _M
