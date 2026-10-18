using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace ChatGPT.AuthIsland;

public partial class IslandWindow : Window
{
    private ApprovalRequest? _current;
    private TaskCompletionSource<bool>? _choice;
    private string? _completionUrl;
    private string _address = "";

    public IslandWindow()
    {
        InitializeComponent();
        Loaded += (_, _) => PositionAtTop();
    }

    public void SetBridgeAddress(string address) => _address = address;

    public void ShowIdle()
    {
        _current = null;
        _completionUrl = null;
        Heading.Text = "ChatGPT Auth Island";
        Subheading.Text = $"Bridge ready at {_address}";
        StatusDot.Background = (Brush)FindResource("Primary");
        RequestPanel.Visibility = Visibility.Collapsed;
        ResizeTo(460, 88);
        Show(); Activate();
    }

    public Task<bool> AskAsync(ApprovalRequest request)
    {
        _current = request;
        _completionUrl = null;
        Heading.Text = request.Title;
        Subheading.Text = "ChatGPT requests your approval";
        Summary.Text = request.Summary ?? "Review the host-provided permissions before continuing.";
        PermissionList.ItemsSource = request.Permissions;
        StatusDot.Background = new SolidColorBrush(Color.FromRgb(255, 190, 66));
        RequestPanel.Visibility = Visibility.Visible;
        ResizeTo(460, Math.Min(560, 210 + request.Permissions.Count * 56));
        Show(); Activate();
        _choice = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        return _choice.Task;
    }

    public void ShowCompletion(CompletionNotice notice)
    {
        _current = null;
        _completionUrl = notice.ConversationUrl;
        Heading.Text = notice.Title ?? "ChatGPT session finished";
        Subheading.Text = notice.Summary ?? "Click to return to the conversation";
        StatusDot.Background = (Brush)FindResource("Primary");
        RequestPanel.Visibility = Visibility.Collapsed;
        ResizeTo(460, 88);
        Show(); Activate();
    }

    private void Allow(object sender, RoutedEventArgs e) => Decide(true);
    private void Deny(object sender, RoutedEventArgs e) => Decide(false);
    private void Decide(bool allowed)
    {
        _choice?.TrySetResult(allowed);
        ShowIdle();
    }

    private void DragWindow(object sender, MouseButtonEventArgs e)
    {
        if (e.OriginalSource is Button) return;
        if (_completionUrl is not null)
        {
            Process.Start(new ProcessStartInfo(_completionUrl) { UseShellExecute = true });
            _completionUrl = null;
            ShowIdle();
            return;
        }
        if (e.LeftButton == MouseButtonState.Pressed) DragMove();
    }

    private void ResizeTo(double width, double height)
    {
        BeginAnimation(WidthProperty, new DoubleAnimation(width, TimeSpan.FromMilliseconds(220)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
        BeginAnimation(HeightProperty, new DoubleAnimation(height, TimeSpan.FromMilliseconds(220)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
        BeginAnimation(OpacityProperty, new DoubleAnimation(0.82, 1, TimeSpan.FromMilliseconds(180)));
    }

    private void PositionAtTop()
    {
        Left = (SystemParameters.WorkArea.Width - Width) / 2;
        Top = SystemParameters.WorkArea.Top + 18;
    }
}
