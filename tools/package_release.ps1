param(
    [string]$EngineRoot = (Join-Path $PSScriptRoot '../../LuaSTG-Sub-master'),
    [string]$CMake = 'cmake',
    [string]$ReleaseName = ('TouHouNightReign-Windows-x64-' + (Get-Date -Format 'yyyyMMdd-HHmmss')),
    [switch]$SkipBuild,
    [switch]$SkipArchive
)

$ErrorActionPreference = 'Stop'
function Get-ReleaseSha256([string]$path) {
    $hasher = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($path)
    try { return [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
    finally { $stream.Dispose(); $hasher.Dispose() }
}
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
$gameRoot = Join-Path $projectRoot 'game'
# Only tracked game files and the explicitly reviewed new replay files are
# eligible. Copying the entire working tree also ships unrelated untracked
# work, ignored player data and potentially private diagnostic material.
$approvedNewFiles = @(
    'game/assets/legacy_replay/bgm/st02boss.ogg',
    'game/assets/legacy_replay/bgm/st03boss.ogg',
    'game/assets/legacy_replay/bgm/st04boss.ogg',
    'game/assets/legacy_replay/bgm/st05boss.ogg',
    'game/assets/legacy_replay/bgm/st06boss.ogg',
    'game/assets/ui/status/affixes-moonlit.png',
    'game/scripts/tnr/legacy_replay/anm_geometry.lua',
    'game/scripts/tnr/legacy_replay/bullet_transforms.lua',
    'game/scripts/tnr/legacy_replay/charge_particles.lua',
    'game/scripts/tnr/legacy_replay/classic_bombs.lua',
    'game/scripts/tnr/legacy_replay/classic_shots.lua',
    'game/scripts/tnr/legacy_replay/coop.lua',
    'game/scripts/tnr/legacy_replay/curve_laser.lua',
    'game/scripts/tnr/legacy_replay/laser.lua',
    'game/scripts/tnr/legacy_replay/modern_combat.lua',
    'game/scripts/tnr/legacy_replay/reference_rng.lua',
    'game/scripts/tnr/legacy_replay/reference_rules.lua',
    'game/scripts/tnr/multiplayer/replay_network.lua',
    'game/scripts/tnr/ui/tutorial_pages.lua',
    'game/scripts/tnr/ui/weapon_preview.lua'
)
function Test-ExcludedGamePath([string]$path) {
    return $path -like 'game/assets/players/kud/*' -or
        $path -eq 'game/scripts/tnr/debug/replay_pilot.lua' -or
        $path -like 'game/userdata/*' -or $path -like 'game/legacy/virtual_data/*' -or
        $path -match '(?i)(\.log|\.dmp|\.result|\.bak|_smoke_result\.txt)$' -or
        $path -match '(?i)(^|/)(desktop\.ini|Thumbs\.db)$'
}
function Get-GitGameFiles([bool]$untrackedOnly) {
    # PowerShell 5 may decode native output with CP936 even when Git writes
    # UTF-8. Read Git's NUL-delimited output explicitly as UTF-8 so localized
    # filenames and embedded whitespace are preserved on any console codepage.
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = 'git'
    $start.Arguments = '-C "' + $projectRoot + '" ls-files -z ' +
        $(if ($untrackedOnly) { '--others --exclude-standard ' } else { '' }) + '-- game'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $process = [Diagnostics.Process]::Start($start)
    try {
        $output = $process.StandardOutput.ReadToEnd()
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "Git file enumeration failed: $errorText" }
        return @($output.Split([char]0) | Where-Object { $_ -ne '' })
    } finally { $process.Dispose() }
}
$tracked = @(Get-GitGameFiles $false)
$untracked = @(Get-GitGameFiles $true)
$unexpected = @($untracked | Where-Object { -not (Test-ExcludedGamePath $_) -and $_ -notin $approvedNewFiles })
if ($unexpected.Count -gt 0) {
    throw ('Review untracked game files before packaging: ' + ($unexpected -join ', '))
}
$files = @(($tracked + $approvedNewFiles | Where-Object { -not (Test-ExcludedGamePath $_) }) | Sort-Object -Unique)
$gamePrefix = [IO.Path]::GetFullPath($gameRoot).TrimEnd('\') + '\'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach ($relative in $files) {
    if ($relative -notmatch '^game/' -or $relative.StartsWith('"')) { throw "Unsupported Git path: $relative" }
    $source = [IO.Path]::GetFullPath((Join-Path $projectRoot $relative))
    if (-not $source.StartsWith($gamePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Game path escapes the project: $relative" }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Required game file missing: $relative" }
    $fileItem = Get-Item -LiteralPath $source -Force
    if (($fileItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Game file is a filesystem link: $relative" }
    # FileInfo has Directory, not Parent. Starting at Parent silently skips
    # all directories on PowerShell 5 and can follow an external junction.
    $item = $fileItem.Directory
    while ($item -and $item.FullName.Length -ge $gameRoot.Length) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Game path contains a filesystem link: $relative" }
        if ($item.FullName -eq $gameRoot) { break }
        $item = $item.Parent
    }
    $output = Join-Path $destination ($relative.Substring(5))
    $parent = Split-Path -Parent $output
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::Copy($source, $output, $false)
}
foreach ($name in $binaryFiles) {
    $outputName = if ($name -eq 'LuaSTGSub.exe') { 'TouHouNightReign.exe' } else { $name }
    Copy-Item -LiteralPath (Join-Path $binaryRoot $name) -Destination (Join-Path $destination $outputName)
}
Copy-Item -LiteralPath (Join-Path $EngineRoot 'data/license') -Destination (Join-Path $destination 'licenses') -Recurse
Copy-Item -LiteralPath (Join-Path $EngineRoot 'License.txt') -Destination (Join-Path $destination 'licenses/LuaSTG-Sub-License.txt')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'release_readme.txt') -Destination (Join-Path $destination 'README.txt')
$validationRoot = Join-Path $destination 'validation'
New-Item -ItemType Directory -Path $validationRoot -Force | Out-Null
foreach ($report in @('native-card-audit.md', 'native-card-audit-results.tsv', 'stage1-validation.md')) {
    $reportPath = Join-Path $projectRoot ('docs/' + $report)
    if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
        Copy-Item -LiteralPath $reportPath -Destination (Join-Path $validationRoot $report)
    }
}
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
    source_commit = (& git -C $projectRoot rev-parse HEAD)
    platform = 'Windows x64'
    configuration = 'Release'
    engine_sha256 = Get-ReleaseSha256 (Join-Path $destination 'TouHouNightReign.exe')
    contents = 'Reviewed tracked game files and approved replay additions; excludes player saves, diagnostics and unrelated work.'
}
$metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'release-info.json') -Encoding UTF8
$hashLines = Get-ChildItem -LiteralPath $destination -Recurse -File | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($destination.Length + 1).Replace('\', '/')
    '{0}  {1}' -f (Get-ReleaseSha256 $_.FullName), $relative
}
[IO.File]::WriteAllLines((Join-Path $destination 'SHA256SUMS.txt'), [string[]]$hashLines, (New-Object Text.UTF8Encoding($false)))
if (-not $SkipArchive) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($destination, $archive, [IO.Compression.CompressionLevel]::Optimal, $true)
    $zipHash = Get-ReleaseSha256 $archive
    "$zipHash  $ReleaseName.zip" | Set-Content -LiteralPath "$archive.sha256" -Encoding ASCII
    Write-Output "Archive: $archive"
}
Write-Output "Release folder: $destination"
