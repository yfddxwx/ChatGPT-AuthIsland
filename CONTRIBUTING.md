# Contributing

Please open an issue before large changes. Keep the bridge protocol backward compatible: a new field may be added, but existing permission fields must not be collapsed or reinterpreted.

Before opening a pull request, run:

```powershell
dotnet build ChatGPT.AuthIsland.sln -c Release
```

Do not add telemetry, network calls, credential collection, or code that tries to scrape a ChatGPT session without explicit user consent.
