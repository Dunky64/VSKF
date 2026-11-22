# The Driveway Butler - update to the latest code. Started by update.bat.
. (Join-Path $PSScriptRoot 'common.ps1')

$Owner = 'Dunky64'; $Repo = 'VSKF'
$Branch = (Get-Content (Join-Path $PcDir 'branch.txt') -Raw).Trim()

try {
    Write-Step 'Getting the latest code from GitHub'
    $git = Get-RepoGitExe
    if ((Test-Path (Join-Path $RepoRoot '.git')) -and $git) {
        & $git -C $RepoRoot fetch origin $Branch
        & $git -C $RepoRoot checkout $Branch
        & $git -C $RepoRoot pull --ff-only origin $Branch
        if ($LASTEXITCODE -ne 0) { throw 'git pull failed. Open GitHub Desktop and click "Pull origin" instead.' }
        Write-Ok 'Up to date (via git)'
    } else {
        $zip = Join-Path $env:TEMP 'driveway-butler-update.zip'
        $tmp = Join-Path $env:TEMP 'driveway-butler-update'
        $url = "https://github.com/$Owner/$Repo/archive/refs/heads/$Branch.zip"
        try { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing }
        catch { throw 'Could not download the update. If your GitHub repo is private, use GitHub Desktop (see docs\PC-SETUP.md) or download the ZIP again in your browser.' }
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $src = Get-ChildItem $tmp -Directory | Select-Object -First 1
        # Copy everything except this PC's own files (settings, logs, Python environment).
        robocopy $src.FullName $RepoRoot /E /XD (Join-Path $src.FullName 'pc\local') (Join-Path $src.FullName 'pc\.venv') /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Copying the new files failed (robocopy code $LASTEXITCODE)" }
        Write-Ok 'Up to date (via ZIP download)'
    }

    Write-Step 'Updating Python libraries'
    if (-not (Test-Path $VenvPython)) { throw 'Python is not set up yet. Run setup.bat first.' }
    & $VenvPython -m pip install --quiet --disable-pip-version-check -r (Join-Path $PcDir 'requirements.txt')
    Write-Ok 'Done'

    Write-Step 'Restarting the worker'
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
            Where-Object { $_.CommandLine -match 'worker\.py' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
        Start-ScheduledTask -TaskName $TaskName
        Write-Ok 'Worker restarted'
    } else {
        Write-Info 'No worker installed yet. If this update adds one, run setup.bat once.'
    }
    Write-Host ''
    Write-Host '  UPDATE FINISHED.' -ForegroundColor Green
} catch {
    Write-Bad "Update stopped: $($_.Exception.Message)"
}
