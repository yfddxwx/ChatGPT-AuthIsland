namespace ChatGPT.AuthIsland;

public sealed record Permission(string Name, string? Description, string? Risk);

public sealed record ApprovalRequest(
    string RequestId,
    string ConversationUrl,
    string Title,
    string? Summary,
    IReadOnlyList<Permission> Permissions);

public sealed record CompletionNotice(string ConversationUrl, string? Title, string? Summary);
