local cfg = require "access_control.config"

local function sync()
    for _, mod in ipairs(cfg.mods) do
        local m = require("access_control.mods." .. mod .. ".main")
        m:sync()
    end
end

local function handler(premature)
    if not premature then
        sync()
        local ok, err = ngx.timer.at(cfg.sync_interval, handler)
        if not ok then
            ngx.log(ngx.ERR, "failed to create timer: ", err)
            return
        end
    end
end

-- 同步黑名单定时任务
local function sync_loop()
    if 0 == ngx.worker.id() then
        ngx.timer.at(0, sync)
        local ok, err = ngx.timer.at(cfg.sync_interval, handler)
        if not ok then
            ngx.log(ngx.ERR, "failed to create timer: ", err)
            return
        end
        ngx.log(ngx.INFO, "Sync loop start")
    end
end

xpcall(
    sync_loop,
    function(err)
        ngx.log(ngx.ERR, err)
    end
)
