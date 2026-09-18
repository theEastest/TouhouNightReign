param(
    [string]$EngineRoot = (Join-Path $PSScriptRoot '../../LuaSTG-Sub-master'),
    [string]$CMake = 'cmake',
    [string]$ReleaseName = ('TouHouNightReign-Windows-x64-' + (Get-Date -Format 'yyyyMMdd-HHmmss')),
    [switch]$SkipBuild,
    [switch]$SkipArchive
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$EngineRoot = [IO.Path]::GetFullPath($EngineRoot)
if ($ReleaseName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw 'ReleaseName must be a simple folder name using letters, digits, dots, underscores or hyphens.'
}
$releaseRoot = Join-Path $projectRoot 'releases'
$destination = Join-Path $releaseRoot $ReleaseName
$archive = "$destination.zip"
if ((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $archive)) {
    throw "Output already exists. Choose a new ReleaseName: $destination"
}
if (-not $SkipBuild) {
    & $CMake --build (Join-Path $EngineRoot 'build/amd64') --config Release --target LuaSTG -- /m
    if ($LASTEXITCODE -ne 0) { throw "Release build failed: $LASTEXITCODE" }
}
$binaryRoot = Join-Path $EngineRoot 'build/amd64/bin'
$binaryFiles = @('LuaSTGSub.exe', 'd3dcompiler_47.dll', 'xaudio2_9redist.dll')
foreach ($name in $binaryFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $binaryRoot $name) -PathType Leaf)) {
        throw "Required runtime file missing: $name"
    }
}
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$gameRoot = Join-Path $projectRoot 'game'
# /XJ prevents development junctions from retaining dependencies on this PC.
# Saves, logs and developer self-test results must not travel to other players.
& robocopy $gameRoot $destination /E /XJ /XD (Join-Path $gameRoot 'userdata') (Join-Path $gameRoot 'legacy/virtual_data') /XF '*.log' '*.dmp' '*.result' '*.bak' 'desktop.ini' 'Thumbs.db' /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -ge 8) { throw "Copy failed: robocopy exit $LASTEXITCODE" }
foreach ($name in $binaryFiles) {
    $outputName = if ($name -eq 'LuaSTGSub.exe') { 'TouHouNightReign.exe' } else { $name }
    Copy-Item -LiteralPath (Join-Path $binaryRoot $name) -Destination (Join-Path $destination $outputName)
}
Copy-Item -LiteralPath (Join-Path $EngineRoot 'data/license') -Destination (Join-Path $destination 'licenses') -Recurse
Copy-Item -LiteralPath (Join-Path $EngineRoot 'License.txt') -Destination (Join-Path $destination 'licenses/LuaSTG-Sub-License.txt')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'release_readme.txt') -Destination (Join-Path $destination 'README.txt')
New-Item -ItemType Directory -Path (Join-Path $destination 'userdata') -Force | Out-Null
$launcher = @'
@echo off
setlocal
pushd "%~dp0"
if errorlevel 1 exit /b 1
if not exist "TouHouNightReign.exe" (
    echo Missing TouHouNightReign.exe. Please extract the entire ZIP first.
    pause
    popd
    exit /b 1
)
start "" /wait "TouHouNightReign.exe"
set "gameExit=%errorlevel%"
if not "%gameExit%"=="0" (
    echo Game exited with code %gameExit%. See engine.log in this folder.
    pause
)
popd
exit /b %gameExit%
'@
[IO.File]::WriteAllText((Join-Path $destination 'StartGame.bat'), (($launcher -replace "`r?`n", "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
$config = Get-Content -LiteralPath (Join-Path $destination 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($resource in $config.file_system.resources) {
    if ($resource.type -eq 'directory' -and -not (Test-Path -LiteralPath (Join-Path $destination $resource.path) -PathType Container)) {
        throw "Packaged resource directory missing: $($resource.path)"
    }
}
if (@(Get-ChildItem -LiteralPath $destination -Recurse -Force -Attributes ReparsePoint).Count -gt 0) {
    throw 'Release contains a filesystem link; portable packaging failed.'
}
$metadata = [ordered]@{
    name = $ReleaseName
    built_at = (Get-Date -Format o)
    platform = 'Windows x64'
    configuration = 'Release'
    engine_sha256 = (Get-FileHash -LiteralPath (Join-Path $destination 'TouHouNightReign.exe') -Algorithm SHA256).Hash
    contents = 'Current working copy; excludes player saves and development logs.'
}
$metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'release-info.json') -Encoding UTF8
$hashLines = Get-ChildItem -LiteralPath $destination -Recurse -File | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($destination.Length + 1).Replace('\', '/')
    '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $relative
}
[IO.File]::WriteAllLines((Join-Path $destination 'SHA256SUMS.txt'), [string[]]$hashLines, (New-Object Text.UTF8Encoding($false)))
if (-not $SkipArchive) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($destination, $archive, [IO.Compression.CompressionLevel]::Optimal, $true)
    $zipHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    "$zipHash  $ReleaseName.zip" | Set-Content -LiteralPath "$archive.sha256" -Encoding ASCII
    Write-Output "Archive: $archive"
}
Write-Output "Release folder: $destination"
