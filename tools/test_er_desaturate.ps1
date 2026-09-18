param([string]$EngineExe = (Join-Path $PSScriptRoot '../../LuaSTG-Sub-master/build/amd64/bin/LuaSTGSub.exe'))
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testRoot = Join-Path $projectRoot ('.validation/er-desaturate-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$config = Get-Content -LiteralPath (Join-Path $projectRoot 'game/config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($resource in $config.file_system.resources) {
    $resource.path = (Join-Path (Join-Path $projectRoot 'game') $resource.path).Replace('\', '/')
}
$config.file_system.resources += [pscustomobject]@{ name='game-root'; type='directory'; path=(Join-Path $projectRoot 'game').Replace('\', '/') }
# Directory search paths are searched in reverse registration order.
$config.file_system.resources += [pscustomobject]@{ name='runtime-test'; type='directory'; path=$testRoot.Replace('\', '/') }
$config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $testRoot 'config.json') -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $projectRoot 'tests/er_desaturate_runtime.lua') -Destination (Join-Path $testRoot 'main.lua')
foreach ($entry in @(Get-ChildItem Env:TNR_*)) { [Environment]::SetEnvironmentVariable($entry.Name, $null, 'Process') }
$env:TNR_TEST_PROJECT_ROOT = $projectRoot
$process = Start-Process -FilePath ([IO.Path]::GetFullPath($EngineExe)) -WorkingDirectory $testRoot -WindowStyle Hidden -PassThru
try {
    if (-not $process.WaitForExit(55000)) { throw "Runtime test timed out. See $testRoot/engine.log" }
    if ($process.ExitCode -ne 0) { throw "Engine exited with code $($process.ExitCode). See $testRoot/engine.log" }
    $result = Get-Content -LiteralPath (Join-Path $testRoot 'er_desaturate.result') -Raw
    if (-not $result.StartsWith('passed')) { throw $result }
    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object Drawing.Bitmap((Join-Path $testRoot 'mask-test.png'))
    try {
        $gray = $bitmap.GetPixel([int]($bitmap.Width / 4), [int]($bitmap.Height / 2))
        $expectedGray = 40 * 0.30 + 120 * 0.59 + 200 * 0.11
        foreach ($channel in @($gray.R, $gray.G, $gray.B)) {
            if ([math]::Abs($channel - $expectedGray) -gt 2) { throw "Masked luminance incorrect: $gray" }
        }
        foreach ($y in @([int]($bitmap.Height / 4), [int]($bitmap.Height * 3 / 4))) {
            $color = $bitmap.GetPixel([int]($bitmap.Width * 3 / 4), $y)
            if ([math]::Abs($color.R - 40) -gt 2 -or [math]::Abs($color.G - 120) -gt 2 -or [math]::Abs($color.B - 200) -gt 2) {
                throw "Unmasked color changed: $color"
            }
        }
    } finally { $bitmap.Dispose() }
    Write-Output $result
    Write-Output 'GPU pixel checks passed: white mask desaturates; black and red masks preserve color.'
    Write-Output "Evidence: $testRoot"
} finally {
    $process.Refresh()
    if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
}
