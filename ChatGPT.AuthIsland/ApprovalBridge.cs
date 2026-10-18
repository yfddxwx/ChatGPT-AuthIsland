using System.Net;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Windows;

namespace ChatGPT.AuthIsland;

public sealed class ApprovalBridge : IAsyncDisposable
{
    private readonly HttpListener _listener = new();
    private readonly IslandWindow _island;
    private readonly CancellationTokenSource _stop = new();
    private Task? _loop;
    private readonly string _token = Convert.ToHexString(RandomNumberGenerator.GetBytes(24));

    public string Address { get; } = "http://127.0.0.1:41373/v1/";

    public ApprovalBridge(IslandWindow island) => _island = island;

    public Task StartAsync()
    {
        _listener.Prefixes.Add(Address);
        _listener.Start();
        var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ChatGPT.AuthIsland");
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "bridge.json"), JsonSerializer.Serialize(new { address = Address, token = _token }));
        _loop = Task.Run(ListenAsync);
        return Task.CompletedTask;
    }

    private async Task ListenAsync()
    {
        while (!_stop.IsCancellationRequested)
        {
            HttpListenerContext context;
            try { context = await _listener.GetContextAsync(); }
            catch (HttpListenerException) when (_stop.IsCancellationRequested) { break; }
            _ = HandleAsync(context);
        }
    }

    private async Task HandleAsync(HttpListenerContext context)
    {
        try
        {
            if (context.Request.HttpMethod != "POST") { await ReplyAsync(context, 405, new { error = "POST required" }); return; }
            if (context.Request.Headers["Authorization"] != $"Bearer {_token}") { await ReplyAsync(context, 401, new { error = "Invalid bridge token" }); return; }
            var path = context.Request.Url?.AbsolutePath.TrimEnd('/');
            using var body = await JsonDocument.ParseAsync(context.Request.InputStream);
            if (path == "/v1/approvals")
            {
                var request = ParseApproval(body.RootElement);
                var allowed = await Application.Current.Dispatcher.InvokeAsync(() => _island.AskAsync(request)).Task.Unwrap();
                await ReplyAsync(context, 200, new { requestId = request.RequestId, decision = allowed ? "allow" : "deny", permissions = request.Permissions.Select(p => p.Name) });
                return;
            }
            if (path == "/v1/completions")
            {
                var notice = new CompletionNotice(Get(body.RootElement, "conversationUrl"), GetOptional(body.RootElement, "title"), GetOptional(body.RootElement, "summary"));
                await Application.Current.Dispatcher.InvokeAsync(() => _island.ShowCompletion(notice));
                await ReplyAsync(context, 200, new { ok = true });
                return;
            }
            await ReplyAsync(context, 404, new { error = "Unknown endpoint" });
        }
        catch (Exception ex) { await ReplyAsync(context, 400, new { error = ex.Message }); }
    }

    private static ApprovalRequest ParseApproval(JsonElement root) => new(
        Get(root, "requestId"), Get(root, "conversationUrl"), Get(root, "title"), GetOptional(root, "summary"),
        root.TryGetProperty("permissions", out var permissions) && permissions.ValueKind == JsonValueKind.Array
            ? permissions.EnumerateArray().Select(x => new Permission(Get(x, "name"), GetOptional(x, "description"), GetOptional(x, "risk"))).ToArray()
            : throw new InvalidOperationException("permissions must be a non-empty array"));

    private static string Get(JsonElement element, string name) => GetOptional(element, name) is { Length: > 0 } value ? value : throw new InvalidOperationException($"{name} is required");
    private static string? GetOptional(JsonElement element, string name) => element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static async Task ReplyAsync(HttpListenerContext context, int status, object payload)
    {
        var json = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(payload));
        context.Response.StatusCode = status;
        context.Response.ContentType = "application/json";
        context.Response.ContentLength64 = json.Length;
        await context.Response.OutputStream.WriteAsync(json);
        context.Response.Close();
    }

    public async ValueTask DisposeAsync()
    {
        _stop.Cancel(); _listener.Close();
        if (_loop is not null) await _loop;
        _stop.Dispose();
    }
}
