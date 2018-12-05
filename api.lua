local gcfg = require "access_control.config"
local cjson = require "cjson"
local redis = require "resty.redis"
local logger_mod = require "access_control.utils.logger"
local logger = logger_mod:new("api")
local _M = {}
local mt = {__index = _M}

-- 遇到错误返回的json response
function _M.say_err(self, status, reason, log_level)
    if not log_level then
        log_level = ngx.ERR
    end
    logger:log(log_level, reason)
    ngx.status = status

    self.say_json({}, reason)
end

function _M.say_json(data, reason)
    if reason == nil then
        reason = ""
    end
    cjson.encode_empty_table_as_object(false)
    ngx.say(cjson.encode({data = data, reason = reason}))
end

-- 创建redis连接
function _M.connect_redis(self)
    self.redis = redis:new()
    self.redis:set_timeout(gcfg.redis_connect_timeout)
    local ok, err = self.redis:connect(gcfg.redis_host, gcfg.redis_port)
    if not ok then
        local reason = "Redis connection error while retrieving ip_blacklist: " .. err
        self:say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
        ngx.exit(ngx.HTTP_OK)
    end
end

-- 保持redis连接
function _M.keepalive(self)
    local ok, err = self.redis:set_keepalive(60000, 50)
    if not ok then
        logger:err("Redis failed to set keepalive: " .. err)
        local ok, err = self.redis:close()
        if not ok then
            logger:err("Redis failed to close: " .. err)
        end
    end
end

-- 获取请求body并decode
function _M.req_body()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    logger:debug("Request body: " .. body)
    local ok, data = pcall(cjson.decode, body)
    if not ok then
        local reason = "Json decode err, please check your request body is array"
        self:say_err(ngx.HTTP_BAD_REQUEST, reason)
        return nil
    end
    return data
end

function _M.full_key(mod_redis_key_prefix, real_key)
    if real_key == nil then
        real_key = ""
    end
    return gcfg.common_redis_key_prefix .. ":" .. mod_redis_key_prefix .. ":" .. real_key
end

function _M.get(self)
    local data = {}
    local keys = {}
    local vals = {}
    local args, err = ngx.req.get_uri_args()
    if err then
        self:say_err(ngx.HTTP_BAD_REQUEST, "Failed to request argument: " .. err)
        return
    end

    local redis_full_key_prefix = self.full_key(self.mod)

    -- 先获取mod所有key
    cursor = 0
    while true do
        local res, err = self.redis:scan(cursor, "MATCH", redis_full_key_prefix .. "*", "COUNT", 1000)
        if err then
            self:say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, "Redis read error while retrieving keys: " .. err)
            return
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
            self:say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, "Redis read error while retrieving values: " .. err)
            return
        end
    end

    -- 合并数据并剥掉key的前缀
    for i, key in ipairs(keys) do
        local real_key = string.sub(key, #redis_full_key_prefix + 1)
        table.insert(data, {key = real_key, value = vals[i], full_key = key})
    end

    self.say_json(data)
    return
end

function _M.post(self)
    local resp = {}
    local data = self.req_body()
    if not data then
        return
    end
    if data[1] == nil then
        self:say_err(ngx.HTTP_BAD_REQUEST, "Request body must an array and not empty")
        return
    end

    local ok, err = self.redis:multi()
    if not ok then
        local reason = "Failed to run multi: " .. err
        self:say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
        return
    end

    for _, row in ipairs(data) do
        local key = row["key"]
        local value = row["value"]
        local expire = row["expire"]
        local expireat = row["expireat"]

        if not key or not value then
            local reason = "Missing argument 'key' or 'value'"
            self:say_err(ngx.HTTP_BAD_REQUEST, reason)
            local ok, err = self.redis:discard()
            if err then
                logger:err("Discard err: " .. err)
            end
            return
        end

        local full_key = self.full_key(self.mod, key)

        -- set key
        local res, err
        if expireat ~= nil then
            expire = expireat - math.floor(ngx.now())
            res, err = self.redis:set(full_key, value, "EX", expire, "NX")
        elseif expire ~= nil and expire ~= 0 and expireat == nil then
            res, err = self.redis:set(full_key, value, "EX", expire, "NX")
        else
            res, err = self.redis:set(full_key, value, "NX")
        end

        if err then
            logger:err("Set redis key err: " .. err)
            self:say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
            local ok, err = self.redis:discard()
            if err then
                logger:err("Discard err: " .. err)
            end
            return
        end

        table.insert(resp, {key = key, value = value, full_key = full_key})
    end

    local ans, err = self.redis:exec()
    if err then
        local reason = "Failed to run exec: " .. err
        self:say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
        local ok, err = self.redis:discard()
        if err then
            logger:err("Discard err: " .. err)
        end
        return
    end

    for index, res in ipairs(ans) do
        resp[index]["result"] = res
    end

    self.say_json(resp)
    return
end

function _M.put(self)
    local resp = {}
    local data = self.req_body()
    if not data then
        return
    end
    if data[1] == nil then
        self:say_err(ngx.HTTP_BAD_REQUEST, "Request body must an array and not empty")
        return
    end

    local ok, err = self.redis:multi()
    if not ok then
        local reason = "Failed to run multi: " .. err
        self:say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
        return
    end

    for _, row in ipairs(data) do
        local key = row["key"]
        local value = row["value"]
        local expire = row["expire"]
        local expireat = row["expireat"]

        if not key then
            local reason = "Missing argument 'key'"
            self:say_err(ngx.HTTP_BAD_REQUEST, reason)
            local ok, err = self.redis:discard()
            if err then
                logger:err("Discard err: " .. err)
            end
            return
        end

        local full_key = self.full_key(self.mod, key)

        -- set key
        local res, err
        if expireat ~= nil then
            expire = expireat - math.floor(ngx.now())
            res, err = self.redis:set(full_key, value, "EX", expire)
        elseif expire ~= nil and expire ~= 0 and expireat == nil then
            res, err = self.redis:set(full_key, value, "EX", expire)
        else
            res, err = self.redis:set(full_key, value)
        end

        if err then
            logger:err("Set redis key err: " .. err)
            self:say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
            local ok, err = self.redis:discard()
            if err then
                logger:err("Discard err: " .. err)
            end
            return
        end

        table.insert(resp, {key = key, value = value, full_key = full_key})
    end

    local ans, err = self.redis:exec()
    if err then
        ngx.say("Failed to run exec: ", err)
        self:say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
        local ok, err = self.redis:discard()
        if err then
            logger:err("Discard err: " .. err)
        end
        return
    end

    for index, res in ipairs(ans) do
        resp[index]["result"] = res
    end

    self.say_json(resp)
    return
end

function _M.delete(self)
    local resp = {}
    local data = self.req_body()
    if not data then
        return
    end
    local keys = data["keys"]
    if keys == nil then
        local reason = "Missing argument 'key'"
        self:say_err(ngx.HTTP_BAD_REQUEST, reason)
        return
    end

    local ok, err = self.redis:multi()
    if not ok then
        local reason = "Failed to run multi: " .. err
        self:say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
        return
    end

    for _, key in ipairs(keys) do
        local full_key = self.full_key(self.mod, key)

        -- Delete key
        local res, err = self.redis:del(full_key)
        if err then
            local reason = "Failed to run del: " .. err
            self:say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
            local ok, err = self.redis:discard()
            if err then
                logger:err("Discard err: " .. err)
            end
            return
        end
        table.insert(resp, {ip = ip, key = key, full_key = full_key})
    end

    local ans, err = self.redis:exec()
    if err then
        local reason = "Failed to run exec: " .. err
        self:say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
        local ok, err = self.redis:discard()
        if err then
            logger:err("Discard err: " .. err)
        end
        return
    end

    for index, res in ipairs(ans) do
        resp[index]["result"] = res
    end

    self.say_json(resp)
    return
end

local function main()
    m = setmetatable({}, mt)
    local whitelist = gcfg.api_whitelist

    if not whitelist[ngx.var[1]] then
        m:say_err(ngx.HTTP_BAD_REQUEST, "Unknown mod", ngx.WARN)
        return
    end
    m.mod = ngx.var[1]

    local method_name = ngx.req.get_method()
    m:connect_redis()

    if method_name == "GET" then
        m:get()
    elseif method_name == "POST" then
        m:post()
    elseif method_name == "PUT" then
        m:put()
    elseif method_name == "DELETE" then
        m:delete()
    else
        local reason = "Unknown method: " .. method_name
        m:say_err(ngx.HTTP_BAD_REQUEST, reason, ngx.WARN)
    end
    m:keepalive()
    ngx.exit(ngx.HTTP_OK)
end

main()
