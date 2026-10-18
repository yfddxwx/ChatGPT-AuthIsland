# ChatGPT Auth Island

Windows 11 的原生授权批准器：以一个带弹性展开动画的“灵动岛”显示 ChatGPT 宿主送来的权限，逐项展示、不合并、不猜测；用户点 **Allow** 或 **Deny** 后，结果同步返回宿主。本项目不读取账号、Cookie、聊天内容或 API 密钥。

> ChatGPT 没有公开的桌面授权拦截接口。Auth Island 因而提供一个本机桥接协议，供获得宿主授权的 ChatGPT 集成、扩展或自动化工具调用；它不能也不会绕过 ChatGPT 的原生批准流程。

## Features

- Windows 原生 WPF 单文件发布；不需要 Windows App SDK 或 Electron。
- 顶部悬浮、毛玻璃观感、展开/收起动画；窗口可拖动。
- 权限颗粒度完全来自宿主的 `permissions[]`：不聚合、不扩权、不隐去描述。
- 会话完成通知；点击岛屿会在默认浏览器打开对应会话。
- 仅监听 `127.0.0.1`，不会暴露到局域网。

## Install

下载 Release 中的 `ChatGPT.AuthIsland.exe`，双击运行即可。首次运行后，它会在屏幕顶部显示 “Bridge ready”。

从源代码发布：

```powershell
dotnet publish ChatGPT.AuthIsland/ChatGPT.AuthIsland.csproj -c Release
```

产物在 `ChatGPT.AuthIsland/bin/Release/net8.0-windows/win-x64/publish/`。

## Bridge API

所有请求都只发给 `http://127.0.0.1:41373/v1/`。首次启动会生成随机桥接令牌，保存在 `%LOCALAPPDATA%\ChatGPT.AuthIsland\bridge.json`；调用方必须带上 `Authorization: Bearer <token>`。批准请求会阻塞至用户选择后再返回，适合宿主保持原有的授权颗粒度。

```http
POST /v1/approvals
Content-Type: application/json
Authorization: Bearer <token from bridge.json>

{
  "requestId": "req_42",
  "conversationUrl": "https://chatgpt.com/c/example",
  "title": "Run workspace command?",
  "summary": "The host needs your decision.",
  "permissions": [
    { "name": "Read D:\\project", "description": "Inspect source files", "risk": "low" },
    { "name": "Run npm test", "description": "Execute the test command", "risk": "medium" }
  ]
}
```

Response:

```json
{"requestId":"req_42","decision":"allow","permissions":["Read D:\\project","Run npm test"]}
```

当宿主会话结束时：

```http
POST /v1/completions
Content-Type: application/json
Authorization: Bearer <token from bridge.json>

{"conversationUrl":"https://chatgpt.com/c/example","title":"Task completed","summary":"Click to return to the conversation."}
```

## Development

Requires .NET 8 SDK on Windows. There are no third-party runtime dependencies.

```powershell
dotnet build ChatGPT.AuthIsland.sln
dotnet run --project ChatGPT.AuthIsland/ChatGPT.AuthIsland.csproj
```

## Prior art and acknowledgements

- [Windows App SDK](https://github.com/microsoft/WindowsAppSDK) informed the Windows-native notification and activation direction.
- [Toasty](https://github.com/shanselman/toasty) inspired the source-window return workflow; no source code was copied.

## License

[MIT](LICENSE)
