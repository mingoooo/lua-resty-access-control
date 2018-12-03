local _M = {}
local mt = {__index = _M}

function _M.new(self, mod_name)
    return setmetatable({_mod_name = mod_name}, mt)
end

function _M.log(self, level, msg)
    local mod_name = rawget(self, "_mod_name")
    if not mod_name then
        return "not initialized"
    end
    ngx.log(level, "[" .. mod_name .. "] ", msg)
end

function _M.debug(self, msg)
    self:log(ngx.DEBUG, msg)
end

function _M.info(self, msg)
    self:log(ngx.INFO, msg)
end

function _M.warn(self, msg)
    self:log(ngx.WARN, msg)
end

function _M.err(self, msg)
    self:log(ngx.ERR, msg)
end

return _M
