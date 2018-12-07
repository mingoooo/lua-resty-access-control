# API 文档

- [API 文档](#api-%E6%96%87%E6%A1%A3)
    - [部署 API](#%E9%83%A8%E7%BD%B2-api)
    - [GET](#get)
    - [POST](#post)
    - [PUT](#put)
    - [DELETE](#delete)

## 部署 API

修改 nginx 配置文件，新增 server 块

```
vim openresty/nginx.conf
```

```
server {
	listen     4001;

	location ~ /api/access-control/(.*) {
                default_type application/json;
		content_by_lua_file /data/svr/openresty/lualib/access_control/api.lua;
	}
}
```

```
/data/sh/openresty.sh reload
```

## GET

## POST

## PUT

## DELETE
