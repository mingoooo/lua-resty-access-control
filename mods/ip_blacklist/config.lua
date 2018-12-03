local _M = {}

-- dict name
_M.dict_name = "ip_blacklist"

-- redis存储黑名单的set key
_M.redis_key_prefix = "ip_blacklist"

-- 黑名单缓存文件路径
_M.cache_file = "/tmp/ip_blacklist"

return _M
