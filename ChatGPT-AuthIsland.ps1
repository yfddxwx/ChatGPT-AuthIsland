Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Native {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
  [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hWnd, int attr, ref int value, int size);
}
'@

$script:chatHandle = [IntPtr]::Zero
$script:lastBusy = $false
$script:lastRequestKey = ''
$script:pending = @()
$script:lastCompletedAt = [DateTime]::MinValue
$script:expanded = $false
$script:targetWidth = 286
$script:targetHeight = 72

function Get-ChatGPTWindow {
  Get-Process -Name 'ChatGPT','chatgpt' -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}

function Get-Text([System.Windows.Automation.AutomationElement]$element) {
  try { return [string]$element.Current.Name } catch { return '' }
}

function Get-UiButtons([System.Windows.Automation.AutomationElement]$root) {
  $condition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
  $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
}

function Get-ElementContext([System.Windows.Automation.AutomationElement]$element) {
  $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker; $node = $element
  for ($i = 0; $i -lt 5; $i++) {
    try { $node = $walker.GetParent($node) } catch { break }
    if ($null -eq $node) { break }
    $name = Get-Text $node
    if ($name -and $name -ne (Get-Text $element)) { return $name }
  }
  return 'ChatGPT request'
}

function Find-PermissionRequests([System.Windows.Automation.AutomationElement]$root) {
  # Explicit permission verbs only: ordinary chat buttons are never exposed for approval.
  $allow = '(?i)^(allow|approve|authorize|permit|\u5141\u8bb8|\u6279\u51c6|\u6388\u6743)$'
  $items = @()
  foreach ($button in (Get-UiButtons $root)) {
    $name = Get-Text $button
    if ($name -match $allow) {
      $id = try { ($button.GetRuntimeId() -join '.') } catch { $name }
      $items += [pscustomobject]@{ Name = $name; Context = Get-ElementContext $button; Id = $id; Element = $button }
    }
  }
  $items
}

function Test-Busy([System.Windows.Automation.AutomationElement]$root) {
  foreach ($button in (Get-UiButtons $root)) {
    if ((Get-Text $button) -match '(?i)^(stop generating|stop|\u505c\u6b62\u751f\u6210)$') { return $true }
  }
  return $false
}

function Set-RoundedRegion {
  $path = New-Object Drawing.Drawing2D.GraphicsPath
  $r = 30; $w = $form.Width; $h = $form.Height
  $path.AddArc(0,0,$r,$r,180,90); $path.AddArc($w-$r,0,$r,$r,270,90)
  $path.AddArc($w-$r,$h-$r,$r,$r,0,90); $path.AddArc(0,$h-$r,$r,$r,90,90)
  $path.CloseFigure(); $form.Region = New-Object Drawing.Region($path)
}

function Set-Expanded([bool]$value) {
  $script:expanded = $value
  $script:targetWidth = if ($value) { 430 } else { 286 }
  $script:targetHeight = if ($value) { 142 } else { 72 }
  $approve.Visible = $value; $ignore.Visible = $value
  $line.Visible = $value; $request.Visible = $value; $context.Visible = $value
}

$form = New-Object Windows.Forms.Form
$form.FormBorderStyle = 'None'; $form.StartPosition = 'Manual'; $form.TopMost = $true
$form.ShowInTaskbar = $false; $form.BackColor = [Drawing.Color]::FromArgb(16,22,33)
$form.ForeColor = [Drawing.Color]::White; $form.Opacity = 0.94
$form.Width = 286; $form.Height = 72
$form.Add_Resize({ Set-RoundedRegion })
$form.Add_Shown({
  $screen = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $form.Left = $screen.Right - $form.Width - 24; $form.Top = $screen.Top + 18
  $mica = 3; $corner = 2
  [Native]::DwmSetWindowAttribute($form.Handle, 38, [ref]$mica, 4) | Out-Null
  [Native]::DwmSetWindowAttribute($form.Handle, 33, [ref]$corner, 4) | Out-Null
  Set-RoundedRegion
})
$form.Add_Paint({
  param($sender, $e)
  $e.Graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $brush = New-Object Drawing.Drawing2D.LinearGradientBrush(
    (New-Object Drawing.Point(0,0)), (New-Object Drawing.Point($sender.Width,$sender.Height)),
    [Drawing.Color]::FromArgb(235,20,28,42), [Drawing.Color]::FromArgb(225,8,12,20))
  $e.Graphics.FillRectangle($brush, 0, 0, $sender.Width, $sender.Height)
  $brush.Dispose()
  $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(90,150,190,255),1)
  $e.Graphics.DrawLine($pen, 28, 1, $sender.Width-28, 1); $pen.Dispose()
  $dot = if ($script:expanded) { [Drawing.Color]::FromArgb(70,220,150) } else { [Drawing.Color]::FromArgb(95,165,255) }
  $dotBrush = New-Object Drawing.SolidBrush($dot)
  $e.Graphics.FillEllipse($dotBrush, 22, 25, 10, 10); $dotBrush.Dispose()
})

$title = New-Object Windows.Forms.Label
$title.Location = New-Object Drawing.Point(44,13); $title.AutoSize = $true
$title.Font = New-Object Drawing.Font('Segoe UI Semibold', 12)
$title.Text = 'Auth Island'; $form.Controls.Add($title)
$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(44,38); $status.AutoSize = $true
$status.ForeColor = [Drawing.Color]::FromArgb(185,199,220)
$status.Text = 'Monitoring ChatGPT...'; $form.Controls.Add($status)
$request = New-Object Windows.Forms.Label
$request.Location = New-Object Drawing.Point(24,70); $request.MaximumSize = New-Object Drawing.Size(382,18); $request.AutoSize = $true
$request.Font = New-Object Drawing.Font('Segoe UI', 9)
$request.ForeColor = [Drawing.Color]::FromArgb(210,225,245); $request.Visible = $false
$form.Controls.Add($request)
$context = New-Object Windows.Forms.Label
$context.Location = New-Object Drawing.Point(24,88); $context.MaximumSize = New-Object Drawing.Size(210,18); $context.AutoSize = $true
$context.Font = New-Object Drawing.Font('Segoe UI', 8); $context.ForeColor = [Drawing.Color]::FromArgb(145,170,205); $context.Visible = $false
$form.Controls.Add($context)
$line = New-Object Windows.Forms.Label
$line.BackColor = [Drawing.Color]::FromArgb(55,75,100); $line.Location = New-Object Drawing.Point(24,62)
$line.Size = New-Object Drawing.Size(382,1); $line.Visible = $false; $form.Controls.Add($line)

$approve = New-Object Windows.Forms.Button
$approve.Text = 'Approve'; $approve.FlatStyle = 'Flat'; $approve.FlatAppearance.BorderSize = 0
$approve.BackColor = [Drawing.Color]::FromArgb(42,190,125); $approve.ForeColor = [Drawing.Color]::White
$approve.Location = New-Object Drawing.Point(250,103); $approve.Size = New-Object Drawing.Size(76,28)
$approve.Visible = $false; $approve.Add_Click({
  if ($script:pending.Count -gt 0) {
    try {
      $pattern = $script:pending[0].Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
      $pattern.Invoke(); $status.Text = 'Approved current request'; $script:lastRequestKey = ''
    } catch { $status.Text = 'Approval failed; use ChatGPT directly' }
  }
})
$form.Controls.Add($approve)
$ignore = New-Object Windows.Forms.Button
$ignore.Text = 'Ignore'; $ignore.FlatStyle = 'Flat'; $ignore.FlatAppearance.BorderSize = 0
$ignore.BackColor = [Drawing.Color]::FromArgb(48,62,82); $ignore.ForeColor = [Drawing.Color]::White
$ignore.Location = New-Object Drawing.Point(334,103); $ignore.Size = New-Object Drawing.Size(72,28)
$ignore.Visible = $false; $ignore.Add_Click({
  $script:lastRequestKey = ''; $script:pending = @(); $status.Text = 'Ignored current request'; Set-Expanded $false
})
$form.Controls.Add($ignore)

$notify = New-Object Windows.Forms.NotifyIcon
$notify.Icon = [Drawing.SystemIcons]::Information; $notify.Visible = $true; $notify.Text = 'ChatGPT Auth Island'
$notify.Add_DoubleClick({ if ($script:chatHandle -ne [IntPtr]::Zero) { [Native]::ShowWindowAsync($script:chatHandle, 9); [Native]::SetForegroundWindow($script:chatHandle) } })
$notify.Add_BalloonTipClicked({ if ($script:chatHandle -ne [IntPtr]::Zero) { [Native]::ShowWindowAsync($script:chatHandle, 9); [Native]::SetForegroundWindow($script:chatHandle) } })
$menu = New-Object Windows.Forms.ContextMenuStrip
$exit = $menu.Items.Add('Exit')
$exit.Add_Click({ $notify.Visible = $false; $timer.Stop(); $form.Close() })
$notify.ContextMenuStrip = $menu

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 120
$timer.Add_Tick({
  if ($form.Width -ne $script:targetWidth -or $form.Height -ne $script:targetHeight) {
    $form.Width += [Math]::Sign($script:targetWidth - $form.Width) * [Math]::Min(22, [Math]::Abs($script:targetWidth - $form.Width))
    $form.Height += [Math]::Sign($script:targetHeight - $form.Height) * [Math]::Min(14, [Math]::Abs($script:targetHeight - $form.Height))
    $screen = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $form.Left = $screen.Right - $form.Width - 24
    Set-RoundedRegion; $form.Invalidate()
  }
  $process = Get-ChatGPTWindow
  if (-not $process) { $status.Text = 'ChatGPT desktop host not found'; return }
  $script:chatHandle = $process.MainWindowHandle
  try { $root = [System.Windows.Automation.AutomationElement]::FromHandle($script:chatHandle) } catch { return }
  $busy = Test-Busy $root
  if ($script:lastBusy -and -not $busy -and (([DateTime]::Now - $script:lastCompletedAt).TotalSeconds -gt 3)) {
    $script:lastCompletedAt = [DateTime]::Now
    $notify.ShowBalloonTip(5000, 'ChatGPT session complete', 'Click to return to the active ChatGPT conversation.', [Windows.Forms.ToolTipIcon]::Info)
  }
  $script:lastBusy = $busy
  $requests = @(Find-PermissionRequests $root); $script:pending = $requests
  if ($requests.Count -gt 0) {
    $key = (($requests | ForEach-Object Id) -join '|')
    if ($key -ne $script:lastRequestKey) { $script:lastRequestKey = $key; Set-Expanded $true; $form.Show() }
    $request.Text = "ChatGPT requests: $($requests[0].Name)$(if ($requests.Count -gt 1) { "  +$($requests.Count - 1)" })"
    $context.Text = $requests[0].Context; $status.Text = 'Action required'
  } elseif (-not $busy -and -not $script:expanded) { $status.Text = 'Monitoring ChatGPT...' }
})
$timer.Start()
Set-Expanded $false
[Windows.Forms.Application]::Run($form)
