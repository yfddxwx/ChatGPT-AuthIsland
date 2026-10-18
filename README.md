# ChatGPT Auth Island

Windows 原生、零第三方依赖的 ChatGPT 权限人工批准器。界面模拟 iPhone 灵动岛的深色玻璃浮层，权限颗粒度跟随 ChatGPT 桌面宿主当前可见的权限按钮。

## 使用

1. 双击 `Start-AuthIsland.cmd`。
2. 保持 ChatGPT 桌面版运行。
3. 出现权限请求时，在浮层中点击“批准”或“忽略”。
4. 会话从“生成中”变为完成时，系统托盘会提醒；双击托盘图标回到 ChatGPT。

## 安全边界

- 不注入进程、不修改 ChatGPT 文件、不拦截网络、不自动批准。
- 只通过 Windows UI Automation 读取 ChatGPT 宿主窗口，并在用户明确点击“批准”后调用当前权限按钮。
- 依赖 ChatGPT 桌面版的可访问性文本；按钮文案变化时不会批准，需手动处理。
- 需要 Windows PowerShell 5.1（Windows 自带）。

## 开源

MIT License。
