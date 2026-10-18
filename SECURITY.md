# Security policy

Report vulnerabilities privately to the repository owner through GitHub's private vulnerability-reporting flow. Do not file public issues for vulnerabilities that could cause unintended approvals or expose bridge tokens.

The local bridge only binds to `127.0.0.1` and requires a per-launch bearer token. Treat `%LOCALAPPDATA%\ChatGPT.AuthIsland\bridge.json` as a local secret: do not commit or share it.
