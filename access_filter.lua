local cfg = require "access_control.config"

local function filter()
    for _, mod in ipairs(cfg.mods) do
        local m = require("access_control.mods." .. mod .. ".main")
        m:on_filter()
    end
end

xpcall(
    filter,
    function(err)
        ngx.log(ngx.ERR, err)
    end
)
