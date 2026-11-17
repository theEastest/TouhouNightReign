param([string]$EngineExe=(Join-Path $PSScriptRoot '../../LuaSTG-Sub-master/build/amd64/bin/LuaSTGSub.exe'),[switch]$Visual,[ValidateSet('classic','modern')][string]$Mode='classic',[ValidateRange(1,6)][int]$Stage=1,[switch]$Campaign)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$auditRoot=Join-Path $projectRoot ('.validation/replay-lan-'+$Mode+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $auditRoot -Force | Out-Null
# Reserve an available loopback port, then release it for the engine listener.
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
$listener.Start()
$port=$listener.LocalEndpoint.Port
$listener.Stop()
$processes=@()
try {
    foreach ($role in @('host','client')) {
        $testRoot=Join-Path $auditRoot $role
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        $config=Get-Content -LiteralPath (Join-Path $projectRoot 'game/config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($resource in $config.file_system.resources) {
            $resource.path=(Join-Path (Join-Path $projectRoot 'game') $resource.path).Replace('\','/')
        }
        $config.file_system.resources += [pscustomobject]@{name='game-root';type='directory';path=(Join-Path $projectRoot 'game').Replace('\','/')}
        $config.file_system.resources += [pscustomobject]@{name='audit';type='directory';path=$testRoot.Replace('\','/')}
        $config.window.title="Replay LAN audit - $role"
        if (-not $Visual) {
            $config.graphics_system.vsync=$false
            $config.timing.frame_rate=240
        }
        $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $testRoot 'config.json') -Encoding UTF8
        Copy-Item -LiteralPath (Join-Path $projectRoot 'tests/replay_lan_audit_runtime.lua') -Destination (Join-Path $testRoot 'main.lua')
        foreach ($entry in @(Get-ChildItem Env:TNR_*)) { [Environment]::SetEnvironmentVariable($entry.Name,$null,'Process') }
        $env:TNR_TEST_PROJECT_ROOT=$projectRoot
        $env:TNR_TEST_ROLE=$role
        $env:TNR_TEST_PORT="$port"
        $env:TNR_TEST_MODE=$Mode
        $env:TNR_TEST_STAGE="$Stage"
        if ($Campaign) { $env:TNR_TEST_CAMPAIGN='1' }
        if ($Visual) { $env:TNR_TEST_VISUAL='1' }
        $processes+=Start-Process -FilePath ([IO.Path]::GetFullPath($EngineExe)) -WorkingDirectory $testRoot -WindowStyle Hidden -PassThru
    }
    $deadline=(Get-Date).AddMinutes($(if ($Campaign) { 60 } else { 20 }))
    foreach ($process in $processes) {
        while (-not $process.WaitForExit(1000)) {
            if ((Get-Date) -gt $deadline) { throw "Audit timeout: $auditRoot" }
        }
    }
    $failed=@()
    foreach ($role in @('host','client')) {
        $result=Get-Content -LiteralPath (Join-Path $auditRoot "$role/replay-lan.result")
        $result
        if ($result -notcontains 'VERDICT=PASS') { $failed+=$role }
    }
    Write-Output "Evidence: $auditRoot"
    if ($failed.Count -gt 0) { throw "Audit failed: $($failed -join ', ')" }
} finally {
    foreach ($process in $processes) {
        $process.Refresh()
        if (-not $process.HasExited) { $process.Kill();$process.WaitForExit() }
    }
}
