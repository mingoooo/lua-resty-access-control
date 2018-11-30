local cfg = require "access_control.mods.ip_blacklist.config"
local gcfg = require "access_control.config"
local cjson = require "cjson"
local redis = require "resty.redis"

-- 遇到错误返回的json response
local function say_err(status, reason, log_level)
    if not log_level then
        log_level = ngx.ERR
    end
    ngx.log(log_level, reason)
    ngx.status = status
    cjson.encode_empty_table_as_object(false)
    ngx.say(cjson.encode({data = {}, reason = reason}))
end

-- 创建redis连接
local red = redis:new()
red:set_timeout(gcfg.redis_connect_timeout)
local ok, err = red:connect(gcfg.redis_host, gcfg.redis_port)
if not ok then
    local reason = "Redis connection error while retrieving ip_blacklist: " .. err
    say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
    ngx.exit(ngx.HTTP_OK)
end

-- 保持redis连接
local function keepalive()
    local ok, err = red:set_keepalive(60000, 50)
    if not ok then
        ngx.log(ngx.ERR, "Redis failed to set keepalive: ", err)
        local ok, err = red:close()
        if not ok then
            ngx.log(ngx.ERR, "Redis failed to close: ", err)
        end
    end
end

-- 获取请求body并decode
local function req_body()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    ngx.log(ngx.DEBUG, "Request body: " .. body)
    local ok, data = pcall(cjson.decode, body)
    if not ok then
        local reason = "Json decode err, please check your request body is array"
        say_err(ngx.HTTP_BAD_REQUEST, reason)
        return nil
    end
    return data
end

-- 生成黑名单key
local function gen_key(ip, expireat, expire)
    local key
    if expireat and expireat ~= 0 then
        expire = expireat - math.floor(ngx.now())
    end

    if expire and expire ~= 0 then
        if not expireat then
            expireat = math.floor(ngx.now()) + expire
        end
    else
        expire = 0
        expireat = 0
    end

    key = "access_control:" .. cfg.redis_key_prefix .. ":" .. ip
    ngx.log(ngx.DEBUG, "Generate key: " .. key)
    if expireat == 0 then
        return key, expireat, nil
    end
    return key, expireat, expire
end

local function get()
    local data = {}
    -- 获取黑名单全部key
    local ip_blacklist_expireat
    local ip_blacklist, err = red:keys("access_control:" .. cfg.redis_key_prefix .. ":*")
    if err then
        local reason = "Redis read error: " .. err
        say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
        return
    end
    if ip_blacklist[1] ~= nil then
        ip_blacklist_expireat, err = red:mget(unpack(ip_blacklist))
        if err then
            local reason = "Redis read error: " .. err
            say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
            return
        end
    end

    for index, key in ipairs(ip_blacklist) do
        local ext = ip_blacklist_expireat[index]
        local _, _, ip = string.match(key, "(.*):(.*):(.*)")
        table.insert(data, {ip = ip, expireat = tonumber(ext), key = key})
    end

    cjson.encode_empty_table_as_object(false)
    ngx.say(cjson.encode({data = data, reason = ""}))
    return
end

local function post()
    local resp = {}
    local data = req_body()
    if not data then
        return
    end
    if data[1] == nil then
        say_err(ngx.HTTP_BAD_REQUEST, "Request body must an array and not empty")
        return
    end

    local ok, err = red:multi()
    if not ok then
        ngx.say("Failed to run multi: ", err)
        say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
        return
    end

    for _, ip_info in ipairs(data) do
        local ip = ip_info["ip"]
        local expireat = ip_info["expireat"]
        local expire = ip_info["expire"]

        if not ip then
            local reason = "Missing argument 'ip'"
            say_err(ngx.HTTP_BAD_REQUEST, reason)
            local ok, err = red:discard()
            if err then
                ngx.log(ngx.ERR, "Discard err: " .. err)
            end
            return
        end

        -- set key
        local key, exat, ex = gen_key(ip, expireat, expire)
        local res, err
        if ex then
            res, err = red:set(key, exat, "EX", ex, "NX")
        else
            res, err = red:set(key, exat, "NX")
        end
        if err then
            ngx.log(ngx.ERR, "Set redis key err: " .. err)
            say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
            local ok, err = red:discard()
            if err then
                ngx.log(ngx.ERR, "Discard err: " .. err)
            end
            return
        end

        table.insert(resp, {ip = ip, expireat = exat, key = key})
    end

    local ans, err = red:exec()
    if err then
        ngx.say("Failed to run exec: ", err)
        say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
        local ok, err = red:discard()
        if err then
            ngx.log(ngx.ERR, "Discard err: " .. err)
        end
        return
    end

    for index, res in ipairs(ans) do
        resp[index]["result"] = res
    end

    cjson.encode_empty_table_as_object(false)
    ngx.say(cjson.encode({data = resp, reason = ""}))
    return
end

local function put()
    local resp = {}
    local data = req_body()
    if not data then
        return
    end
    if data[1] == nil then
        say_err(ngx.HTTP_BAD_REQUEST, "Request body must an array and not empty")
        return
    end

    local ok, err = red:multi()
    if not ok then
        ngx.say("Failed to run multi: ", err)
        say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
        return
    end

    for _, ip_info in ipairs(data) do
        local ip = ip_info["ip"]
        local expireat = ip_info["expireat"]
        local expire = ip_info["expire"]

        if ip then
            local key, exat, ex = gen_key(ip, expireat, expire)

            -- Set key
            ngx.log(ngx.DEBUG, "Set redis key: " .. key)
            local res, err
            if not ex then
                res, err = red:set(key, exat)
            else
                if ex > 0 then
                    res, err = red:set(key, exat, "EX", ex)
                end
            end
            if err then
                ngx.log(ngx.ERR, "Set redis key err: " .. err)
                say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
                local ok, err = red:discard()
                if err then
                    ngx.log(ngx.ERR, "Discard err: " .. err)
                end
                return
            end
            table.insert(resp, {ip = ip, expireat = exat, key = key})
        end
    end

    local ans, err = red:exec()
    if err then
        ngx.say("Failed to run exec: ", err)
        say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
        local ok, err = red:discard()
        if err then
            ngx.log(ngx.ERR, "Discard err: " .. err)
        end
        return
    end

    for index, res in ipairs(ans) do
        resp[index]["result"] = res
    end

    cjson.encode_empty_table_as_object(false)
    ngx.say(cjson.encode({data = resp, reason = ""}))
    return
end

local function delete()
    local resp = {}
    local args = ngx.req.get_uri_args()
    for k, v in pairs(args) do
        if k == "ip" then
            local ok, err = red:multi()
            if not ok then
                ngx.say("Failed to run multi: ", err)
                say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
                return
            end

            for ip in v:gmatch("[^,]+") do
                local key = "access_control:" .. cfg.redis_key_prefix .. ":" .. ip:gsub("%s+", "")

                -- Delete key
                local res, err = red:del(key)
                if err then
                    ngx.say("Failed to run del: ", err)
                    say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
                    local ok, err = red:discard()
                    if err then
                        ngx.log(ngx.ERR, "Discard err: " .. err)
                    end
                    return
                end
                table.insert(resp, {ip = ip, key = key})
            end

            local ans, err = red:exec()
            if err then
                ngx.say("Failed to run exec: ", err)
                say_err(ngx.HTTP_INTERNAL_SERVER_ERROR, reason)
                local ok, err = red:discard()
                if err then
                    ngx.log(ngx.ERR, "Discard err: " .. err)
                end
                return
            end

            for index, res in ipairs(ans) do
                resp[index]["result"] = res
            end
        end
    end

    cjson.encode_empty_table_as_object(false)
    ngx.say(cjson.encode({data = resp, reason = ""}))
    return
end

local method_name = ngx.req.get_method()
if method_name == "GET" then
    get()
elseif method_name == "POST" then
    post()
elseif method_name == "PUT" then
    put()
elseif method_name == "DELETE" then
    delete()
else
    local reason = "Unknown method: " .. method_name
    say_err(ngx.HTTP_BAD_REQUEST, reason, ngx.WARN)
end
keepalive()
ngx.exit(ngx.HTTP_OK)
