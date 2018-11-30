local _M = {}
-- 过滤器包名
_M.mods = {"ip_blacklist"}

-- 同步黑名单时间间隔（单位：秒）
_M.sync_interval = 60

-- redis ip
_M.redis_host = "127.0.0.1"

-- redis port
_M.redis_port = 6379

-- redis连接超时时间
_M.redis_connect_timeout = 100

return _M
