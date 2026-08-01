# RFC 8628 — OAuth 2.0 设备授权许可（中文翻译）

> **原文**： [RFC 8628 - OAuth 2.0 Device Authorization Grant](https://datatracker.ietf.org/doc/html/rfc8628)
> **状态**：Proposed Standard（建议标准）
> **发布**：2019 年 8 月
> **作者**：W. Denniss (Google), J. Bradley (Ping Identity), M. Jones (Microsoft), H. Tschofenig (ARM Limited)
> **说明**：本文为学习用非官方中文译文，协议语义以英文原文为准。文中 **MUST / SHOULD / MAY** 等关键词按 BCP 14 保留其规范含义。

---

## 摘要

OAuth 2.0 设备授权许可（device authorization grant）面向那些已联网、但要么没有可用于基于用户代理（浏览器）授权的浏览器，要么输入能力受限、难以在授权流程中要求用户输入文本进行认证的设备。它使这类设备上的 OAuth 客户端（如智能电视、媒体主机、电子相框、打印机等）能够借助**另一台设备上的用户代理**，获得用户对访问受保护资源的授权。

## 本备忘录状态

本文是 Internet Standards Track 文档，由 IETF 产出，代表 IETF 社区共识，并经 IESG 批准发布。Internet 标准的更多信息见 RFC 7841 第 2 节。当前状态、勘误与反馈见：[https://www.rfc-editor.org/info/rfc8628](https://www.rfc-editor.org/info/rfc8628)。

## 版权声明

Copyright (c) 2019 IETF Trust and the persons identified as the document authors. All rights reserved.

本文受 BCP 78 及 IETF Trust 法律条款约束。从本文提取的代码组件必须包含 Simplified BSD License 文本（见 Trust Legal Provisions 第 4.e 节），并按该许可证提供且不附带保证。

---



## 目录

1. [引言](#1-引言)
2. [术语](#2-术语)
3. [协议](#3-协议)
  - 3.1 [设备授权请求](#31-设备授权请求)
  - 3.2 [设备授权响应](#32-设备授权响应)
  - 3.3 [用户交互](#33-用户交互)
  - 3.3.1 [非文本验证 URI 优化](#331-非文本验证-uri-优化)
  - 3.4 [设备访问令牌请求](#34-设备访问令牌请求)
  - 3.5 [设备访问令牌响应](#35-设备访问令牌响应)
4. [发现元数据](#4-发现元数据)
5. [安全考虑](#5-安全考虑)
6. [可用性考虑](#6-可用性考虑)
7. [IANA 考虑](#7-iana-考虑)
8. [规范性引用](#8-规范性引用)

---



## 1. 引言

本 OAuth 2.0 [[RFC6749](https://www.rfc-editor.org/info/rfc6749/)] 协议扩展使 OAuth 客户端能够在**输入能力有限或缺少合适浏览器**的设备应用上请求用户授权。这类设备包括智能电视、媒体主机、相框、打印机等——它们缺少传统 OAuth 交互所需的便捷输入方式或合适浏览器。本规范定义的授权流有时也称为 **device flow（设备流）**：引导用户在具备必要输入与浏览器能力的**第二台设备**（如智能手机）上审查授权请求。

设备授权许可**并非**要取代智能手机等能力充足设备上原生应用中基于浏览器的 OAuth；那些应用应遵循 [[RFC8252](https://www.rfc-editor.org/info/rfc8252/)]《OAuth 2.0 for Native Apps》。

使用本授权许可类型的运行前提：

1. 设备已连接到互联网。
2. 设备能够发起出站 HTTPS 请求。
3. 设备能够向用户显示或以其它方式传达 URI 与代码序列。
4. 用户拥有可处理该请求的第二台设备（如个人电脑或智能手机）。

由于设备授权许可**不要求**设备上的 OAuth 客户端与用户代理之间进行双向通信（不同于授权码、隐式许可等其它 OAuth 2 许可类型），它能支持其它方式难以覆盖的若干场景。

设备客户端并不直接与终端用户的用户代理（浏览器）交互，而是指示终端用户使用另一台计算机或设备连接到授权服务器以批准访问请求。由于协议支持无法接收入站请求的客户端，客户端会**反复轮询**授权服务器，直到终端用户完成批准。

设备客户端通常自行选择要支持的授权服务器集合（例如自有授权服务器，或与之有合作关系的提供方）。常见情况是只支持一个授权服务器——例如某媒体提供方的电视应用只支持该提供方的授权服务器。用户与该授权提供方之间可能尚无既有关系，但可在授权流中建立。

```
   +----------+                                +----------------+
   |          |>---(A)-- Client Identifier --->|                |
   |          |                                |                |
   |          |<---(B)-- Device Code,      ---<|                |
   |          |          User Code,            |                |
   |  Device  |          & Verification URI    |                |
   |  Client  |                                |                |
   |          |  [polling]                     |                |
   |          |>---(E)-- Device Code       --->|                |
   |          |          & Client Identifier   |                |
   |          |                                |  Authorization |
   |          |<---(F)-- Access Token      ---<|     Server     |
   +----------+   (& Optional Refresh Token)   |                |
         v                                     |                |
         :                                     |                |
        (C) User Code & Verification URI       |                |
         :                                     |                |
         v                                     |                |
   +----------+                                |                |
   | End User |                                |                |
   |    at    |<---(D)-- End user reviews  --->|                |
   |  Browser |          authorization request |                |
   +----------+                                +----------------+

                 图 1：设备授权流程（Device Authorization Flow）
```

图 1 中的步骤：

- **(A)** 客户端向授权服务器请求访问，请求中包含其客户端标识符。
- **(B)** 授权服务器签发设备码（device code）与终端用户码（end-user code），并提供终端用户验证 URI。
- **(C)** 客户端指示终端用户在另一台设备上的用户代理中访问该验证 URI，并提供用户码以便审查授权请求。
- **(D)** 授权服务器通过用户代理认证终端用户，提示用户输入设备客户端提供的用户码；验证用户码后，提示用户接受或拒绝请求。
- **(E)** 在用户审查请求（步骤 D）期间，客户端反复轮询授权服务器以获知用户是否完成授权；请求中包含设备码及其客户端标识符。
- **(F)** 授权服务器验证客户端提供的设备码：若授予访问则返回访问令牌；若拒绝则返回错误；若尚未完成则指示客户端继续轮询。

---



## 2. 术语

本文中的关键词 **MUST**、**MUST NOT**、**REQUIRED**、**SHALL**、**SHALL NOT**、**SHOULD**、**SHOULD NOT**、**RECOMMENDED**、**NOT RECOMMENDED**、**MAY**、**OPTIONAL** 须按 [BCP 14](https://www.rfc-editor.org/bcp/bcp14) [[RFC2119](https://www.rfc-editor.org/info/rfc2119/)] [[RFC8174](https://www.rfc-editor.org/info/rfc8174/)] 解释，且仅当它们以全大写形式出现时适用。

中文习惯对应（仅供阅读，不改变规范强度）：


| 英文                           | 含义概要    |
| ---------------------------- | ------- |
| MUST / REQUIRED / SHALL      | 必须      |
| MUST NOT / SHALL NOT         | 不得      |
| SHOULD / RECOMMENDED         | 应当      |
| SHOULD NOT / NOT RECOMMENDED | 不应当     |
| MAY / OPTIONAL               | 可以 / 可选 |


---



## 3. 协议



### 3.1. 设备授权请求

本规范定义了一个新的 OAuth 端点：**设备授权端点（device authorization endpoint）**。它与 [[RFC6749](https://www.rfc-editor.org/info/rfc6749/)] 中用户通过用户代理（浏览器）交互的授权端点不同。使用设备授权端点时，设备上的 OAuth 客户端**直接**与授权服务器交互，不在用户代理中呈现请求；终端用户在**另一台设备**上完成授权。交互定义如下。

客户端通过向设备授权端点发起 HTTP `POST` 请求，向授权服务器申请一组验证码，从而启动授权流。

客户端在设备授权请求中，按 [[RFC6749] 附录 B](https://www.rfc-editor.org/info/rfc6749/#appendix-B)，以 `application/x-www-form-urlencoded` 格式、UTF-8 字符编码，在 HTTP 请求实体正文中包含下列参数：

`client_id`
若客户端未按 [[RFC6749] 第 3.2.1 节](https://www.rfc-editor.org/info/rfc6749/#section-3.2.1)向授权服务器进行认证，则**REQUIRED**。客户端标识符，见 [[RFC6749] 第 2.2 节](https://www.rfc-editor.org/info/rfc6749/#section-2.2)。

`scope`
**OPTIONAL**。访问请求的范围，见 [[RFC6749] 第 3.3 节](https://www.rfc-editor.org/info/rfc6749/#section-3.3)。

示例 HTTPS 请求：

```http
POST /device_authorization HTTP/1.1
Host: server.example.com
Content-Type: application/x-www-form-urlencoded

client_id=1406020730&scope=example_scope
```

设备发出的所有请求 **MUST** 使用 TLS [[RFC8446](https://www.rfc-editor.org/info/rfc8446/)]，并实现 [BCP 195 [RFC7525]](https://www.rfc-editor.org/bcp/bcp195) 的最佳实践。

未带值的参数 **MUST** 视为未发送。授权服务器 **MUST** 忽略无法识别的请求参数。请求与响应参数 **MUST NOT** 重复出现。

[[RFC6749] 第 3.2.1 节](https://www.rfc-editor.org/info/rfc6749/#section-3.2.1)的客户端认证要求适用于本端点：机密客户端（已建立客户端凭证）以与令牌端点相同的方式认证；公共客户端通过 `client_id` 标识自身。

由于本协议具有轮询特性（见第 3.4 节），需注意避免压垮令牌端点。为减少对令牌端点的无效请求，客户端 **SHOULD** 仅在用户提示时启动设备授权请求，而**不要**在应用启动、或先前授权会话过期/失败时自动发起。

### 3.2. 设备授权响应

成功时，授权服务器生成在有限时间内有效的唯一设备验证码与终端用户码，并以 `application/json` [[RFC8259](https://www.rfc-editor.org/info/rfc8259/)] 格式、HTTP 200 (OK) 状态码放入响应正文。响应包含下列参数：

`device_code`（REQUIRED）
设备验证码。

`user_code`（REQUIRED）
终端用户验证码。

`verification_uri`（REQUIRED）
授权服务器上的终端用户验证 URI。URI 应简短、易记，因为终端用户需要手动输入到用户代理中。

`verification_uri_complete`（OPTIONAL）
已包含 `user_code`（或具有同等功能的其它信息）的验证 URI，面向非文本传输场景设计。

`expires_in`（REQUIRED）
`device_code` 与 `user_code` 的生命周期（秒）。

`interval`（OPTIONAL）
客户端在向令牌端点发起轮询请求之间 **SHOULD** 等待的最短秒数。若未提供，客户端 **MUST** 使用默认值 **5**。

示例：

```http
HTTP/1.1 200 OK
Content-Type: application/json
Cache-Control: no-store

{
  "device_code": "GmRhmhcxhwAzkoEqiMEg_DnyEysNkuNhszIySk9eS",
  "user_code": "WDJB-MJHT",
  "verification_uri": "https://example.com/device",
  "verification_uri_complete":
      "https://example.com/device?user_code=WDJB-MJHT",
  "expires_in": 1800,
  "interval": 5
}
```

出错时（例如客户端配置无效），授权服务器按 [RFC6749] 第 5.2 节令牌端点的方式响应。

### 3.3. 用户交互

收到成功的授权响应后，客户端向终端用户显示或以其它方式传达 `user_code` 与 `verification_uri`，并指示其在第二台设备上的用户代理中访问该 URI（例如手机浏览器）并输入用户码。

```
           +-----------------------------------------------+
           |                                               |
           |  Using a browser on another device, visit:    |
           |  https://example.com/device                   |
           |                                               |
           |  And enter the code:                          |
           |  WDJB-MJHT                                    |
           |                                               |
           +-----------------------------------------------+

                     图 2：用户指引示例
```

授权用户导航到 `verification_uri`，并在受 TLS 保护的会话中向授权服务器认证 [[RFC8446](https://www.rfc-editor.org/info/rfc8446/)]。授权服务器提示终端用户输入客户端提供的 `user_code` 以标识设备授权会话，随后应告知用户其正在执行的操作，并请其批准或拒绝请求。用户交互完成后，服务器指示用户返回其设备。

在用户交互期间，设备持续使用 `device_code` 轮询令牌端点（见第 3.4 节），直到用户完成交互、代码过期或发生其它错误。`device_code` **不面向**终端用户直接使用，因此交互过程中不应显示，以免造成困惑。

支持本规范的授权服务器 **MUST** 实现以用户导航到 `verification_uri` 开始、并在交互某阶段提供 `user_code` 的用户交互序列。除此之外，具体顺序与实现由授权服务器决定——例如可在授权流中允许新用户注册，或增加额外安全验证步骤。

**NOT RECOMMENDED**：授权服务器在 `verification_uri` 中包含 `user_code`，这会增加用户必须输入的 URI 长度与复杂度。虽然用户仍需输入类似数量的字符，但在成功导航到 `verification_uri` 后，服务器可高亮输入错误以改善体验。下一节描述的 `verification_uri_complete` 交互则设计为同时携带这两部分信息。

#### 3.3.1. 非文本验证 URI 优化

当授权响应（第 3.2 节）包含 `verification_uri_complete` 时，客户端 **MAY** 以非文本方式呈现该 URI（任何能打开浏览器并访问该 URI 的方法，如 QR 码或 NFC），以免用户手动输入 URI。

出于可用性考虑，**RECOMMENDED** 客户端仍显示文本形式的 `verification_uri`，以便无法使用快捷方式的用户。客户端 **MUST** 仍显示 `user_code`，因为授权服务器会要求用户确认该码以区分设备，或作为远程钓鱼缓解手段（见第 5.4 节）。

若用户通过导航到 `verification_uri_complete` 开始交互，则仍遵循第 3.3 节的流程，只是无需输入 `user_code`。服务器 **SHOULD** 向用户显示 `user_code`，并请其确认与设备上显示的码一致，以确认正在授权正确的设备。与之前一样，除确认设备身份外，用户还应可以选择批准或拒绝授权请求。

```
           +-------------------------------------------------+
           |                                                 |
           |  Scan the QR code or, using     +------------+  |
           |  a browser on another device,   |[_]..  . [_]|  |
           |  visit:                         | .  ..   . .|  |
           |  https://example.com/device     | . .  . ....|  |
           |                                 |.   . . .   |  |
           |  And enter the code:            |[_]. ... .  |  |
           |  WDJB-MJHT                      +------------+  |
           |                                                 |
           +-------------------------------------------------+

     图 3：带完整验证 URI 的 QR 码表示的用户指引示例
```



### 3.4. 设备访问令牌请求

向用户展示指引后，客户端创建访问令牌请求，发送到 [[RFC6749] 第 3.2 节](https://www.rfc-editor.org/info/rfc6749/#section-3.2)定义的令牌端点，且 `grant_type` 为：

```text
urn:ietf:params:oauth:grant-type:device_code
```

这是本规范创建的扩展许可类型（见 [[RFC6749] 第 4.5 节](https://www.rfc-editor.org/info/rfc6749/#section-4.5)），参数如下：

`grant_type`（REQUIRED）
值 **MUST** 为 `urn:ietf:params:oauth:grant-type:device_code`。

`device_code`（REQUIRED）
设备验证码，即第 3.2 节设备授权响应中的 `device_code`。

`client_id`
若客户端未按 [[RFC6749] 第 3.2.1 节](https://www.rfc-editor.org/info/rfc6749/#section-3.2.1)认证，则 **REQUIRED**。客户端标识符，见 [[RFC6749] 第 2.2 节](https://www.rfc-editor.org/info/rfc6749/#section-2.2)。

示例 HTTPS 请求（换行仅便于显示）：

```http
POST /token HTTP/1.1
Host: server.example.com
Content-Type: application/x-www-form-urlencoded

grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code
&device_code=GmRhmhcxhwAzkoEqiMEg_DnyEysNkuNhszIySk9eS
&client_id=1406020730
```

若客户端已签发客户端凭证（或被分配其它认证要求），则客户端 **MUST** 按 [[RFC6749] 第 3.2.1 节](https://www.rfc-editor.org/info/rfc6749/#section-3.2.1)向授权服务器认证。注意静态分发的客户端凭证存在安全影响，见第 5.6 节。

对该请求的响应见第 3.5 节。与其它 OAuth 许可类型不同，预期客户端会根据响应中的错误码**反复**尝试访问令牌请求（轮询）。

### 3.5. 设备访问令牌响应

若用户已批准许可，令牌端点按 [[RFC6749] 第 5.1 节](https://www.rfc-editor.org/info/rfc6749/#section-5.1)返回成功响应；否则按 [[RFC6749] 第 5.2 节](https://www.rfc-editor.org/info/rfc6749/#section-5.2)返回错误。

除 [[RFC6749] 第 5.2 节](https://www.rfc-editor.org/info/rfc6749/#section-5.2)定义的错误码外，设备授权许可在令牌端点响应中还规定下列错误码：

`authorization_pending`
授权请求仍在等待，因终端用户尚未完成用户交互步骤（第 3.3 节）。客户端 **SHOULD** 重复向令牌端点发起访问令牌请求（即轮询）。每次新请求之前，客户端 **MUST** 至少等待设备授权响应中 `interval` 参数指定的秒数（见第 3.2 节；若未提供则为 5 秒），并遵守 `slow_down` 错误要求的轮询间隔增大。

`slow_down`
`authorization_pending` 的变体：授权仍在等待、应继续轮询，但本请求及后续所有请求的间隔 **MUST** 增加 **5 秒**。

`access_denied`
授权请求被拒绝。

`expired_token`
`device_code` 已过期，设备授权会话已结束。客户端 **MAY** 开始新的设备授权请求，但 **SHOULD** 等待用户交互后再重启，以避免不必要的轮询。

`authorization_pending` 与 `slow_down` 的行为较为特殊：它们指示 OAuth 客户端应继续轮询令牌端点（按上文精确定义的行为重复令牌请求）。若客户端收到**任何其它**错误码，则 **MUST** 停止轮询，并 **SHOULD** 作出相应反应（例如向用户显示错误）。

遇到连接超时时，客户端 **MUST** 在重试前单方面降低轮询频率。**RECOMMENDED** 使用指数退避（例如每次连接超时将轮询间隔加倍）。

本规范的假设是：用户进行授权的那台独立设备**无法**回传到带有 OAuth 客户端的设备。协议只要求单向通道，以尽量提高在受限环境中的可用性（例如只能发起出站请求的电视应用）。若所选用户交互接口存在回传通道，则设备 **MAY** 在收到用户已完成操作的通知后再发起令牌请求（作为轮询的替代）。但此类行为超出本规范范围。

---



## 4. 发现元数据

对本协议的支持在 OAuth 2.0 Authorization Server Metadata [RFC8414] 中声明如下：将值 `urn:ietf:params:oauth:grant-type:device_code` 包含在 `grant_types_supported` 中，并增加下列键值对：

`device_authorization_endpoint`（OPTIONAL）
授权服务器设备授权端点的 URL，定义见第 3.1 节。

---



## 5. 安全考虑



### 5.1. 用户码暴力破解

由于用户码由用户输入，出于可用性会倾向于较短的码，其熵通常低于设备码或其它不影响可用性的 OAuth bearer token。因此建议服务器对用户码尝试进行**限速**。

用户码 **SHOULD** 具有足够熵，并结合限速及其它缓解措施，使暴力破解变得不可行。例如，一般认为 128 位对称加密密钥在今天足够好，因为攻击者需付出 2^{96} 量级工作量才有 2^{-32} 的随机猜中概率。限速与用户码的有限生命周期人为限制了攻击者可“做”的工作量。例如，若使用 8 字符、基数 20 的用户码（约 34.5 比特熵），限速间隔与有效期只需允许约 5 次尝试，即可达到相同的 2^{-32} 随机猜中概率。

成功暴力破解用户码会使攻击者用**自己的**凭证批准授权许可，随后设备会收到关联到攻击者账户的设备授权许可。这与 OAuth bearer token 被暴力破解后攻击者获得受害者授权许可的情形相反。此类攻击并不总是有经济意义——例如视频应用中，设备所有者可能反而用攻击者账户购片（但即便如此仍存在隐私风险，仍需防护）。此外，某些设备流用法会让授权账户获得需要保护的能力（如控制设备）。

用户码的精确长度与所含熵由授权服务器裁量，需综合考虑受保护资源的敏感度、码长在可用性上的可行性，以及已有的缓解措施（如限速）。

### 5.2. 设备码暴力破解

猜中设备码的攻击者有可能在用户完成流程后获得授权。由于设备码不向用户显示，长度没有可用性顾虑，因此 **SHOULD** 使用熵非常高的码。

### 5.3. 设备可信性

与其它原生应用 OAuth 2.0 流不同，请求授权的设备与用户授予访问的设备不是同一台。因此，来自批准用户会话与设备的信号，并不总能用于判断客户端设备的可信度。

注意：若与本流一起使用的授权服务器是恶意的，它可能对其它授权服务器的回信道流发起中间人攻击。该场景下中间人并非完全隐蔽——终端用户最终会落在错误服务的授权页上，从而有机会注意到浏览器地址栏 URL 不对。要实现这一点，设备制造商要么本身是攻击者并出货恶意设备，要么使用了被攻击者控制的授权服务器（可能因设备所用授权服务器被攻破）。一定程度上，购买者是在依赖制造商及其商业伙伴的可信度。

### 5.4. 远程钓鱼

攻击者可能在其控制的设备上启动设备流，例如发送邮件指示目标用户访问验证 URL 并输入用户码。为缓解此类攻击，**RECOMMENDED** 在用户交互步骤（第 3.3 节）中告知用户其正在授权一台设备，并确认设备在其掌控中。授权服务器 **SHOULD** 显示有关设备的信息，以便用户发现软件客户端是否在冒充硬件设备。

对于支持第 3.3.1 节 `verification_uri_complete` 优化的授权服务器，确认设备在用户掌控中尤为重要，因为用户不再需要手动输入设备上显示的码。一种建议是在授权流中显示该码，并请用户核实设备上当前显示的是同一码。

用户码寿命需足够长以便可用（允许用户取出第二台设备、导航到验证 URI、登录等），又应足够短以限制用于钓鱼的码的可用性。这并不能阻止钓鱼者（尤其是实时交互时）出示新鲜令牌，但会限制通过邮件或短信发送码的可行性。

### 5.5. 会话窥探

在设备等待授权期间，恶意用户可能通过物理窥探设备 UI（例如观看显示屏幕）并比发起者更快完成授权，从而劫持会话。设备在考虑如何向用户传达代码时，**SHOULD** 考虑运行环境，以降低被恶意用户观察到的机会。

### 5.6. 非机密客户端

设备客户端通常无法保持其凭证的机密性——持有设备的用户可以逆向工程并提取凭证。因此，除非采取额外措施，否则应将其视为公共客户端（[RFC6749] 第 2.1 节），易被冒充。[RFC6819] 第 5.3.1 节以及 [RFC8252] 第 8.5、8.6 节的安全考虑适用于此类客户端。

用户还可能获取颁发给其客户端的 `device_code` 和/或其它 OAuth bearer token，从而通过冒充客户端直接使用自己的授权许可。鉴于已持有客户端凭证的用户本就可以冒充客户端并创建新的授权许可（新的 `device_code`），这并不构成单独的冒充向量。

### 5.7. 非视觉码传输

并不要求设备以视觉方式显示用户码。也可使用其它单向通信方式，如 TTS 语音或 Bluetooth Low Energy。为缓解恶意用户在其不控制的设备上启动凭证绑定的攻击，**RECOMMENDED** 所选通信信道仅对近距离人员可访问，例如能看见或听见该设备的人。

---



## 6. 可用性考虑

本节为非规范性讨论。

### 6.1. 用户码建议

对许多用户而言，最近的联网设备是手机；这些设备的输入方式在切换大小写或输入数字时通常比电脑键盘更耗时。选择用户码字符集时应考虑这些限制，以提升可用性（加快输入、减少重试）。

一种提升输入速度的方式是将字符集限制为**不区分大小写的 A–Z 字母、不含数字**。这些字符通常无需修饰键即可在手机键盘上输入。进一步去掉元音以避免随机组成单词，得到基数 20 字符集：`BCDFGHJKLMNPQRSTVWXZ`。可加入短横线或其它标点以提高可读性。

遵循该指南的示例用户码 `WDJB-MJHT` 含 8 个有效字符，并加短横线以提高可读性，熵为 20^8。

纯数字码在可用性上也是好选择，尤其是面向不使用 A–Z 键盘的地区；但为保持高熵，长度需要更长。

含 9 位有效数字、加短横线以提高可读性、熵为 10^9 的示例：`019-450-730`。

处理输入的用户码时，服务器应剥离其为可读性而加入的短横线及其它标点（使用户可选是否包含这些标点）。对仅使用 A–Z 范围字符的码（如上基数 20 字符集），比较前应将用户输入转为大写，以应对用户输入等价小写字符的情况。进一步剥离所选字符集之外的所有字符也值得推荐，以减少因误输入（如空格）使本有效输入失效的情况。

**RECOMMENDED** 避免包含两个或多个易混淆字符的字符集，如 `0` 与 `O`，或 `1`、`l` 与 `I`。此外，在可行范围内，当字符集中某字符可能与集外字符混淆时，**MAY** 将集外字符替换为集内常被混淆的那个字符——例如在使用 0–9 数字字符集时，可将 `O` 替换为 `0`。

### 6.2. 非浏览器用户交互

设备与授权服务器 **MAY** 在第 3.3 节所述方式之外，协商替代的码传输与用户交互方法。例如通过蓝牙将码传到授权服务器配套应用，从而无需浏览器与手动输入。此类交互仍可利用本协议——最终用户只需向授权服务器标识授权会话；但通过验证 URI 以外的用户交互超出本规范范围。

---



## 7. IANA 考虑



### 7.1. OAuth 参数注册

在 IANA “OAuth Parameters” 注册表 [IANA.OAuth.Parameters]（由 [RFC6749] 建立）中注册：


| 字段                       | 值                |
| ------------------------ | ---------------- |
| Name                     | `device_code`    |
| Parameter Usage Location | token request    |
| Change Controller        | IESG             |
| Reference                | RFC 8628 第 3.4 节 |




### 7.2. OAuth URI 注册

在 IANA “OAuth URI” 注册表中注册：


| 字段                     | 值                                              |
| ---------------------- | ---------------------------------------------- |
| URN                    | `urn:ietf:params:oauth:grant-type:device_code` |
| Common Name            | Device Authorization Grant Type for OAuth 2.0  |
| Change Controller      | IESG                                           |
| Specification Document | RFC 8628 第 3.4 节                               |




### 7.3. OAuth 扩展错误注册

在 IANA “OAuth Extensions Error Registry” 中注册：


| Name                    | Usage Location          | Protocol Extension | Change Controller | Reference |
| ----------------------- | ----------------------- | ------------------ | ----------------- | --------- |
| `authorization_pending` | Token endpoint response | RFC 8628           | IETF              | 第 3.5 节   |
| `access_denied`         | Token endpoint response | RFC 8628           | IETF              | 第 3.5 节   |
| `slow_down`             | Token endpoint response | RFC 8628           | IETF              | 第 3.5 节   |
| `expired_token`         | Token endpoint response | RFC 8628           | IETF              | 第 3.5 节   |




### 7.4. OAuth 授权服务器元数据

在 IANA “OAuth Authorization Server Metadata” 注册表（由 [RFC8414] 建立）中注册：


| 字段                   | 值                                                               |
| -------------------- | --------------------------------------------------------------- |
| Metadata name        | `device_authorization_endpoint`                                 |
| Metadata Description | URL of the authorization server's device authorization endpoint |
| Change Controller    | IESG                                                            |
| Reference            | RFC 8628 第 4 节                                                  |


---



## 8. 规范性引用


| 引用                      | 说明                                                                                                                             |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| [IANA.OAuth.Parameters] | IANA, “OAuth Parameters”, [http://www.iana.org/assignments/oauth-parameters](http://www.iana.org/assignments/oauth-parameters) |
| [RFC2119]               | Bradner, S., “Key words for use in RFCs to Indicate Requirement Levels”, BCP 14, RFC 2119, March 1997                          |
| [RFC6749]               | Hardt, D., Ed., “The OAuth 2.0 Authorization Framework”, RFC 6749, October 2012                                                |
| [RFC6755]               | Campbell, B. and H. Tschofenig, “An IETF URN Sub-Namespace for OAuth”, RFC 6755, October 2012                                  |
| [RFC6819]               | Lodderstedt, T., Ed., McGloin, M., and P. Hunt, “OAuth 2.0 Threat Model and Security Considerations”, RFC 6819, January 2013   |
| [RFC7525]               | Sheffer, Y., Holz, R., and P. Saint-Andre, “Recommendations for Secure Use of TLS and DTLS”, BCP 195, RFC 7525, May 2015       |
| [RFC8174]               | Leiba, B., “Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words”, BCP 14, RFC 8174, May 2017                             |
| [RFC8252]               | Denniss, W. and J. Bradley, “OAuth 2.0 for Native Apps”, BCP 212, RFC 8252, October 2017                                       |
| [RFC8259]               | Bray, T., Ed., “The JavaScript Object Notation (JSON) Data Interchange Format”, STD 90, RFC 8259, December 2017                |
| [RFC8414]               | Jones, M., Sakimura, N., and J. Bradley, “OAuth 2.0 Authorization Server Metadata”, RFC 8414, June 2018                        |
| [RFC8446]               | Rescorla, E., “The Transport Layer Security (TLS) Protocol Version 1.3”, RFC 8446, August 2018                                 |


---



## 致谢（节选）

本文起点是 Internet-Draft `draft-recordon-oauth-v2-device`（David Recordon、Brent Goldman），其内容又来自早期 OAuth 2.0 草案中因部署经验不足而在正式发布前移除的部分。感谢为早期草案做出贡献的 OAuth Working Group 成员。

本文在 Rifaat Shekh-Yusef 与 Hannes Tschofenig 主持的 OAuth Working Group 中完成；Security Area Directors 为 Benjamin Kaduk、Kathleen Moriarty、Eric Rescorla。

对最终规范提供想法、反馈与措辞贡献的个人包括（不完全列表）：Ben Campbell、Brian Campbell、Roshni Chandrashekhar、Alissa Cooper、Eric Fazendin、Benjamin Kaduk、Jamshid Khosravian、Mirja Kuehlewind、Torsten Lodderstedt、James Manger、Dan McNulty、Breno de Medeiros、Alexey Melnikov、Simon Moffatt、Stein Myrseth、Emond Papegaaij、Justin Richer、Adam Roach、Nat Sakimura、Andrew Sciberras、Marius Scurtescu、Filip Skokan、Robert Sparks、Ken Wang、Christopher Wood、Steven E. Wright、Qin Wu 等。

---



## 作者地址

- **William Denniss** — Google — [wdenniss@google.com](mailto:wdenniss@google.com) — [https://wdenniss.com/deviceflow](https://wdenniss.com/deviceflow)
- **John Bradley** — Ping Identity — [ve7jtb@ve7jtb.com](mailto:ve7jtb@ve7jtb.com) — [http://www.thread-safe.com/](http://www.thread-safe.com/)
- **Michael B. Jones** — Microsoft — [mbj@microsoft.com](mailto:mbj@microsoft.com) — [http://self-issued.info/](http://self-issued.info/)
- **Hannes Tschofenig** — ARM Limited, Austria — [Hannes.Tschofenig@gmx.net](mailto:Hannes.Tschofenig@gmx.net) — [http://www.tschofenig.priv.at](http://www.tschofenig.priv.at)

---



## 与 ClickHouse Client 的对应关系（阅读笔记）

`clickhouse-client --login` 使用的正是本 RFC 的设备授权流：

1. `POST` 设备授权端点 → 拿到 `device_code` / `user_code` / `verification_uri`（及可选 `verification_uri_complete`）。
2. 向用户展示验证 URI 与用户码（可打开浏览器 / 打印 QR）。
3. 以 `grant_type=urn:ietf:params:oauth:grant-type:device_code` 轮询令牌端点，处理 `authorization_pending` / `slow_down` / 成功令牌 / 其它错误。
4. 请求体 `Content-Type` 为 `application/x-www-form-urlencoded`（第 3.1、3.4 节规定）。
5. 发现阶段可从 OIDC/OAuth 元数据读取 `device_authorization_endpoint`，并确认 `grant_types_supported` 包含本 grant type（第 4 节）。

实现参考：`src/Client/JWTProvider.cpp`、`src/Client/OAuthDeviceFlow.*`。