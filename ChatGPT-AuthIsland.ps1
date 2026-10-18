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
  $allow = '(?i)^(allow|approve|authorize|continue|permit|\u5141\u8bb8|\u6279\u51c6|\u6388\u6743|\u7ee7\u7eed|\u786e\u8ba4)$'
  $items = @()
  foreach ($button in (Get-UiButtons $root)) {
    $name = Get-Text $button
    if ($name -match $allow) { $items += [pscustomobject]@{ Name = $name; Element = $button } }
  }
  $items
}

function Test-Busy([System.Windows.Automation.AutomationElement]$root) {
  foreach ($button in (Get-UiButtons $root)) {
    if ((Get-Text $button) -match '(?i)^(stop generating|stop|\u505c\u6b62\u751f\u6210)$') { return $true }
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
$status.Text = 'Monitoring ChatGPT host...'
$form.Controls.Add($status)
$approve = New-Object Windows.Forms.Button
$approve.Text = 'Approve'; $approve.FlatStyle = 'Flat'; $approve.FlatAppearance.BorderSize = 0
$approve.BackColor = [Drawing.Color]::FromArgb(43,180,111); $approve.ForeColor = [Drawing.Color]::White
$approve.Location = New-Object Drawing.Point(232,72); $approve.Size = New-Object Drawing.Size(74,28)
$approve.Add_Click({
  if ($script:pending.Count -gt 0) {
    try {
      $pattern = $script:pending[0].Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
      $pattern.Invoke(); $status.Text = 'Approved current ChatGPT request'; $script:lastRequestKey = ''
    } catch { $status.Text = 'Approval failed; use ChatGPT directly' }
  }
})
$form.Controls.Add($approve)
$ignore = New-Object Windows.Forms.Button
$ignore.Text = 'Ignore'; $ignore.FlatStyle = 'Flat'; $ignore.FlatAppearance.BorderSize = 0
$ignore.BackColor = [Drawing.Color]::FromArgb(55,61,71); $ignore.ForeColor = [Drawing.Color]::White
$ignore.Location = New-Object Drawing.Point(316,72); $ignore.Size = New-Object Drawing.Size(70,28)
$ignore.Add_Click({ $script:lastRequestKey = ''; $script:pending = @(); $status.Text = 'Ignored current request' })
$form.Controls.Add($ignore)

$notify = New-Object Windows.Forms.NotifyIcon
$notify.Icon = [Drawing.SystemIcons]::Information
$notify.Visible = $true
$notify.Text = 'ChatGPT Auth Island'
$notify.Add_DoubleClick({ if ($script:chatHandle -ne [IntPtr]::Zero) { [Native]::ShowWindowAsync($script:chatHandle, 9); [Native]::SetForegroundWindow($script:chatHandle) } })
$menu = New-Object Windows.Forms.ContextMenuStrip
$exit = $menu.Items.Add('Exit')
$exit.Add_Click({ $notify.Visible = $false; $timer.Stop(); $form.Close() })
$notify.ContextMenuStrip = $menu

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 900
$timer.Add_Tick({
  $process = Get-ChatGPTWindow
  if (-not $process) { $status.Text = 'ChatGPT desktop host not found'; return }
  $script:chatProcess = $process; $script:chatHandle = $process.MainWindowHandle
  try { $root = [System.Windows.Automation.AutomationElement]::FromHandle($script:chatHandle) } catch { return }
  $busy = Test-Busy $root
  if ($script:lastBusy -and -not $busy) {
    $notify.ShowBalloonTip(5000, 'ChatGPT session complete', 'Double-click the tray icon to return to ChatGPT.', [Windows.Forms.ToolTipIcon]::Info)
  }
  $script:lastBusy = $busy
  $requests = @(Find-PermissionRequests $root)
  $script:pending = $requests
  if ($requests.Count -gt 0) {
    $key = (($requests | ForEach-Object Name) -join '|')
    if ($key -ne $script:lastRequestKey) { $script:lastRequestKey = $key; $form.Show() }
    $status.Text = "ChatGPT permission request: $($requests[0].Name)"
  } elseif (-not $busy) { $status.Text = 'Monitoring ChatGPT host...' }
})
$timer.Start()
[Windows.Forms.Application]::Run($form)
