param([Parameter(Mandatory)][string]$WixBin)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$wix = (Resolve-Path -LiteralPath $WixBin).Path
& (Join-Path $PSScriptRoot 'Build.ps1')

$exe = Join-Path $root 'dist\BatteryViewer.exe'
$version = [Reflection.AssemblyName]::GetAssemblyName($exe).Version
$release = Join-Path $root 'dist\release'
New-Item -ItemType Directory -Force $release | Out-Null
$msiName = "Battery-Viewer-$($version.ToString(2))-Windows-Setup.msi"
$stage = Join-Path $env:TEMP ("BatteryViewerPackage-" + [Guid]::NewGuid())
New-Item -ItemType Directory $stage | Out-Null

try {
    $stagedExe = Join-Path $stage 'BatteryViewer.exe'
    $object = Join-Path $stage 'BatteryViewerInstaller.wixobj'
    $msi = Join-Path $stage $msiName
    Copy-Item -LiteralPath $exe -Destination $stagedExe
    & (Join-Path $wix 'candle.exe') -nologo -arch x86 "-dProductVersion=$($version.ToString(3))" "-dAppPath=$stagedExe" -out $object (Join-Path $PSScriptRoot 'Installer.wxs')
    if ($LASTEXITCODE -ne 0) { throw 'WiX could not compile the installer source.' }
    & (Join-Path $wix 'light.exe') -nologo -spdb -out $msi $object
    if ($LASTEXITCODE -ne 0) { throw 'WiX could not link or validate the installer.' }
    Copy-Item -LiteralPath $msi -Destination (Join-Path $release $msiName) -Force
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force
}

Copy-Item -LiteralPath $exe -Destination (Join-Path $release "Battery-Viewer-$($version.ToString(2))-Windows-Portable.exe") -Force
Write-Output "Packaged $(Join-Path $release $msiName)"
