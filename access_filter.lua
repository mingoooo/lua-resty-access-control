local cfg = require "access_control.config"
local logger_mod = require "access_control.utils.logger"
local logger = logger_mod:new("access_filter")

local function filter()
    for _, mod in ipairs(cfg.mods) do
        local m = require("access_control.mods." .. mod .. ".main")
        m:on_filter()
    end
end

xpcall(
    filter,
    function(err)
        logger:err(err)
    end
)
