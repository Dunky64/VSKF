# The Driveway Butler - PC setup. Started by setup.bat. Safe to run again at any time.
. (Join-Path $PSScriptRoot 'common.ps1')

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
Start-Transcript -Path (Join-Path $LogDir "setup-$stamp.log") | Out-Null
$problems = New-Object System.Collections.Generic.List[string]

try {
    Write-Host ''
    Write-Host '  THE DRIVEWAY BUTLER - PC SETUP' -ForegroundColor White
    Write-Host '  This takes 10-30 minutes, mostly downloading the AI model (about 6 GB).'
    Write-Host '  You can leave it running. Do not close this window.'

    # Files downloaded from the internet are "blocked" by Windows. Unblock ours so they can run.
    Get-ChildItem $RepoRoot -Recurse -File -Include *.ps1, *.bat, *.py -ErrorAction SilentlyContinue |
        Unblock-File -ErrorAction SilentlyContinue

    # 1. Windows -----------------------------------------------------------------------------
    Write-Step 'Step 1 of 8: Checking Windows'
    $win = Get-WindowsInfo
    if ($win.IsWin11) { Write-Ok "$($win.Caption) (build $($win.Build))" }
    else { Write-Warn "$($win.Caption) (build $($win.Build)). Windows 11 is recommended."; $problems.Add('Not Windows 11') }

    # 2. Graphics card -----------------------------------------------------------------------
    Write-Step 'Step 2 of 8: Checking the graphics card'
    $gpu = Get-AmdGpu
    if (-not $gpu) {
        Write-Bad 'No AMD Radeon graphics card found.'
        $problems.Add('No Radeon GPU detected')
    } else {
        Write-Ok "$($gpu.Name), $($gpu.VramGb) GB graphics memory"
        Write-Info "Driver $($gpu.DriverVersion), dated $($gpu.DriverDate.ToString('d MMM yyyy')), AMD Software $($gpu.Adrenalin)"
        if ($gpu.Name -notmatch '9070') { Write-Warn 'This is not an RX 9070. Setup will continue anyway.' }
        if ($gpu.DriverDate -lt [datetime]'2025-06-01') {
            Write-Warn 'Your graphics driver is old. Please update it: go to amd.com/support, download'
            Write-Info 'AMD Software: Adrenalin Edition, install it, restart the PC, then run setup.bat again.'
            $problems.Add('Graphics driver older than June 2025')
        }
    }

    # 3. Disk space --------------------------------------------------------------------------
    Write-Step 'Step 3 of 8: Checking disk space'
    $drive = Get-PSDrive -Name ($env:USERPROFILE.Substring(0, 1))
    $freeGb = [math]::Round($drive.Free / 1GB, 1)
    if ($freeGb -lt 15) { Write-Bad "Only $freeGb GB free on drive $($drive.Name):. At least 15 GB is needed."; throw 'Not enough disk space' }
    Write-Ok "$freeGb GB free on drive $($drive.Name):"

    # 4. Ollama ------------------------------------------------------------------------------
    Write-Step 'Step 4 of 8: Installing Ollama (runs the AI model)'
    Start-Ollama | Out-Null
    $ver = Get-OllamaVersion
    if ($ver -and $ver -ge $MinOllama) {
        Write-Ok "Ollama $ver is already installed and running"
    } else {
        if ($ver) { Write-Info "Ollama $ver is too old, updating it..." } else { Write-Info 'Downloading Ollama...' }
        $installer = Join-Path $env:TEMP 'OllamaSetup.exe'
        Invoke-WebRequest -Uri $OllamaUrl -OutFile $installer -UseBasicParsing
        Write-Info 'Installing (a window may flash up, that is normal)...'
        Get-Process -Name 'ollama app', 'ollama' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        $p = Start-Process -FilePath $installer -ArgumentList '/VERYSILENT', '/NORESTART', '/SUPPRESSMSGBOXES' -Wait -PassThru
        if ($p.ExitCode -ne 0) { throw "Ollama installer failed (exit code $($p.ExitCode))" }
        if (-not (Start-Ollama)) { throw 'Ollama was installed but did not start' }
        Write-Ok "Ollama $(Get-OllamaVersion) installed and running"
    }
    $compute = Get-OllamaComputeLine
    if ($compute) { Write-Info "Ollama says: $($compute -replace '^.*?msg=','')" }

    # 5. AI model ----------------------------------------------------------------------------
    Write-Step "Step 5 of 8: Downloading the AI model $Model (about 6 GB, this is the slow part)"
    & (Get-OllamaExe) pull $Model
    if ($LASTEXITCODE -ne 0) { throw "Could not download $Model" }
    Write-Ok "$Model is ready"

    # 6. Python ------------------------------------------------------------------------------
    Write-Step 'Step 6 of 8: Installing Python and the worker libraries'
    $python = Find-Python
    if (-not $python) {
        Write-Info 'Downloading Python 3.12...'
        $pyInstaller = Join-Path $env:TEMP 'python-3.12.10-amd64.exe'
        Invoke-WebRequest -Uri $PythonUrl -OutFile $pyInstaller -UseBasicParsing
        $p = Start-Process -FilePath $pyInstaller -ArgumentList '/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_test=0', 'Include_launcher=1' -Wait -PassThru
        if ($p.ExitCode -ne 0) { throw "Python installer failed (exit code $($p.ExitCode))" }
        $python = Find-Python
        if (-not $python) { throw 'Python was installed but cannot be found' }
    }
    Write-Ok "Python: $python"
    if (-not (Test-Path $VenvPython)) { & $python -m venv $VenvDir; if ($LASTEXITCODE -ne 0) { throw 'Could not create the Python environment' } }
    & $VenvPython -m pip install --quiet --disable-pip-version-check --upgrade pip
    & $VenvPython -m pip install --quiet --disable-pip-version-check -r (Join-Path $PcDir 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Could not install the Python libraries' }
    Write-Ok 'Libraries installed'

    # 7. GPU test ----------------------------------------------------------------------------
    Write-Step 'Step 7 of 8: Testing the AI on 5 driveway photos'
    $before = Get-GpuMemoryUsedGb
    & $VenvPython (Join-Path $PcDir 'gpu_test.py') $Model
    $testCode = $LASTEXITCODE
    $after = Get-GpuMemoryUsedGb
    if ($after -ne $null) { Write-Info "Graphics memory in use: $after GB (was $before GB before the test)" }

    if ($testCode -ne 0) {
        Write-Warn 'The AI is not running fully on the graphics card. Trying the backup method (Vulkan)...'
        [Environment]::SetEnvironmentVariable('OLLAMA_VULKAN', '1', 'User')
        $env:OLLAMA_VULKAN = '1'
        if (-not (Restart-Ollama)) { throw 'Ollama did not restart' }
        & $VenvPython (Join-Path $PcDir 'gpu_test.py') $Model
        if ($LASTEXITCODE -eq 0) {
            Write-Ok 'The backup method works. Ollama will use Vulkan from now on.'
        } else {
            [Environment]::SetEnvironmentVariable('OLLAMA_VULKAN', $null, 'User')
            Remove-Item Env:\OLLAMA_VULKAN -ErrorAction SilentlyContinue
            Restart-Ollama | Out-Null
            Write-Bad 'The AI still is not using the graphics card.'
            $problems.Add('AI not running on the GPU')
        }
    }

    # 8. Worker autostart --------------------------------------------------------------------
    Write-Step 'Step 8 of 8: Home worker'
    $workerBat = Join-Path $PcDir 'run_worker.bat'
    if (Test-Path $workerBat) {
        $action  = New-ScheduledTaskAction -Execute $workerBat -WorkingDirectory $PcDir
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
            -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
        Start-ScheduledTask -TaskName $TaskName
        Write-Ok 'The worker starts with Windows and is running now'
    } else {
        Write-Info 'Not built yet (that is Milestone B). Nothing to do.'
    }

    $topic = Get-NtfyTopic
} catch {
    Write-Bad "Setup stopped: $($_.Exception.Message)"
    $problems.Add("Stopped: $($_.Exception.Message)")
} finally {
    Write-Host ''
    Write-Host '==================================================================' -ForegroundColor White
    if ($problems.Count -eq 0) {
        Write-Host '  SETUP FINISHED. Everything looks good.' -ForegroundColor Green
    } else {
        Write-Host '  SETUP FINISHED WITH PROBLEMS:' -ForegroundColor Yellow
        $problems | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
    }
    Write-Host ''
    if ($topic) { Write-Host "  Your phone alert topic (for the ntfy app): $topic" -ForegroundColor Cyan }
    Write-Host '  NEXT: double-click diagnose.bat and send the report to Claude.'
    Write-Host '==================================================================' -ForegroundColor White
    Stop-Transcript | Out-Null
}
