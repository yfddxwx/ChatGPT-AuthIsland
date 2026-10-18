using System.Windows;

namespace ChatGPT.AuthIsland;

public partial class App : Application
{
    private ApprovalBridge? _bridge;
    private IslandWindow? _island;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
        _island = new IslandWindow();
        _bridge = new ApprovalBridge(_island);
        await _bridge.StartAsync();
        _island.SetBridgeAddress(_bridge.Address);
        _island.ShowIdle();
    }

    protected override async void OnExit(ExitEventArgs e)
    {
        if (_bridge is not null) await _bridge.DisposeAsync();
        base.OnExit(e);
    }
}
