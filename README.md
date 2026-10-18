# ChatGPT Auth Island

Windows 原生、零依赖、便携即用的 ChatGPT 桌面版权限人工批准器。以 iPhone 灵动岛为灵感的玻璃浮层，在需要你确认时展开。

## Start

1. 下载或克隆本仓库。
2. 双击 `Start-AuthIsland.cmd`。
3. 保持 ChatGPT Windows 桌面版运行。

无需安装、管理员权限或网络权限。启动器会脱离命令行运行，关闭命令行不会退出；右键托盘图标可退出。

## Behavior

- 只显示 ChatGPT 当前界面中具有明确授权语义的按钮（Allow / Approve / Authorize / Permit 及中文对应词）。
- 每次批准都由用户在浮层中点击；浮层调用的正是宿主当前显示的对应按钮。
- 显示宿主提供的请求上下文，多个请求会保留计数。
- 会话从生成中变为完成时，岛会变为可点击的完成提醒并发送系统托盘提醒；点击岛或托盘图标将 ChatGPT 前置到当前会话。
- 浮层有圆角、透明玻璃层和展开收起动画。

## Safety

- 不注入进程、不修改 ChatGPT、不读写会话内容、不拦截网络、不自动批准。
- 仅使用 Windows UI Automation 读取 ChatGPT 可访问性树；可访问性文案不匹配时不会提供批准入口。
- 通知只能回到 ChatGPT 当前活动会话。Windows UI Automation 不提供可靠的会话 URL，因此不会猜测或切换到其他会话。

## Requirements

Windows 10/11、ChatGPT Windows 桌面版、Windows PowerShell 5.1（系统自带）。

## License

[MIT](LICENSE)
