local redis = require "resty.redis"
local cjson = require "cjson"
local cfg = require "access_control.config"

local _M = {}

function _M.sync(self)
    ngx.log(ngx.WARN, "Undefined sync method")
end

function _M.filter(self)
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

-- 从redis拉取数据，连不上就从缓存文件加载
function _M.fetch_data(self, redis_key_prefix, cache_file)
    ngx.log(ngx.DEBUG, "Fetch " .. redis_key_prefix .. " data")
    local data = {}
    local keys = {}
    local vals = {}

    -- 连接redis
    local ok, err = self:connect_redis(cfg.redis_host, cfg.redis_port, cfg.redis_connect_timeout)
    if not ok then
        -- 加载缓存文件
        return self.load_file(cache_file)
    end

    -- 获取新黑名单到nginx缓存
    cursor = 0
    while true do
        local res, err = self.redis:scan(cursor, "MATCH", "access_control:" .. redis_key_prefix .. ":*", "COUNT", 1000)
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

    -- 获取有效期
    if keys[1] ~= nil then
        vals, err = self.redis:mget(unpack(keys))
        if err then
            ngx.log(ngx.ERR, "Redis read error while retrieving values: " .. err)
            return self.load_file(cache_file)
        end
    end

    -- 合并数据
    for i, key in ipairs(keys) do
        data[key] = vals[i]
    end

    -- 备份到缓存文件
    self.dump_file(cache_file, data)

    -- keepalive
    self:keepalive_redis()
    return data
end

function _M.load_file(path)
    ngx.log(ngx.DEBUG, "Load data by file: " .. path)
    local file = io.open(path, "r")
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
