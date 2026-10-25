# 一次 GitHub 连不上的逐层定位（可复用的排查顺序）

> 症状：`git push` 走 HTTPS 报认证失败，`winget install` 报 `InternetOpenUrl() failed. 0x80072ee5`，
> 但同一台机器 `ssh -T git@github.com` 却一切正常。下面是从"以为是工具坏了"到"找到阻断层"的全过程。

## 0. 先分清"哪一层断了"

顺序必须是 **DNS → TCP → TLS → HTTP → 应用**。跳层会一路错判。

```powershell
Test-NetConnection github.com -Port 443 -InformationLevel Quiet
Test-NetConnection github.com -Port 22  -InformationLevel Quiet
```

本机结果：**443 = True，22 = True**。TCP 全通 —— 所以"网络不通"这个结论是错的。

## 1. 用 `exit code` 判，不要用 `-w`

```powershell
curl.exe -s -o NUL --max-time 20 https://example.com   # exit=0   对照组通
curl.exe -s -o NUL --max-time 20 https://github.com    # exit=56  CURLE_RECV_ERROR
```

`exit=56` = 请求发出去了，**接收阶段被掐断**。TCP 通 + TLS/接收断 = 典型的 SNI 阻断。

### 一个把我带偏的坑

我一开始用 `-w '%{http_code}'` 判断连通性，拿到 `000` + `exit=43`（CURLE_BAD_FUNCTION_ARGUMENT），
连 `curl -w '%{http_code}' --version` 都报 43 —— **没有实际传输时这个变量本身就会让 curl 退 43**。

> **教训：判连通性只看 `exit code`。`-w` 是给人看的报告，不是判据。**

## 2. 找到通路再谈修工具

```powershell
curl.exe --socks5-hostname 127.0.0.1:1080 -L -o out.zip https://github.com/...
# exit=0
```

本机结论：**443 必须走 socks 代理；22 端口直连可用。**

于是两条路分叉：

| 目标 | 走哪条 |
|---|---|
| `git push`（推代码） | **SSH over 22**，不需要代理 |
| 下载 release / 调 REST API | **HTTPS + socks 代理** |

## 3. `winget` / `HttpClient` 为什么单独失效

| 工具 | 失败原因 |
|---|---|
| `winget` | WinINet **不认 `socks5h://`** 这个 scheme，拿着它去直连 443 → 被断 → `0x80072ee5` |
| `.NET HttpClient` | 默认不走 socks，直连 443 → 超时 |

**所以这不是 winget 的 bug，是代理配置格式与工具能力不匹配。** 用 `curl --socks5-hostname` 绕过去即可。

## 4. 代理配置的三处别写错

```
git  → http.proxy = socks5h://127.0.0.1:1080     # git 认 socks5h
curl → --socks5-hostname 127.0.0.1:1080          # 不要在 URL 里写 socks5h
Go(gh) → HTTPS_PROXY=socks5://127.0.0.1:1080     # Go 只认 socks5:，不认 socks5h
```

`socks5` 与 `socks5h` 的区别是**谁做 DNS 解析**：`h` 表示由代理解析域名（对 SNI 阻断更有效），
但并非每个工具都认这个后缀。**写错后缀的表现不是"报错"，而是"直连"** —— 这一点最坑。

## 5. 最终可用形态（本机）

```powershell
# 推代码：直连 SSH，不需要任何代理
git push origin main

# 下载：走 socks
curl.exe --socks5-hostname 127.0.0.1:1080 -L -o x.zip https://github.com/...

# gh CLI：注入 Go 风格代理变量
$env:HTTPS_PROXY='socks5://127.0.0.1:1080'
gh api user --jq .login
```

## 一句话总结

**"工具坏了"和"通路断了"在症状上长得一样，但修法完全不同。**
先用 `exit code` 把层切开，再决定修工具还是换通路。
