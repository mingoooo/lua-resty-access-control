local redis = require "resty.redis"
local cjson = require "cjson"
local cfg = require "access_control.config"

local _M = {}

function _M.on_sync(self)
    ngx.log(ngx.WARN, "Undefined sync method")
end

function _M.on_filter(self)
    ngx.log(ngx.WARN, "Undefined filter method")
end

-- 连接redis
function _M.connect_redis(self, host, port, timeout)
    local red = redis:new()
    if timeout then
        red:set_timeout(timeout)
    end
    local ok, err = red:connect(host, port)
    if ok then
        self.redis = red
    end
    return ok, err
end

-- Redis keepalive
function _M.keepalive_redis(self)
    return self.redis:set_keepalive(cfg.sync_interval * 2 or 60 * 2, 100)
end

-- 从redis拉取数据，只要获取失败就从缓存文件加载
function _M.fetch_data(self, mod_redis_key_prefix, cache_file)
    ngx.log(ngx.DEBUG, "Fetch " .. mod_redis_key_prefix .. " data")
    local data = {}
    local keys = {}
    local vals = {}

    -- 连接redis
    local ok, err = self:connect_redis(cfg.redis_host, cfg.redis_port, cfg.redis_connect_timeout)
    if not ok then
        -- 加载缓存文件
        return self.load_file(cache_file)
    end

    local redis_full_key_prefix = cfg.redis_common_key_prefix..":" .. mod_redis_key_prefix .. ":"

    -- 先获取mod所有key
    cursor = 0
    while true do
        local res, err = self.redis:scan(cursor, "MATCH", redis_full_key_prefix .. "*", "COUNT", 1000)
        if err then
            ngx.log(ngx.ERR, "Redis read error while retrieving keys: " .. err)
            return self.load_file(cache_file)
        end

        cursor = res[1]
        for _, k in ipairs(res[2]) do
            table.insert(keys, k)
        end

        if cursor == "0" then
            break
        end
    end

    -- 再获取key的value
    if keys[1] ~= nil then
        vals, err = self.redis:mget(unpack(keys))
        if err then
            ngx.log(ngx.ERR, "Redis read error while retrieving values: " .. err)
            return self.load_file(cache_file)
        end
    end

    -- 合并数据并剥掉key的前缀
    for i, key in ipairs(keys) do
        data[string.sub(key, #redis_full_key_prefix + 1)] = vals[i]
    end

    -- 备份到缓存文件
    self.dump_file(cache_file, data)

    -- keepalive
    self:keepalive_redis()
    return data
end

-- 从本地缓存文件中获取数据
function _M.load_file(path)
    ngx.log(ngx.DEBUG, "Load data by file: " .. path)
    local file = io.open(path, "r")
    if file == nil then
        ngx.log(ngx.WARN, "Unable to read file "..path)
        return nil
    end
    local res = cjson.decode(file:read())
    file:close()
    return res
end

function _M.dump_file(path, table)
    ngx.log(ngx.DEBUG, "Dump data into file: " .. path)
    local file = io.open(path, "w+")
    file:write(cjson.encode(table))
    file:close()
end

function _M.get_user_ip()
    local headers = ngx.req.get_headers()
    local ip = ngx.var.http_x_forwarded_for

    if not ip then
        return ngx.var.remote_addr
    end

    local index = ip:find(",")
    if not index then
        return ip
    end

    return ip:sub(1, index - 1)
end

return _M
