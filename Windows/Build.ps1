param([switch]$Install)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$dist = Join-Path $root 'dist'
$exe = Join-Path $dist 'BatteryViewer.exe'
New-Item -ItemType Directory -Force $dist | Out-Null
$framework = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319"
$sdkRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\UnionMetadata"
$sdk = Get-ChildItem $sdkRoot -Directory | Where-Object { $_.Name -match '^10\.0\.' } | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (!$sdk) { throw 'Install the Windows 10 or 11 SDK to build Battery Viewer.' }
$refs = @('System.Xaml.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Runtime.dll','System.Runtime.InteropServices.WindowsRuntime.dll','System.Runtime.WindowsRuntime.dll','WPF\PresentationCore.dll','WPF\PresentationFramework.dll','WPF\WindowsBase.dll','WPF\UIAutomationTypes.dll') | ForEach-Object { "/reference:$framework\$_" }
$refs += "/reference:$($sdk.FullName)\Windows.winmd"
$resources = Get-ChildItem "$PSScriptRoot\*.xaml" | ForEach-Object { "/resource:$($_.FullName),$($_.Name)" }
$sources = (Get-ChildItem "$PSScriptRoot\*.cs").FullName
& "$framework\csc.exe" /nologo /optimize+ /target:winexe /platform:anycpu /codepage:65001 "/out:$exe" "/win32manifest:$PSScriptRoot\app.manifest" "/win32icon:$root\windows App Files\Project files\ApIcon.ico" @refs @resources @sources
if ($LASTEXITCODE -ne 0) { throw "Compilation failed." }
Write-Output "Built $exe"
if ($Install) {
    $folder = Join-Path $env:LOCALAPPDATA 'Programs\Battery Percent Viewer'
    $installed = Join-Path $folder 'BatteryViewer.exe'
    $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Get-Process BatteryViewer -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $installed } | ForEach-Object {
        $quit = $null
        if ([Threading.EventWaitHandle]::TryOpenExisting("Local\BatteryPercentViewer.$userSid.Quit", [ref]$quit)) {
            try { [void]$quit.Set() } finally { $quit.Dispose() }
        } else {
            [void]$_.CloseMainWindow()
        }
        if (!$_.WaitForExit(5000)) { throw 'Quit Battery Viewer and run the installer again.' }
    }
    New-Item -ItemType Directory -Force $folder | Out-Null
    Copy-Item $exe $installed -Force
    $link = Join-Path ([Environment]::GetFolderPath('Programs')) 'Battery % Viewer.lnk'
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($link)
    $shortcut.TargetPath = $installed
    $shortcut.WorkingDirectory = $folder
    $shortcut.Save()
    Write-Output "Installed $installed and $link"
}
