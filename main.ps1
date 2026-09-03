# main.ps1 – REGIX Studio Launcher (verbose, debug-friendly)
param(
    [string]$PythonInstallerUrl = "https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe",
    [string]$MainPyUrl = "https://raw.githubusercontent.com/official-jahid/bios-v2/refs/heads/main/main.py"
)

$ErrorActionPreference = "Continue"  # ত্রুটি দেখাতে Continue, কিন্তু থামবে না
$Host.UI.RawUI.WindowTitle = "REGIX Studio Launcher"

# ---- হেল্পার: হিডেন প্রসেস চালানো ----
function Start-HiddenProcess {
    param([string]$FilePath, [string]$Arguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    $null = [System.Diagnostics.Process]::Start($psi)
}

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  REGIX Studio Launcher - Setup & Run" -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# ---- ০. নেটওয়ার্ক প্রটোকল ----
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---- ১. পাইথন চেক ----
Write-Host "[1] Checking Python installation..." -ForegroundColor Green
$pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pythonPath) {
    Write-Host "    Python not found. Installing Python 3.12.3..." -ForegroundColor Yellow
    $installer = "$env:TEMP\python_installer.exe"
    Write-Host "    Downloading installer from $PythonInstallerUrl ..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $PythonInstallerUrl -OutFile $installer -UseBasicParsing
    Write-Host "    Running silent install (may take a few minutes)..." -ForegroundColor Gray
    Start-Process -FilePath $installer -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait -WindowStyle Hidden
    Remove-Item $installer -Force
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    $pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $pythonPath) {
        $pythonPath = "$env:ProgramFiles\Python312\python.exe"
        if (-not (Test-Path $pythonPath)) {
            Write-Host "    [ERROR] Python installation failed!" -ForegroundColor Red
            Read-Host "Press Enter to exit"
            exit 1
        }
    }
    Write-Host "    Python installed successfully at: $pythonPath" -ForegroundColor Green
} else {
    Write-Host "    Python found at: $pythonPath" -ForegroundColor Green
}

# ---- ২. পাইথন ডিপেন্ডেন্সি (সঠিক নাম) ----
Write-Host "[2] Checking required Python packages..." -ForegroundColor Green
$dependencies = @(
    @{ Name = "pymem";       Module = "pymem" },
    @{ Name = "psutil";      Module = "psutil" },
    @{ Name = "pywin32";     Module = "win32security" },
    @{ Name = "keyboard";    Module = "keyboard" },
    @{ Name = "pyinjector";  Module = "pyinjector" }   # সঠিক নাম
)

Write-Host "    Upgrading pip..." -ForegroundColor Gray
& $pythonPath -m pip install --upgrade pip --quiet --disable-pip-version-check 2>&1 | Out-Null

foreach ($dep in $dependencies) {
    Write-Host "    Checking $($dep.Name) ..." -ForegroundColor Gray -NoNewline
    $check = & $pythonPath -c "import $($dep.Module)" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host " NOT FOUND, installing..." -ForegroundColor Yellow
        $install = & $pythonPath -m pip install $dep.Name --quiet --disable-pip-version-check 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`n    [ERROR] Failed to install $($dep.Name). Error: $install" -ForegroundColor Red
            # চালিয়ে যান, কিন্তু ম্যানুয়ালি করতে হতে পারে
        } else {
            Write-Host "    Installed successfully." -ForegroundColor Green
        }
    } else {
        Write-Host " OK." -ForegroundColor Green
    }
}

# ---- ৩. main.py ডাউনলোড ও রান ----
Write-Host "[3] Downloading main.py from $MainPyUrl ..." -ForegroundColor Green
try {
    $webClient = New-Object System.Net.WebClient
    $scriptContent = $webClient.DownloadString($MainPyUrl)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($scriptContent)
    $b64 = [Convert]::ToBase64String($bytes)
    Write-Host "    Downloaded and encoded (length: $($b64.Length) chars)." -ForegroundColor Gray

    Write-Host "    Starting Python process (background) ..." -ForegroundColor Gray
    $cmd = "-c ""import base64, os, sys; sys.stdout = open(os.devnull, 'w') if os.name == 'nt' else sys.stdout; sys.stderr = open(os.devnull, 'w') if os.name == 'nt' else sys.stderr; exec(base64.b64decode('$b64').decode('utf-8'))"""
    Start-HiddenProcess -FilePath $pythonPath -Arguments $cmd
    Write-Host "    Python process started successfully." -ForegroundColor Green
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "  Setup complete! Main program is running." -ForegroundColor Yellow
    Write-Host "  Hotkeys: F3=aimbot ON, F4=OFF, F5=drag ON, F6=OFF, F8=cleanup" -ForegroundColor Cyan
    Write-Host "  Press Ctrl+C in this window to exit (launcher will close)." -ForegroundColor Gray
    Write-Host "  (The Python process will continue running in background.)" -ForegroundColor Gray
    Write-Host "==============================================" -ForegroundColor Cyan
    while ($true) { Start-Sleep -Seconds 1 }
} catch {
    Write-Host "    [ERROR] Failed to download or run main.py: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
