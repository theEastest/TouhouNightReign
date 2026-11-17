param([int]$Stage=1,[int]$PreviewFrame=0,[ValidateRange(0,3)][int]$Difficulty=1,
    [ValidateSet('classic','modern')][string]$Mode='classic')
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$auditRoot=Join-Path $projectRoot ('.validation/render-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $auditRoot | Out-Null
$config=Get-Content -LiteralPath (Join-Path $projectRoot 'game/config.json') -Raw|ConvertFrom-Json
foreach($resource in $config.file_system.resources){$resource.path=(Join-Path (Join-Path $projectRoot 'game') $resource.path).Replace('\','/')}
$config.file_system.resources += [pscustomobject]@{name='game-root';type='directory';path=(Join-Path $projectRoot 'game').Replace('\','/')}
$config.file_system.resources += [pscustomobject]@{name='audit';type='directory';path=$auditRoot.Replace('\','/')}
$config.window.title=if($PreviewFrame -gt 0){"TH15 preview - stage $Stage - difficulty $Difficulty - frame $PreviewFrame"}else{'Six-stage rendering audit'}
if ($PreviewFrame -eq 0) {
    $config.graphics_system.vsync=$false
    $config.timing.frame_rate=240
}
$config|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $auditRoot 'config.json') -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $projectRoot 'tests/replay_render_audit_runtime.lua') -Destination (Join-Path $auditRoot 'main.lua')
$env:TNR_TEST_PROJECT_ROOT=$projectRoot
$env:TNR_TEST_STAGE="$Stage"
$env:TNR_TEST_PREVIEW_FRAME="$PreviewFrame"
$env:TNR_TEST_DIFFICULTY="$Difficulty"
$env:TNR_TEST_MODE=$Mode
$exe=[IO.Path]::GetFullPath((Join-Path $projectRoot '../LuaSTG-Sub-master/build/amd64/bin/LuaSTGSub.exe'))
$process=Start-Process -FilePath $exe -WorkingDirectory $auditRoot -WindowStyle Hidden -PassThru
Write-Output "Evidence: $auditRoot"
try{
    $deadline=(Get-Date).AddMinutes(20)
    while(-not $process.WaitForExit(1000)){if((Get-Date) -gt $deadline){throw 'Rendering diagnostic timed out'}}
    $result=Get-Content -LiteralPath (Join-Path $auditRoot 'render-audit.txt')
    $result
    if($PreviewFrame -gt 0){
        if($result -notcontains "PREVIEW $Stage $PreviewFrame"){throw 'Preview frame was not reached'}
        Write-Output 'Preview closed; visual inspection is separate from diagnostic acceptance.'
    }elseif($result -notcontains 'RENDER_DIAGNOSTIC_PASS'){throw 'Rendering diagnostic failed'}
}finally{$process.Refresh();if(-not $process.HasExited){$process.Kill();$process.WaitForExit()}}
