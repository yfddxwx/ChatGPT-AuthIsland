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
}
'@

$script:chatProcess = $null
$script:chatHandle = [IntPtr]::Zero
$script:lastBusy = $false
$script:lastRequestKey = ''
$script:pending = @()

function Get-ChatGPTWindow {
  Get-Process -Name 'ChatGPT','chatgpt' -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}

function Get-Text([System.Windows.Automation.AutomationElement]$element) {
  try { return [string]$element.Current.Name } catch { return '' }
}

function Get-UiButtons([System.Windows.Automation.AutomationElement]$root) {
  $type = [System.Windows.Automation.Automation.ControlType]::Button
  $condition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $type)
  $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
}

function Find-PermissionRequests([System.Windows.Automation.AutomationElement]$root) {
  $allow = '(?i)^(allow|approve|authorize|continue|permit|允许|批准|授权|继续|确认)$'
  $items = @()
  foreach ($button in (Get-UiButtons $root)) {
    $name = Get-Text $button
    if ($name -match $allow) { $items += [pscustomobject]@{ Name = $name; Element = $button } }
  }
  $items
}

function Test-Busy([System.Windows.Automation.AutomationElement]$root) {
  foreach ($button in (Get-UiButtons $root)) {
    if ((Get-Text $button) -match '(?i)^(stop generating|停止生成|stop)$') { return $true }
  }
  return $false
}

$form = New-Object Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.StartPosition = 'Manual'
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.BackColor = [Drawing.Color]::FromArgb(22,24,29)
$form.ForeColor = [Drawing.Color]::White
$form.Opacity = 0.96
$form.Width = 410
$form.Height = 116
$form.Add_Shown({
  $screen = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $form.Left = $screen.Right - $form.Width - 24
  $form.Top = $screen.Top + 18
})
$form.Add_Paint({
  param($sender, $e)
  $path = New-Object Drawing.Drawing2D.GraphicsPath
  $r = 22; $w = $sender.Width; $h = $sender.Height
  $path.AddArc(0,0,$r,$r,180,90); $path.AddArc($w-$r,0,$r,$r,270,90)
  $path.AddArc($w-$r,$h-$r,$r,$r,0,90); $path.AddArc(0,$h-$r,$r,$r,90,90)
  $path.CloseFigure(); $sender.Region = New-Object Drawing.Region($path)
})

$title = New-Object Windows.Forms.Label
$title.Location = New-Object Drawing.Point(22,14); $title.AutoSize = $true
$title.Font = New-Object Drawing.Font('Segoe UI Semibold', 12)
$title.Text = 'ChatGPT Auth Island'
$form.Controls.Add($title)
$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(22,42); $status.AutoSize = $true
$status.ForeColor = [Drawing.Color]::FromArgb(190,198,210)
$status.Text = '正在监控 ChatGPT 宿主…'
$form.Controls.Add($status)
$approve = New-Object Windows.Forms.Button
$approve.Text = '批准'; $approve.FlatStyle = 'Flat'; $approve.FlatAppearance.BorderSize = 0
$approve.BackColor = [Drawing.Color]::FromArgb(43,180,111); $approve.ForeColor = [Drawing.Color]::White
$approve.Location = New-Object Drawing.Point(232,72); $approve.Size = New-Object Drawing.Size(74,28)
$approve.Add_Click({
  if ($script:pending.Count -gt 0) {
    try {
      $pattern = $script:pending[0].Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
      $pattern.Invoke(); $status.Text = '已批准 ChatGPT 当前权限请求'; $script:lastRequestKey = ''
    } catch { $status.Text = '批准失败：请在 ChatGPT 窗口中手动操作' }
  }
})
$form.Controls.Add($approve)
$ignore = New-Object Windows.Forms.Button
$ignore.Text = '忽略'; $ignore.FlatStyle = 'Flat'; $ignore.FlatAppearance.BorderSize = 0
$ignore.BackColor = [Drawing.Color]::FromArgb(55,61,71); $ignore.ForeColor = [Drawing.Color]::White
$ignore.Location = New-Object Drawing.Point(316,72); $ignore.Size = New-Object Drawing.Size(70,28)
$ignore.Add_Click({ $script:lastRequestKey = ''; $script:pending = @(); $status.Text = '已忽略当前请求' })
$form.Controls.Add($ignore)

$notify = New-Object Windows.Forms.NotifyIcon
$notify.Icon = [Drawing.SystemIcons]::Information
$notify.Visible = $true
$notify.Text = 'ChatGPT Auth Island'
$notify.Add_DoubleClick({ if ($script:chatHandle -ne [IntPtr]::Zero) { [Native]::ShowWindowAsync($script:chatHandle, 9); [Native]::SetForegroundWindow($script:chatHandle) } })
$menu = New-Object Windows.Forms.ContextMenuStrip
$exit = $menu.Items.Add('退出')
$exit.Add_Click({ $notify.Visible = $false; $timer.Stop(); $form.Close() })
$notify.ContextMenuStrip = $menu

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 900
$timer.Add_Tick({
  $process = Get-ChatGPTWindow
  if (-not $process) { $status.Text = '未发现 ChatGPT 桌面宿主'; return }
  $script:chatProcess = $process; $script:chatHandle = $process.MainWindowHandle
  try { $root = [System.Windows.Automation.AutomationElement]::FromHandle($script:chatHandle) } catch { return }
  $busy = Test-Busy $root
  if ($script:lastBusy -and -not $busy) {
    $notify.ShowBalloonTip(5000, 'ChatGPT 会话完成', '点击托盘图标可回到对应 ChatGPT 会话。', [Windows.Forms.ToolTipIcon]::Info)
  }
  $script:lastBusy = $busy
  $requests = @(Find-PermissionRequests $root)
  $script:pending = $requests
  if ($requests.Count -gt 0) {
    $key = (($requests | ForEach-Object Name) -join '|')
    if ($key -ne $script:lastRequestKey) { $script:lastRequestKey = $key; $form.Show() }
    $status.Text = "ChatGPT 请求权限：$($requests[0].Name)"
  } elseif (-not $busy) { $status.Text = '正在监控 ChatGPT 宿主…' }
})
$timer.Start()
[Windows.Forms.Application]::Run($form)
