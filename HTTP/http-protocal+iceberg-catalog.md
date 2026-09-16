
HTTP 格式可以拆成两套报文来看：

- **请求报文**：客户端发给服务端
- **响应报文**：服务端回给客户端

两者结构几乎对称，都是：

```text
起始行
头部字段
空行
消息体（可选）
```

其中 **空行非常关键**，它告诉对方“头部结束了，下面是 body”。

---

## 1. HTTP 请求报文格式

一个 HTTP/1.1 请求长这样：

```http
GET /v1/config?warehouse=my_wh HTTP/1.1
Host: localhost:8080
Accept: application/json
Authorization: Bearer xxx

```

如果带 body，比如 POST：

```http
POST /v1/my_wh/namespaces HTTP/1.1
Host: localhost:8080
Content-Type: application/json
Content-Length: 35

{"namespace":["db1"],"properties":{}}
```

拆开看：

### 1.1 请求行

格式：

```text
方法 SP 请求目标 SP HTTP版本 CRLF
```

例子：

```http
GET /v1/config?warehouse=my_wh HTTP/1.1
```

- `GET`：HTTP 方法
- `/v1/config?warehouse=my_wh`：请求目标，通常是路径 + 查询参数
- `HTTP/1.1`：协议版本
- `CRLF`：回车换行，也就是 `\r\n`

常见方法：

| 方法 | 语义 | 幂等 | 安全 |
|---|---|---|---|
| GET | 获取资源 | 是 | 是 |
| HEAD | 只获取头部，不要 body | 是 | 是 |
| POST | 创建、提交、执行动作 | 通常否 | 否 |
| PUT | 替换资源 | 是 | 否 |
| PATCH | 部分更新 | 通常否 | 否 |
| DELETE | 删除资源 | 是 | 否 |
| OPTIONS | 查询支持的方法 | 是 | 是 |

REST 里常见对应：

- `GET /tables`：列出表
- `POST /tables`：创建表
- `GET /tables/{table}`：加载表
- `POST /tables/{table}`：提交表更新
- `DELETE /tables/{table}`：删除表
- `HEAD /tables/{table}`：判断表是否存在

### 1.2 请求目标

常见形式：

```text
/path/to/resource?key1=value1&key2=value2
```

比如：

```text
/v1/config?warehouse=my_wh
/v1/my_wh/namespaces/db1/tables/t1
```

注意：

- `?` 后面是查询参数，多个用 `&` 分隔。
- `#fragment` 不会发给服务端，只给浏览器/客户端自己用。
- 路径和查询参数里的特殊字符要百分号编码，比如空格是 `%20`。
- 查询参数通常用于过滤、分页、指定 warehouse 等。
- 路径参数通常用于定位资源，比如 `{namespace}`、`{table}`。

### 1.3 请求头部

格式：

```text
字段名: 字段值
```

字段名大小写不敏感。

常见请求头：

| 头部 | 作用 |
|---|---|
| Host | 目标主机，HTTP/1.1 必需 |
| Accept | 我能接受什么响应格式，如 `application/json` |
| Content-Type | 我发送的 body 是什么格式 |
| Content-Length | body 有多少字节 |
| Authorization | 认证信息，如 `Bearer token` |
| User-Agent | 客户端标识 |
| Cookie | 浏览器 cookie |
| If-None-Match | 条件请求，配合 ETag |

例如：

```http
Host: localhost:8080
Accept: application/json
Content-Type: application/json
Authorization: Bearer abc123
```

`Accept` 和 `Content-Type` 容易混：

- `Accept`：我希望你返回什么格式。
- `Content-Type`：我实际发过去的 body 是什么格式。

### 1.4 空行

头部结束后必须有一个空行：

```http
Host: localhost:8080

```

这个空行就是 `\r\n`。没有它，服务端不知道头部什么时候结束。

### 1.5 请求体

GET 通常没有 body。  
POST、PUT、PATCH 通常有 body。

常见 body 格式：

- `application/json`
- `application/x-www-form-urlencoded`
- `multipart/form-data`
- `text/plain`

REST API 最常用 JSON：

```json
{
  "namespace": ["db1"],
  "properties": {
    "owner": "alice"
  }
}
```

---

## 2. HTTP 响应报文格式

响应长这样：

```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 85

{"defaults":{},"overrides":{"prefix":"my_wh"},"endpoints":["GET /v1/config"]}
```

拆开：

### 2.1 状态行

格式：

```text
HTTP版本 SP 状态码 SP 原因短语 CRLF
```

例子：

```http
HTTP/1.1 200 OK
```

常见状态码：

| 状态码 | 含义 |
|---|---|
| 200 | OK，成功 |
| 201 | Created，已创建 |
| 204 | No Content，成功但无 body |
| 301/302 | 重定向 |
| 304 | Not Modified，缓存有效 |
| 400 | Bad Request，请求格式/参数错 |
| 401 | Unauthorized，未认证 |
| 403 | Forbidden，无权限 |
| 404 | Not Found，资源不存在 |
| 405 | Method Not Allowed，方法不对 |
| 409 | Conflict，冲突 |
| 415 | Unsupported Media Type，body 类型不支持 |
| 422 | Unprocessable Entity，语义错误 |
| 500 | Internal Server Error，服务端错误 |
| 501 | Not Implemented，未实现 |
| 503 | Service Unavailable，服务不可用 |

Iceberg REST 里常见：

- `200 OK`：成功
- `400 BadRequestException`：参数错误
- `404 NoSuchWarehouseException` / `NoSuchTableException`
- `409 CommitFailedException`：提交冲突
- `501 NotImplementedException`

### 2.2 响应头部

常见响应头：

| 头部 | 作用 |
|---|---|
| Content-Type | 响应 body 格式 |
| Content-Length | 响应 body 字节数 |
| Location | 重定向或新资源地址 |
| Set-Cookie | 设置 cookie |
| ETag | 资源版本标识 |
| Cache-Control | 缓存策略 |

例如：

```http
Content-Type: application/json
Content-Length: 123
```

### 2.3 响应体

成功时可能是 JSON：

```json
{
  "defaults": {},
  "overrides": {
    "prefix": "my_wh"
  },
  "endpoints": [
    "GET /v1/config",
    "POST /v1/{prefix}/namespaces"
  ]
}
```

错误时可能是：

```json
{
  "error": {
    "message": "Unknown warehouse: my_wh",
    "type": "NoSuchWarehouseException",
    "code": 404
  }
}
```

---

## 3. 完整例子：Iceberg `GET /v1/config`

请求：

```http
GET /v1/config?warehouse=my_wh HTTP/1.1
Host: localhost:8080
Accept: application/json
Authorization: Bearer xxx

```

响应：

```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 120

{
  "defaults": {},
  "overrides": {
    "prefix": "my_wh"
  },
  "endpoints": [
    "GET /v1/config",
    "GET /v1/{prefix}/namespaces",
    "POST /v1/{prefix}/namespaces"
  ]
}
```

对应代码：

- `handleGetConfig` 处理的是 `GET /v1/config`。
- `getQueryParameter(uri, "warehouse")` 从 URL 查询参数里取 `warehouse`。
- 如果没传 `warehouse`，返回 `400 BadRequestException`。
- 如果 `warehouse` 不匹配，返回 `404 NoSuchWarehouseException`。
- 响应 JSON 里的 `overrides.prefix` 告诉客户端：后续请求要带上前缀。
- 遍历 `getIcebergRESTRoutes()` 是为了生成 `endpoints`，这是服务发现。

---

## 4. 完整例子：创建 Namespace

请求：

```http
POST /v1/my_wh/namespaces HTTP/1.1
Host: localhost:8080
Content-Type: application/json
Content-Length: 35

{"namespace":["db1"],"properties":{}}
```

响应：

```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 2

{}
```

这里：

- 方法：`POST`
- 路径：`/v1/my_wh/namespaces`
- `my_wh` 来自 `overrides.prefix`
- body 是 JSON
- `Content-Type` 告诉服务端 body 是 JSON
- `Content-Length` 是 body 字节数

---

## 5. URL 结构和 `Poco::URI`

一个 URL：

```text
scheme://host:port/path?query#fragment
```

例子：

```text
http://localhost:8080/v1/config?warehouse=my_wh#top
```

对应：

| 部分 | 值 |
|---|---|
| scheme | `http` |
| host | `localhost` |
| port | `8080` |
| path | `/v1/config` |
| query | `warehouse=my_wh` |
| fragment | `top` |

`Poco::URI` 用法：

```cpp
Poco::URI uri("http://localhost:8080/v1/config?warehouse=my_wh");

uri.getScheme();   // "http"
uri.getHost();     // "localhost"
uri.getPort();     // 8080
uri.getPath();     // "/v1/config"
uri.getQuery();    // "warehouse=my_wh"
uri.getFragment(); // "top" 如果有
```

取查询参数：

```cpp
auto params = uri.getQueryParameters();
for (const auto& p : params) {
    std::cout << p.first << "=" << p.second << std::endl;
}
// warehouse=my_wh
```

所以在你的代码里：

```cpp
auto requested_warehouse = getQueryParameter(uri, "warehouse");
```

本质上就是从：

```text
GET /v1/config?warehouse=my_wh HTTP/1.1
```

里解析出 `warehouse=my_wh`。

---

## 6. HTTP 和 Iceberg REST 路由的关系

代码里的路由：

```cpp
{HTTPRequest::HTTP_GET, {"v1", "{prefix}", "namespaces"}, IcebergRESTOperation::ListNamespaces, true}
```

对应 HTTP 请求：

```http
GET /v1/my_wh/namespaces HTTP/1.1
```

拆解：

- 方法：`GET`
- 路径段：
  - `v1`
  - `my_wh` 对应 `{prefix}`
  - `namespaces`
- 操作：`ListNamespaces`

再比如：

```cpp
{HTTPRequest::HTTP_POST, {"v1", "{prefix}", "namespaces", "{namespace}", "tables"}, IcebergRESTOperation::CreateTable, false}
```

对应：

```http
POST /v1/my_wh/namespaces/db1/tables HTTP/1.1
Content-Type: application/json

{...}
```

- 方法：`POST`
- `{prefix}` = `my_wh`
- `{namespace}` = `db1`
- 操作：`CreateTable`
- 复杂参数放在 JSON body 里

所以 HTTP 路由匹配通常是：

```text
方法 + 路径段
```

查询参数一般不参与路由匹配，比如 `?warehouse=my_wh` 是在 handler 里单独解析的。

---

## 7. 常见坑

1. **空行不能少**  
   头部和 body 之间必须有空行。

2. **`Content-Length` 是字节数**  
   不是字符数。中文、UTF-8 字符占多个字节。

3. **GET 通常不放 body**  
   虽然协议没完全禁止，但语义不明确，很多服务器忽略。

4. **HEAD 响应不能有 body**  
   `HEAD` 和 `GET` 一样，但只返回头部。Iceberg 用它判断资源是否存在。

5. **查询参数要编码**  
   空格写成 `%20`，`&`、`=` 等也要编码。

6. **`Host` 在 HTTP/1.1 必需**  
   没有 `Host`，服务器通常返回 400。

7. **`Accept` 和 `Content-Type` 不同**  
   `Accept` 是“我要什么”，`Content-Type` 是“我给的是什么”。

8. **HTTP 是无状态的**  
   每个请求独立。认证靠 `Authorization`、cookie、token 等。

9. **HTTP/1.1 默认持久连接**  
   一个 TCP 连接可以发多个请求。关闭用 `Connection: close`。

10. **HTTP/2 语义一样，格式不同**  
    HTTP/2 是二进制分帧，有 `:method`、`:path`、`:scheme`、`:authority` 伪头，但方法、状态码、头部语义和 HTTP/1.1 一致。

---

## 8. 示例

用 `curl -v`：

```bash
curl -v "http://localhost:8080/v1/config?warehouse=my_wh"
```

它会打印：

```text
> GET /v1/config?warehouse=my_wh HTTP/1.1
> Host: localhost:8080
> Accept: */*
>
< HTTP/1.1 200 OK
< Content-Type: application/json
< Content-Length: 120
<
{...}
```

`>` 是请求，`<` 是响应。

也可以看：

- Chrome DevTools → Network
- Wireshark
- Postman
- `nc` / `telnet` 手动发请求

---

## 总结

HTTP 格式就是：

```text
请求：方法 路径 版本
      头部
      空行
      body

响应：版本 状态码 原因
      头部
      空行
      body
```

REST API 在此之上约定：

- 用方法表达动作：GET、POST、PUT、DELETE、HEAD
- 用路径表达资源：`/v1/{prefix}/namespaces/{namespace}/tables/{table}`
- 用查询参数表达过滤/选项：`?warehouse=my_wh`
- 用 JSON body 表达复杂数据
- 用状态码表达结果：200、400、404、409、501
- 用头部表达元信息：`Content-Type`、`Accept`、`Authorization`
