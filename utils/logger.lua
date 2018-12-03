local _M = {}

_M.mod_name = ""

function _M.log(self, level, msg)
    ngx.log(level, "[" .. self.mod_name .. "] ", msg)
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
