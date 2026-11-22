# The Driveway Butler - diagnostic report. Started by diagnose.bat.
# Prints a short report, saves it, copies it to the clipboard and sends it to your phone (ntfy).
. (Join-Path $PSScriptRoot 'common.ps1')
$ErrorActionPreference = 'Continue'   # a report should never stop half way

$lines = New-Object System.Collections.Generic.List[string]
function Add([string]$s) { $lines.Add($s) }

Write-Host 'Collecting the report, this takes about a minute...' -ForegroundColor Cyan

Add "DRIVEWAY BUTLER DIAGNOSE  $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$win = Get-WindowsInfo
Add "Windows: $($win.Caption) build $($win.Build)"

$gpu = Get-AmdGpu
if ($gpu) {
    Add "GPU: $($gpu.Name), $($gpu.VramGb) GB, driver $($gpu.DriverVersion) ($($gpu.DriverDate.ToString('yyyy-MM-dd'))), AMD Software $($gpu.Adrenalin)"
} else {
    $all = (Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name }) -join '; '
    Add "GPU: NO RADEON FOUND. Cards seen: $all"
}
$drive = Get-PSDrive -Name ($env:USERPROFILE.Substring(0, 1))
Add "Disk free: $([math]::Round($drive.Free / 1GB, 1)) GB on $($drive.Name):"

# Ollama -----------------------------------------------------------------------------------
$started = Start-Ollama
$ver = Get-OllamaVersion
Add "Ollama: $(if ($ver) { "$ver running" } elseif (Get-OllamaExe) { 'installed but NOT running' } else { 'NOT installed' })"
$vulkan = [Environment]::GetEnvironmentVariable('OLLAMA_VULKAN', 'User')
Add "Vulkan backup mode: $(if ($vulkan -eq '1') { 'ON' } else { 'off' })"
$compute = Get-OllamaComputeLine
if ($compute) { Add "Ollama GPU line: $($compute -replace '^.*?msg=','')" } else { Add 'Ollama GPU line: (none found in server.log)' }
if ($ver) {
    try {
        $tags = (Invoke-RestMethod "$OllamaApi/api/tags" -TimeoutSec 10).models | ForEach-Object { $_.name }
        Add "Models downloaded: $(if ($tags) { $tags -join ', ' } else { 'none' })"
    } catch { Add 'Models downloaded: (could not ask Ollama)' }
}

# Quick live test -------------------------------------------------------------------------
if ($ver -and (Test-Path $VenvPython)) {
    $before = Get-GpuMemoryUsedGb
    $quickFile = Join-Path $LocalDir 'last_quick_test.json'
    Remove-Item $quickFile -ErrorAction SilentlyContinue
    & $VenvPython (Join-Path $PcDir 'gpu_test.py') $Model --count 1 *> $null
    $during = Get-GpuMemoryUsedGb
    if (Test-Path $quickFile) {
        $q = Get-Content $quickFile -Raw | ConvertFrom-Json
        $share = if ($q.gpu_share -ne $null) { "{0:P0}" -f [double]$q.gpu_share } else { 'unknown' }
        Add "Quick test (1 photo): $($q.avg_seconds_per_image) s/image, valid JSON $($q.valid_json)/1, model on GPU: $share ($($q.model_vram_gb) of $($q.model_total_gb) GB)"
        $err = @($q.rows | ForEach-Object { $_.errors }) | Where-Object { $_ } | Select-Object -First 2
        if ($err) { Add "Quick test errors: $($err -join ' | ')" }
    } else { Add 'Quick test: FAILED to run (see errors below)' }
    if ($during -ne $null) { Add "Graphics memory used: $during GB (before test: $before GB)" }
} else {
    Add 'Quick test: skipped (Ollama or Python not set up - run setup.bat first)'
}

$fullFile = Join-Path $LocalDir 'last_gpu_test.json'
if (Test-Path $fullFile) {
    $f = Get-Content $fullFile -Raw | ConvertFrom-Json
    $times = ($f.rows | ForEach-Object { if ($_.ok) { "$($_.seconds)" } else { 'X' } }) -join ', '
    Add "Last full test ($($f.when)): $($f.valid_json)/$($f.photos_tested) valid, avg $($f.avg_seconds_per_image) s/image [$times], load $($f.model_load_seconds) s, GPU share $($f.gpu_share)"
}

# Worker ----------------------------------------------------------------------------------
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    Add "Worker: $($task.State), last run $($info.LastRunTime), last result $($info.LastTaskResult)"
} else { Add 'Worker: not installed yet (Milestone B)' }
$hb = Join-Path $LocalDir 'last_heartbeat.txt'
if (Test-Path $hb) { Add "Worker last heartbeat: $((Get-Content $hb -Raw).Trim())" }

# Recent errors ---------------------------------------------------------------------------
$errs = New-Object System.Collections.Generic.List[string]
Get-OllamaErrors 3 | ForEach-Object { $errs.Add('ollama: ' + ($_ -replace '^.*?msg=', '')) }
$setupLog = Get-ChildItem $LogDir -Filter 'setup-*.log' -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
if ($setupLog) {
    Get-Content $setupLog.FullName | Where-Object { $_ -match '\[FAIL\]|\[WARN\]|Setup stopped' } |
        Select-Object -Last 5 | ForEach-Object { $errs.Add('setup: ' + $_.Trim()) }
}
$workerLog = Join-Path $LogDir 'worker.log'
if (Test-Path $workerLog) {
    Get-Content $workerLog -Tail 500 | Where-Object { $_ -match 'ERROR' } | Select-Object -Last 3 | ForEach-Object { $errs.Add('worker: ' + $_) }
}
if ($errs.Count) { Add 'Recent problems:'; $errs | ForEach-Object { Add ('  ' + $(if ($_.Length -gt 220) { $_.Substring(0, 220) + '...' } else { $_ })) } }
else { Add 'Recent problems: none' }

# Output ----------------------------------------------------------------------------------
$report = $lines -join "`r`n"
$reportFile = Join-Path $LocalDir 'diagnose-report.txt'
Set-Content -Path $reportFile -Value $report -Encoding UTF8
Write-Host ''
Write-Host $report
Write-Host ''
try { Set-Clipboard -Value $report; Write-Host 'Copied to the clipboard.' -ForegroundColor Green } catch {}

$topic = Get-NtfyTopic
$sent = $false
try {
    $body = if ($report.Length -gt 3900) { $report.Substring(0, 3900) } else { $report }
    Invoke-RestMethod -Method Post -Uri "https://ntfy.sh/$topic" -Body ([Text.Encoding]::UTF8.GetBytes($body)) `
        -Headers @{ Title = 'Driveway Butler diagnose report' } -TimeoutSec 15 | Out-Null
    $sent = $true
} catch {}
Write-Host ''
if ($sent) {
    Write-Host "Sent to your phone. In the ntfy app, subscribe to this topic to see it:  $topic" -ForegroundColor Green
} else {
    Write-Host 'Could not send it to your phone. The report is saved here:' -ForegroundColor Yellow
}
Write-Host "Saved to: $reportFile"
