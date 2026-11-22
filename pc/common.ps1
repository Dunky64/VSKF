# Shared helpers for setup.ps1, update.ps1 and diagnose.ps1.
# Works with the Windows PowerShell 5.1 that comes with Windows 11. Keep this file ASCII-only.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # makes downloads much faster in PowerShell 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$PcDir      = Join-Path $RepoRoot 'pc'
$LocalDir   = Join-Path $PcDir 'local'          # machine-specific files, never uploaded to GitHub
$LogDir     = Join-Path $LocalDir 'logs'
$VenvDir    = Join-Path $PcDir '.venv'
$VenvPython = Join-Path $VenvDir 'Scripts\python.exe'
$Model      = 'qwen3-vl:8b'
$MinOllama  = [version]'0.12.7'                 # first Ollama version that runs Qwen3-VL
$OllamaApi  = 'http://127.0.0.1:11434'
$OllamaDir  = Join-Path $env:LOCALAPPDATA 'Programs\Ollama'
$OllamaLog  = Join-Path $env:LOCALAPPDATA 'Ollama\server.log'
$PythonUrl  = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe'
$OllamaUrl  = 'https://ollama.com/download/OllamaSetup.exe'
$TaskName   = 'DrivewayButlerWorker'

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Step($msg) { Write-Host ''; Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    [OK]   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    [WARN] $msg" -ForegroundColor Yellow }
function Write-Bad($msg)  { Write-Host "    [FAIL] $msg" -ForegroundColor Red }
function Write-Info($msg) { Write-Host "           $msg" }

function Get-WindowsInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    [pscustomobject]@{
        Caption = $os.Caption
        Build   = [int]$os.BuildNumber
        IsWin11 = ([int]$os.BuildNumber -ge 22000)
    }
}

function Get-AmdGpu {
    # Returns the Radeon card with driver details and real VRAM (WMI caps VRAM at 4 GB, so read the registry).
    $card = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'Radeon' } | Select-Object -First 1
    if (-not $card) { return $null }
    $vramGb = $null; $adrenalin = $null
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    Get-ChildItem $classKey -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($p -and $p.DriverDesc -eq $card.Name) {
            if ($p.'HardwareInformation.qwMemorySize') { $vramGb = [math]::Round([double]$p.'HardwareInformation.qwMemorySize' / 1GB, 1) }
            if ($p.RadeonSoftwareVersion) { $adrenalin = $p.RadeonSoftwareVersion }
        }
    }
    [pscustomobject]@{
        Name          = $card.Name
        DriverVersion = $card.DriverVersion
        DriverDate    = $card.DriverDate
        Adrenalin     = $adrenalin
        VramGb        = $vramGb
    }
}

function Get-GpuMemoryUsedGb {
    # Total graphics memory in use right now (all programs). English counter names; returns $null if unavailable.
    try {
        $s = (Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop).CounterSamples
        return [math]::Round((($s | Measure-Object CookedValue -Maximum).Maximum) / 1GB, 2)
    } catch { return $null }
}

function Get-OllamaExe {
    $exe = Join-Path $OllamaDir 'ollama.exe'
    if (Test-Path $exe) { return $exe }
    $cmd = Get-Command ollama.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-OllamaVersion {
    try {
        $v = (Invoke-RestMethod "$OllamaApi/api/version" -TimeoutSec 5).version -replace '[^0-9.].*$', ''
        return [version]$v
    } catch { return $null }
}

function Wait-Ollama([int]$Seconds = 60) {
    for ($i = 0; $i -lt $Seconds; $i++) {
        if (Get-OllamaVersion) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Start-Ollama {
    if (Get-OllamaVersion) { return $true }
    $app = Join-Path $OllamaDir 'ollama app.exe'
    if (Test-Path $app) { Start-Process -FilePath $app | Out-Null }
    else {
        $exe = Get-OllamaExe
        if (-not $exe) { return $false }
        Start-Process -FilePath $exe -ArgumentList 'serve' -WindowStyle Hidden | Out-Null
    }
    return (Wait-Ollama 60)
}

function Restart-Ollama {
    Get-Process -Name 'ollama app', 'ollama' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    return (Start-Ollama)
}

function Get-OllamaComputeLine {
    # Ollama writes which GPU library it picked into server.log, e.g. "inference compute ... library=ROCm ... name=..."
    if (-not (Test-Path $OllamaLog)) { return $null }
    $line = Get-Content $OllamaLog -Tail 3000 -ErrorAction SilentlyContinue |
        Where-Object { $_ -match 'inference compute|no compatible GPUs' } | Select-Object -Last 1
    return $line
}

function Get-OllamaErrors([int]$Count = 5) {
    if (-not (Test-Path $OllamaLog)) { return @() }
    return @(Get-Content $OllamaLog -Tail 3000 -ErrorAction SilentlyContinue |
        Where-Object { $_ -match 'level=ERROR' } | Select-Object -Last $Count)
}

function Find-Python {
    # Returns a path to Python 3.10+ or $null. Ignores the Microsoft Store placeholder.
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe')
    )
    $py = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($py) {
        try { $p = (& $py.Source -3 -c 'import sys; print(sys.executable)' 2>$null); if ($p) { $candidates += $p.Trim() } } catch {}
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c) -and ($c -notmatch 'WindowsApps')) {
            try {
                $ok = & $c -c 'import sys; print(sys.version_info >= (3, 10))' 2>$null
                if ($ok -and $ok.Trim() -eq 'True') { return $c }
            } catch {}
        }
    }
    return $null
}

function Get-NtfyTopic {
    $f = Join-Path $LocalDir 'ntfy_topic.txt'
    if (Test-Path $f) { return (Get-Content $f -Raw).Trim() }
    $chars = 'abcdefghjkmnpqrstuvwxyz23456789'.ToCharArray()
    $topic = 'dwb-' + (-join (1..10 | ForEach-Object { $chars | Get-Random }))
    Set-Content -Path $f -Value $topic -Encoding ASCII
    return $topic
}

function Get-RepoGitExe {
    # git from PATH, or the copy that GitHub Desktop ships with.
    $g = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    $gd = Join-Path $env:LOCALAPPDATA 'GitHubDesktop'
    if (Test-Path $gd) {
        $found = Get-ChildItem $gd -Directory -Filter 'app-*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'resources\app\git\cmd\git.exe' } | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($found) { return $found }
    }
    return $null
}
