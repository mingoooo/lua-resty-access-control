# 模块开发文档

- [模块开发文档](#%E6%A8%A1%E5%9D%97%E5%BC%80%E5%8F%91%E6%96%87%E6%A1%A3)
- [接口规范](#%E6%8E%A5%E5%8F%A3%E8%A7%84%E8%8C%83)
    - [1. 模块名称和目录名称一样](#1-%E6%A8%A1%E5%9D%97%E5%90%8D%E7%A7%B0%E5%92%8C%E7%9B%AE%E5%BD%95%E5%90%8D%E7%A7%B0%E4%B8%80%E6%A0%B7)
    - [2. 目录下有 main.lua](#2-%E7%9B%AE%E5%BD%95%E4%B8%8B%E6%9C%89-%08mainlua)
    - [3. main.lua 继承 mods/base.lua](#3-mainlua-%E7%BB%A7%E6%89%BF-modsbaselua)
    - [4. main.lua 里实现 sync 和 filter 两个 function](#4-mainlua-%E9%87%8C%E5%AE%9E%E7%8E%B0-sync-%E5%92%8C-filter-%E4%B8%A4%E4%B8%AA-function)

# 接口规范

## 1. 模块名称和目录名称一样

Example:

总配置文件 mods 填写的是 ip_blacklist, mods 目录下目录名也需要一样：mods/ip_blacklist

## 2. 目录下有 main.lua

## 3. main.lua 继承 mods/base.lua

Example:

```
local base = require "access_control.mods.base"

local _M = {}
setmetatable(_M, {__index = base})
```

## 4. main.lua 里实现 sync 和 filter 两个 function

Example:

```
function _M.on_sync(self)
    print("I am sync function")
end

function _M.on_filter(self)
    print("I am filter function")
end
```
