local cfg = require "access_filter.config"

local function filter()
    for _, mod in ipairs(cfg.mods) do
        local m = require("access_filter.mods." .. mod .. ".main")
        m:filter()
    end
end

xpcall(
    filter,
    function(err)
        ngx.log(ngx.ERR, err)
    end
)
