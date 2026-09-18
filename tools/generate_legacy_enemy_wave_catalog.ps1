param(
    [string]$Source = "E:\gemesmods\stg\_reference_extract_20260827\activity7\_editor_output.lua",
    [string]$Output = "E:\gemesmods\stg\TouHouNightReign\game\scripts\tnr\stages\legacy_enemy_waves.lua"
)

if (-not (Test-Path -LiteralPath $Source)) {
    throw "Reference source not found: $Source"
}

$lines = Get-Content -LiteralPath $Source -Encoding UTF8
$enemyClasses = @{}
$bossClasses = @{}
foreach ($line in $lines) {
    if ($line -match '_editor_class\["([^"]+)"\]=Class\(enemy\)') {
        $enemyClasses[$Matches[1]] = $true
    }
    if ($line -match '_editor_class\["([^"]+)"\]=Class\(boss\)') {
        $bossClasses[$Matches[1]] = $true
    }
}

function Convert-LuaString([string]$value) {
    return $value.Replace('\\', '\\\\').Replace('"', '\\"')
}

function Convert-StageKey([string]$value) {
    $key = $value.ToLowerInvariant() -replace '[^a-z0-9]+', '_'
    $key = $key.Trim('_')
    if ([string]::IsNullOrWhiteSpace($key)) { $key = 'stage' }
    return $key
}

function Split-LuaArgs([string]$value) {
    $result = @()
    $start = 0
    $depth = 0
    $quote = $null
    for ($i = 0; $i -lt $value.Length; $i++) {
        $char = $value[$i]
        if ($quote -ne $null) {
            if ($char -eq $quote -and ($i -eq 0 -or $value[$i - 1] -ne '\')) { $quote = $null }
            continue
        }
        if ($char -eq '"' -or $char -eq "'") { $quote = $char; continue }
        if ($char -eq '(' -or $char -eq '{' -or $char -eq '[') { $depth++; continue }
        if ($char -eq ')' -or $char -eq '}' -or $char -eq ']') { $depth--; continue }
        if ($char -eq ',' -and $depth -eq 0) {
            $result += $value.Substring($start, $i - $start).Trim()
            $start = $i + 1
        }
    }
    if ($start -lt $value.Length) { $result += $value.Substring($start).Trim() }
    return @($result | Where-Object { $_ -ne '' })
}

function Get-NewCallArgs([string]$line) {
    $match = [regex]::Match($line, 'New\(_editor_class\["([^"]+)"\],(.*)\)')
    if (-not $match.Success) { return @() }
    return Split-LuaArgs $match.Groups[2].Value
}

$stages = @()
$current = $null
$pending = @()
$pendingFrames = 0
$segmentFrames = 0
$waveIndex = 0
$scope = @{}

function Flush-Wave {
    if ($script:current -eq $null -or $script:pending.Count -eq 0) { return }
    $counts = @{}
    foreach ($member in $script:pending) {
        if (-not $counts.ContainsKey($member.class_name)) { $counts[$member.class_name] = 0 }
        $counts[$member.class_name]++
    }
    $classes = @($counts.Keys | Sort-Object)
    $script:waveIndex++
    $script:current.waves += [pscustomobject]@{
        index = $script:waveIndex
        name = "$($script:current.name) Wave $($script:waveIndex)"
        duration_frames = [int]$script:pendingFrames
        segment = [int]$script:current.segment
        classes = $classes
        members = @($script:pending)
    }
    $script:pending = @()
    $script:pendingFrames = 0
}

foreach ($line in $lines) {
    if ($line -match "stage\.group\.DefStageFunc\('([^']+)'\s*,\s*'init'") {
        Flush-Wave
        if ($current -ne $null) { $stages += $current }
        $current = [pscustomobject]@{
            name = $Matches[1]
            waves = @()
            segment = 0
        }
        $pending = @()
        $pendingFrames = 0
        $segmentFrames = 0
        $waveIndex = 0
        $scope = @{}
        continue
    }
    if ($current -eq $null) { continue }
    if ($line -match "stage\.group\.(AddStage|DefStageFunc)\(") {
        Flush-Wave
        $stages += $current
        $current = $null
        continue
    }

    # The original stage function changes from ordinary enemies to an
    # interlude/mid-boss at this point. Keep all enemy spawns before and after
    # that boundary as two selectable waves instead of splitting on every
    # internal wait. Boss objects themselves are never added to the catalog.
    if ($line -match '_editor_class\["([^"]+)"\]' -and $bossClasses.ContainsKey($Matches[1])) {
        Flush-Wave
        # A stage may contain several short mid-bosses. They all belong to the
        # same post-mid-boss enemy section, so only the first boss switches
        # segments and resets that section's relative clock.
        if ($current.segment -eq 0) {
            $current.segment = 1
            $segmentFrames = 0
        }
        continue
    }

    # Preserve simple loop-local numeric values used by the original calls
    # (for example local X=(-170), then X=X+25). These are source parameters,
    # not generated compatibility coordinates.
    if ($line -match 'local\s+([A-Za-z_][A-Za-z0-9_]*)[^=]*=\((-?\d+(?:\.\d+)?)\)') {
        $scope[$Matches[1]] = $Matches[2]
    }
    if ($line -match 'local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(-?\d+(?:\.\d+)?)') {
        $scope[$Matches[1]] = $Matches[2]
    }
    # The reference scripts frequently initialize a loop-local pair in one
    # statement, e.g. `local x,_d_x=(60*i),(-30*i)`. Preserve the first
    # expression so later enemy constructors retain their original x value.
    if ($line -match 'local\s+([A-Za-z_][A-Za-z0-9_]*)\s*,[^=]*=\s*\(([^()]*)\)') {
        $scope[$Matches[1]] = $Matches[2]
    }
    # Capture every parenthesized local pair on a compact source line. The
    # expressions may themselves contain one nested parenthesized term, such
    # as `162*(s%4-2)`.
    $localPairPattern = 'local\s+([A-Za-z_][A-Za-z0-9_]*)\s*,\s*[^=]+?=\s*\(((?:[^()]|\([^()]*\))*)\)'
    foreach ($localPair in [regex]::Matches($line, $localPairPattern)) {
        $scope[$localPair.Groups[1].Value] = $localPair.Groups[2].Value
    }
    if ($line -match '^\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$' -and $Matches[2] -cnotmatch '\blocal\b|\bNew\s*\(') {
        $scope[$Matches[1]] = $Matches[2]
    }
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\1\s*\+\s*(-?\d+(?:\.\d+)?)') {
        $name = $Matches[1]
        if ($scope.ContainsKey($name)) { $scope[$name] = ([double]$scope[$name] + [double]$Matches[2]).ToString([Globalization.CultureInfo]::InvariantCulture) }
    }

    if ($line -match '_editor_class\["([^"]+)"\]' -and $enemyClasses.ContainsKey($Matches[1])) {
        $className = $Matches[1]
        $args = @(Get-NewCallArgs $line)
        for ($argIndex = 0; $argIndex -lt $args.Count; $argIndex++) {
            $arg = $args[$argIndex]
            if ($scope.ContainsKey($arg)) { $args[$argIndex] = $scope[$arg] }
        }
        $pending += [pscustomobject]@{
            class_name = $className
            args = $args
            env = @{} + $scope
            spawn_frame = [int]$segmentFrames
            source = $line.Trim()
        }
        continue
    }

    if ($line -match 'task\._Wait\((\d+)\)') {
        $wait = [int]$Matches[1]
        $segmentFrames += $wait
        if ($pending.Count -gt 0) {
            $pendingFrames += $wait
            # Short waits are the spacing inside one formation. A longer wait
            # terminates the current wave, preserving the original order.
            if ($wait -ge 30) { Flush-Wave }
        }
    }
}
Flush-Wave
if ($current -ne $null) { $stages += $current }

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('-- Generated from the original activity7 stage functions.')
[void]$sb.AppendLine('-- Do not hand-edit: rerun tools/generate_legacy_enemy_wave_catalog.ps1.')
[void]$sb.AppendLine('-- Each member keeps the original enemy class identifier and source order.')
[void]$sb.AppendLine('-- Normal waves are difficulty 1-3; Lunatic waves are difficulty 4-6.')
[void]$sb.AppendLine('return {')

foreach ($stage in $stages) {
    if ($stage.waves.Count -eq 0) { continue }
    $stageKey = Convert-StageKey $stage.name
    [void]$sb.AppendLine(('    {{ id = "legacy_{0}", source_stage = "{1}", waves = {{' -f $stageKey, (Convert-LuaString $stage.name)))
    $grouped = @()
    foreach ($segment in @(0, 1)) {
        $members = @()
        $durationFrames = 0
        foreach ($wave in ($stage.waves | Where-Object { $_.segment -eq $segment })) {
            $durationFrames += [int]$wave.duration_frames
            $members += @($wave.members)
        }
        if ($members.Count -gt 0) {
            $firstFrame = ($members | ForEach-Object { [int]$_.spawn_frame } | Measure-Object -Minimum).Minimum
            foreach ($member in $members) {
                $member.spawn_frame = [int]$member.spawn_frame - [int]$firstFrame
            }
            $lastFrame = ($members | ForEach-Object { [int]$_.spawn_frame } | Measure-Object -Maximum).Maximum
            $durationFrames = [math]::Max($durationFrames, [int]$lastFrame + 1)
            # Very short fragments are setup/transition remnants rather than
            # useful practice targets. Keep the source data intact, but omit
            # grouped entries that are ten seconds or shorter from the
            # selectable catalog.
            $displayDuration = [math]::Round($durationFrames / 60.0, 1)
            if ($displayDuration -gt 10.0) {
                $grouped += [pscustomobject]@{ segment = $segment; members = $members; duration_frames = $durationFrames }
            }
        }
    }
    $total = $grouped.Count
    $groupIndex = 0
    foreach ($wave in $grouped) {
        $groupIndex++
        $isLunatic = $stage.name -match '@Lunatic$'
        $difficultyBase = 1
        if ($isLunatic) { $difficultyBase = 4 }
        if ($total -eq 1 -and $wave.segment -eq 0) {
            $difficulty = $difficultyBase + 1
            $label = "{0} Complete Enemy Run" -f $stage.name
        } elseif ($wave.segment -eq 0) {
            $difficulty = $difficultyBase
            $label = "{0} Before Mid-Boss" -f $stage.name
        } else {
            $difficulty = $difficultyBase + 2
            $label = "{0} After Mid-Boss" -f $stage.name
        }
        $duration = [math]::Round($wave.duration_frames / 60.0, 1)
        $classNames = @($wave.members | ForEach-Object { $_.class_name } | Sort-Object -Unique)
        [void]$sb.AppendLine(('        {{ id = "legacy_{0}_wave_{1:00}", name = "{2}", difficulty = {3}, duration_frames = {4}, duration_seconds = {5}, classes = {{' -f $stageKey, $groupIndex, (Convert-LuaString $label), $difficulty, $wave.duration_frames, $duration.ToString([Globalization.CultureInfo]::InvariantCulture)))
        foreach ($className in $classNames) {
            [void]$sb.AppendLine(('            "{0}",' -f (Convert-LuaString $className)))
        }
        [void]$sb.AppendLine('        }, members = {')
        foreach ($member in $wave.members) {
            [void]$sb.AppendLine(('            {{ class_name = "{0}", args = {{' -f (Convert-LuaString $member.class_name)))
            foreach ($arg in $member.args) {
                [void]$sb.AppendLine(('                "{0}",' -f (Convert-LuaString $arg)))
            }
            [void]$sb.AppendLine(('            }}, spawn_frame = {0}, env = {{' -f $member.spawn_frame))
            foreach ($key in ($member.env.Keys | Sort-Object)) {
                [void]$sb.AppendLine(('                {0} = "{1}",' -f $key, (Convert-LuaString ([string]$member.env[$key]))))
            }
            [void]$sb.AppendLine('            } },')
        }
        [void]$sb.AppendLine('        } },')
    }
    [void]$sb.AppendLine('    } },')
}
[void]$sb.AppendLine('}')

$parent = Split-Path -Parent $Output
New-Item -ItemType Directory -Force -Path $parent | Out-Null
[System.IO.File]::WriteAllText($Output, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Output "Generated $Output from $($stages.Count) stage functions."
