# ChatGPT Auth Island

ChatGPT 网页版的玻璃灵动岛授权器。直接读取 ChatGPT 页面自身的权限对话框与生成状态，不依赖不稳定的桌面 UI Automation。

## Install

1. 下载仓库并解压。
2. 在 Chrome 或 Edge 打开 `chrome://extensions`。
3. 开启「开发者模式」，点击「加载已解压的扩展程序」，选择本仓库目录。
4. 打开或刷新 [chatgpt.com](https://chatgpt.com)。

## Behavior

- 顶部居中毛玻璃岛，具有入场、呼吸、展开和完成提示动画。
- 只在 ChatGPT 的权限对话框中显示宿主提供的实际操作按钮；点击岛内按钮等同于点击该宿主按钮，绝不自动批准。
- 生成结束时，岛会变为绿色可点击提醒，同时发出浏览器通知。
- 点击任一完成提醒会回到触发它的精确会话 URL。
- 不收集、传输或存储聊天内容。

## Requirements

Chrome 或 Microsoft Edge，ChatGPT 网页版。桌面原生客户端没有稳定公开的权限/会话 API，无法在不注入进程的前提下可靠实现这一功能。

## License

[MIT](LICENSE)
