ClickHouse 处理HTTP请求使用Poco库。

## 构建与修改 URI

Poco::URI 是 POCO C++ 库中用于解析、构建和操作 URI（统一资源标识符）的核心类。它遵循 RFC 3986 标准，能帮你轻松拆分 URL 的各个部分，或从零开始构建一个完整的 URL。

Poco::URI 最常用的功能就是解析一个 URL 字符串，并提取出你需要的部分。假设我们有这样一个 URL：

http://www.appinf.com:88/sample?example=query#frag

你可以像下面这样提取它的各个部分：

```
#include "Poco/URI.h"
#include <iostream>

int main() {
    Poco::URI uri("http://www.appinf.com:88/sample?example=query#frag");

    std::string scheme = uri.getScheme();       // "http"
    std::string authority = uri.getAuthority(); // "www.appinf.com:88"
    std::string host = uri.getHost();           // "www.appinf.com"
    unsigned short port = uri.getPort();        // 88
    std::string path = uri.getPath();           // "/sample"
    std::string query = uri.getQuery();         // "example=query"
    std::string fragment = uri.getFragment();   // "frag"

    // getPathEtc() 返回路径、查询字符串和片段的组合
    std::string pathEtc = uri.getPathEtc();     // "/sample?example=query#frag"

    return 0;
}
```

注意：Poco::URI 在内部会对除查询字符串（query）和片段（fragment）之外的部分进行百分号解码。而查询字符串和片段则保持原始编码形式，这是为了在后续处理中避免歧义。

也可以从零开始构建一个 URI，或者修改现有 URI 的各个部分。

```
Poco::URI uri;
uri.setScheme("https");
uri.setAuthority("www.appinf.com");
uri.setPath("/another sample");
// 注意：路径中的空格会被自动编码
std::string result = uri.toString(); 
// 结果: "https://www.appinf.com/another%20sample"
```

## 处理查询参数（Query Parameters）
对于查询字符串，Poco::URI 提供了更友好的方式来处理，而无需手动分割字符串。

获取所有查询参数：
getQueryParameters() 方法会返回一个 std::vector<std::pair<std::string, std::string>>，方便遍历所有参数。

```
Poco::URI uri("http://example.com/api?name=John&age=30");
auto params = uri.getQueryParameters();
for (const auto& param : params) {
    std::cout << param.first << " = " << param.second << std::endl;
}
// 输出:
// name = John
// age = 30
```

添加查询参数：
使用 addQueryParameter() 方法可以安全地添加参数，它会自动处理编码问题。
```
Poco::URI uri("http://example.com/api");
uri.addQueryParameter("q", "C++ POCO"); // 自动编码
// uri.toString() -> "http://example.com/api?q=C%2B%2B%20POCO"
```


