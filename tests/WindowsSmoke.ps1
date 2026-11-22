# Run in the interactive Windows session after installing and launching the app.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -Name WindowVisibility -Namespace BatteryViewerTests -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool IsWindowVisible(System.IntPtr handle);
'@
$exe = Join-Path $env:LOCALAPPDATA 'Programs\Battery Percent Viewer\BatteryViewer.exe'
$process = Get-Process BatteryViewer | Where-Object Path -eq $exe | Select-Object -First 1
if (!$process -or !$process.MainWindowHandle) { throw 'Installed application window is missing.' }
$window = [System.Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
function Find-Control($parent, $id) {
    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $id)
    $parent.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
}
function Invoke-Button($button) {
    $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}
function Find-Settings($parent) {
    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, 'Settings')
    for ($i = 0; $i -lt 30; $i++) {
        $dialog = $parent.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition) |
            Where-Object { $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window } | Select-Object -First 1
        if ($dialog) { return $dialog }
        Start-Sleep -Milliseconds 150
    }
    throw 'Settings dialog did not open.'
}
$level = Find-Control $window 'Level'
$status = Find-Control $window 'Status'
if (!$level.Current.Name -or !$status.Current.Name) { throw 'Battery reading needs accessible text.' }
if (Find-Control $window 'Refresh') { throw 'Unexpected manual refresh button.' }
Write-Output ("Installed dashboard: {0}. {1}." -f $level.Current.Name, $status.Current.Name)
$speak = Find-Control $window 'Speak'
$settings = Find-Control $window 'Settings'
Invoke-Button $speak
Start-Sleep -Milliseconds 900
$view = Find-Control $window 'ViewMenu'
$view.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
Start-Sleep -Milliseconds 200
Invoke-Button (Find-Control $view 'AdjustSize')
$dialog = Find-Settings $window
foreach ($id in 'SizeSlider','ThemePicker','Voices','Preview','Power','Low','LowThreshold','RunInBackground','About','Version','Done') {
    $control = Find-Control $dialog $id
    if (!$control.Current.Name) { throw "Missing accessible name for $id." }
    Write-Output ("{0} = {1}" -f $id, $control.Current.Name)
}
$size = Find-Control $dialog 'SizeSlider'
$range = $size.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
if (!$size.Current.HasKeyboardFocus -or $range.Current.SmallChange -ne 1 -or $range.Current.IsReadOnly) {
    throw 'View should open Settings with an adjustable, focused size slider.'
}
$oldSize = $range.Current.Value
$newSize = if ($oldSize -eq $range.Current.Maximum) { $oldSize - 1 } else { $oldSize + 1 }
try {
    $range.SetValue($newSize)
    Start-Sleep -Milliseconds 200
    if ($range.Current.Value -ne $newSize -or (Find-Control $dialog 'SizeValue').Current.Name -ne "$newSize pt") {
        throw 'The slider and its displayed size should update together.'
    }
} finally {
    $range.SetValue($oldSize)
}
Write-Output 'View opened the focused battery size slider, and UI Automation adjusted its value.'
$lowToggle = (Find-Control $dialog 'Low').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
$thresholdControl = Find-Control $dialog 'LowThreshold'
$threshold = $thresholdControl.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
$startedOff = $lowToggle.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::Off
if ($startedOff) {
    if ($thresholdControl.Current.IsEnabled) { throw 'Low battery threshold should be disabled when alerts are off.' }
    $lowToggle.Toggle()
    Start-Sleep -Milliseconds 200
}
$oldThreshold = $threshold.Current.Value
$newThreshold = if ($oldThreshold -eq 35) { 30 } else { 35 }
try {
    $threshold.SetValue($newThreshold)
    Start-Sleep -Milliseconds 200
    $savedThreshold = Get-ItemPropertyValue 'HKCU:\Software\Varun Manoj Kumar\Battery Viewer' LowBatteryThreshold
    if ($threshold.Current.Value -ne $newThreshold -or $savedThreshold -ne "$newThreshold" -or
        (Find-Control $dialog 'LowThresholdValue').Current.Name -ne "$newThreshold%") {
        throw 'The low battery threshold should update the displayed and saved values.'
    }
} finally {
    $threshold.SetValue($oldThreshold)
    if ($startedOff) { $lowToggle.Toggle() }
}
Write-Output 'Low battery threshold was adjustable and saved.'
$expectedVersion = [Reflection.AssemblyName]::GetAssemblyName($exe).Version.ToString(2)
if ((Find-Control $dialog 'Version').Current.Name -notlike "*$expectedVersion") { throw 'Incorrect version in About.' }
$repeat = Start-Process -FilePath $exe -PassThru
if (!$repeat.WaitForExit(5000)) { throw 'A second copy remained running.' }
if (@(Get-Process BatteryViewer | Where-Object Path -eq $exe).Count -ne 1 -or !$dialog.Current.IsEnabled) {
    throw 'Repeated launch did not preserve the existing viewer and its settings.'
}
Write-Output 'Repeated launch kept the original window and Settings dialog.'
$voices = Find-Control $dialog 'Voices'
$expand = $voices.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
$expand.Expand()
Start-Sleep -Milliseconds 250
$voiceItems = $voices.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)))
Write-Output ("Voice choices: " + (($voiceItems | ForEach-Object { $_.Current.Name }) -join ', '))
$expand.Collapse()
Invoke-Button (Find-Control $dialog 'Preview')
Start-Sleep -Milliseconds 1000
Invoke-Button (Find-Control $dialog 'Done')
Start-Sleep -Milliseconds 400
if (!$settings.Current.IsEnabled) { throw 'Settings failed to close.' }

# Exercise sentinel values that hardware rarely exposes on demand.
$assembly = [Reflection.Assembly]::LoadFrom($exe)
$type = $assembly.GetType('Reading', $true)
$decode = $type.GetMethod('Decode')
function Sample([byte]$ac, [byte]$flags, [byte]$level) {
    $decode.Invoke($null, [object[]]@($ac,$flags,$level))
}
if ((Sample 1 128 255).Status -ne 'No battery detected') { throw 'Missing battery' }
if ($null -ne (Sample 255 255 255).Percent) { throw 'Unknown level' }
if ((Sample 1 1 80).Status -ne 'Connected to power') { throw 'Paused charging' }
if ((Sample 1 9 30).Status -ne 'Charging') { throw 'Charging' }
$low = Sample 0 2 20
if (!$low.ShouldAnnounce((Sample 0 2 21), $false, 20) -or $low.ShouldAnnounce($low, $true, 20)) { throw 'Low battery alert transition' }
$belowCustom = Sample 0 2 33
$aboveCustom = Sample 0 2 36
if (!$belowCustom.ShouldAnnounce($aboveCustom, $false, 35) -or
    !$belowCustom.ShouldAnnounce((Sample 1 1 33), $false, 35) -or
    $low.ShouldAnnounce($belowCustom, $false, 35) -or
    $belowCustom.ShouldAnnounce($aboveCustom, $false, 20) -or
    $belowCustom.ShouldAnnounce($aboveCustom, $false, $null) -or
    (Sample 1 9 33).ShouldAnnounce((Sample 1 9 36), $false, 35)) {
    throw 'Custom low battery threshold'
}
Write-Output 'Windows accessibility and battery state checks passed.'

$prefs = 'HKCU:\Software\Varun Manoj Kumar\Battery Viewer'
$wasBackground = (Get-ItemProperty $prefs -ErrorAction SilentlyContinue).RunInBackground -eq '1'
$mainHandle = $process.MainWindowHandle
try {
    Invoke-Button $settings
    $dialog = Find-Settings $window
    $background = (Find-Control $dialog 'RunInBackground').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
    if (!$wasBackground) { $background.Toggle() }
    if ((Get-ItemPropertyValue $prefs RunInBackground) -ne '1') { throw 'The background setting did not save.' }
    Invoke-Button (Find-Control $dialog 'Done')
    Start-Sleep -Milliseconds 300
    if (!$process.CloseMainWindow()) { throw 'Could not close the main window.' }
    Start-Sleep -Milliseconds 400
    $process.Refresh()
    if ($process.HasExited) { throw 'Closing exited the viewer with background mode on.' }
    if ([BatteryViewerTests.WindowVisibility]::IsWindowVisible($mainHandle)) { throw 'Closing left the main window visible.' }

    $repeat = Start-Process -FilePath $exe -PassThru
    if (!$repeat.WaitForExit(5000)) { throw 'A background process should receive the repeat launch.' }
    for ($i = 0; $i -lt 30 -and ![BatteryViewerTests.WindowVisibility]::IsWindowVisible($mainHandle); $i++) {
        Start-Sleep -Milliseconds 150
    }
    if (![BatteryViewerTests.WindowVisibility]::IsWindowVisible($mainHandle)) { throw 'The existing window did not reopen.' }
    $window = [System.Windows.Automation.AutomationElement]::FromHandle($mainHandle)
    $file = Find-Control $window 'FileMenu'
    $file.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
    Start-Sleep -Milliseconds 200
    Invoke-Button (Find-Control $file 'Quit')
    if (!$process.WaitForExit(5000)) { throw 'Explicit Quit should stop the process even in background mode.' }
    Write-Output 'Background close hid the window, relaunch reopened the same process, and Quit exited.'
} finally {
    if (!$wasBackground) { Set-ItemProperty $prefs RunInBackground '0' }
}
if (!$wasBackground) {
    $normal = Start-Process -FilePath $exe -PassThru
    $normalWindow = $null
    $processId = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $normal.Id)
    for ($i = 0; $i -lt 40 -and !$normalWindow; $i++) {
        Start-Sleep -Milliseconds 150
        $normalWindow = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
            [System.Windows.Automation.TreeScope]::Children, $processId) |
            Where-Object { $_.Current.Name -eq 'Battery % Viewer' -and !$_.Current.IsOffscreen } |
            Select-Object -First 1
    }
    if (!$normalWindow) { throw 'Could not find the restarted viewer window.' }
    $normalWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
    if (!$normal.WaitForExit(5000)) { throw 'Closing with background mode off should exit.' }
    Write-Output 'Normal close exited with background mode off.'
}
