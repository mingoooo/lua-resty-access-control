local _M = {}

-- dict name
_M.dict_name = "ip_blacklist"

-- redis ip
_M.redis_host = "127.0.0.1"

-- redis port
_M.redis_port = 6379

-- redis连接超时时间
_M.redis_connect_timeout = 100

-- redis存储黑名单的set key
_M.redis_key_prefix = "blacklist"

-- 黑名单缓存文件路径
_M.cache_file = "/tmp/ip_blacklist"

-- 同步黑名单时间间隔（单位：秒）
_M.sync_interval = 60

return _M
