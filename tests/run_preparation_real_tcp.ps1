$ErrorActionPreference = 'Stop'
$root = (Get-Location).Path
$exe = [IO.Path]::GetFullPath((Join-Path $root '../LuaSTG-Sub-master/build/amd64/bin/LuaSTGSub.exe'))
$run = Join-Path $root ('.validation/preparation-races-tcp/run-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $run -Force | Out-Null
$env:TNR_TEST_PROJECT_ROOT = $root
foreach ($scenario in @('pending', 'ids', 'capacity', 'race', 'shop_normal', 'shop_life', 'shop_equipment', 'shop_rejected', 'shop_pending_accept', 'shop_pending_reject', 'shop_mismatch_purchase', 'shop_mismatch_money', 'shop_mismatch_session_money', 'shop_mismatch_bomb', 'shop_mismatch_life', 'shop_mismatch_fragment', 'shop_mismatch_inventory', 'shop_mismatch_offer', 'shop_disconnect', 'reward_race', 'reward_unclaim_race', 'floor_pending1', 'floor_pending2', 'floor_both', 'floor_cross')) {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start(); $port = $listener.LocalEndpoint.Port; $listener.Stop()
    $env:TNR_TEST_PORT = "$port"; $env:TNR_TEST_SCENARIO = $scenario
    $procs = @()
    try {
        foreach ($role in @('host', 'client')) {
            $dirRole = Join-Path (Join-Path $run $scenario) $role
            New-Item -ItemType Directory -Path $dirRole -Force | Out-Null
            $cfg = Get-Content game/config.json -Raw | ConvertFrom-Json
            foreach ($resource in $cfg.file_system.resources) { $resource.path = (Join-Path (Join-Path $root 'game') $resource.path).Replace('\', '/') }
            $cfg.file_system.resources += [pscustomobject]@{name='game-root'; type='directory'; path=(Join-Path $root 'game').Replace('\', '/')}
            $cfg.file_system.resources += [pscustomobject]@{name='audit'; type='directory'; path=$dirRole.Replace('\', '/')}
            $cfg.file_system.user = (Join-Path $dirRole 'userdata').Replace('\', '/')
            $cfg.window.title = "Preparation TCP $scenario $role"; $cfg.graphics_system.vsync = $false; $cfg.timing.frame_rate = 240
            $cfg | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $dirRole 'config.json') -Encoding UTF8
            Copy-Item tests/preparation_real_tcp.lua (Join-Path $dirRole 'main.lua')
            $env:TNR_TEST_ROLE = $role
            $procs += Start-Process -FilePath $exe -WorkingDirectory $dirRole -WindowStyle Hidden -PassThru
        }
        foreach ($p in $procs) { if (-not $p.WaitForExit(50000)) { throw "Timed out: $scenario" } }
        foreach ($role in @('host', 'client')) {
            $file = Join-Path (Join-Path (Join-Path $run $scenario) $role) 'result.txt'
            if (-not (Test-Path $file)) { throw "Missing result: $scenario $role" }
            $result = Get-Content $file -Raw
            Write-Output "$scenario $role`n$result"
            if ($result -notmatch 'VERDICT=PASS' -or $result -match 'FAIL') { throw "Failed: $scenario $role" }
        }
    } finally {
        foreach ($p in $procs) { $p.Refresh(); if (-not $p.HasExited) { $p.Kill(); $p.WaitForExit() } }
    }
}
Write-Output "Results: $run"
