# REGIX Studio Launcher – Python (pyinjector-free)
param(
    [string]$PythonInstallerUrl = "https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe",
    [string]$MainPyUrl = "https://raw.githubusercontent.com/official-jahid/bios-v2/refs/heads/main/main.py"
)

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "REGIX Studio Launcher (Python)"

function Show-Notification {
    param([string]$Title, [string]$Message, [string]$Type = "info")
    $color = if ($Type -eq "error") { "Red" } elseif ($Type -eq "success") { "Green" } else { "Cyan" }
    Write-Host "[$Type] $Message" -ForegroundColor $color
    try {
        $popup = New-Object -ComObject Wscript.Shell
        $icon = if ($Type -eq "error") { 16 } elseif ($Type -eq "success") { 64 } else { 64 }
        $popup.Popup($Message, 5, $Title, $icon + 4096) | Out-Null
    } catch {
        Add-Type -AssemblyName System.Windows.Forms
        $buttons = [System.Windows.Forms.MessageBoxButtons]::OK
        $icon = if ($Type -eq "error") { [System.Windows.Forms.MessageBoxIcon]::Error } else { [System.Windows.Forms.MessageBoxIcon]::Information }
        [System.Windows.Forms.MessageBox]::Show($Message, $Title, $buttons, $icon) | Out-Null
    }
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  REGIX Studio Launcher (Python - No injector)" -ForegroundColor Yellow
Write-Host "  Checks Python, installs deps, runs main.py from GitHub" -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ---- 1. Check for Python ----
Write-Host "[1] Checking Python installation..." -ForegroundColor Green
$pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pythonPath) {
    Write-Host "    Python not found. Installing Python 3.12.3..." -ForegroundColor Yellow
    Show-Notification -Title "REGIX Studio" -Message "Python not found. Installing..." -Type "info"
    $installer = "$env:TEMP\python_installer.exe"
    Write-Host "    Downloading installer..." -ForegroundColor Gray
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
            Show-Notification -Title "REGIX Studio" -Message "Python installation failed." -Type "error"
            Read-Host "Press Enter to exit"
            exit 1
        }
    }
    Write-Host "    Python installed successfully at: $pythonPath" -ForegroundColor Green
} else {
    Write-Host "    Python found at: $pythonPath" -ForegroundColor Green
}

# ---- 2. Install required packages (pyinjector বাদ) ----
Write-Host "[2] Installing/checking required Python packages..." -ForegroundColor Green
$packages = @(
    @{Name="pymem"; Module="pymem"},
    @{Name="psutil"; Module="psutil"},
    @{Name="pywin32"; Module="win32security"},
    @{Name="keyboard"; Module="keyboard"}
)

Write-Host "    Upgrading pip..." -ForegroundColor Gray
& $pythonPath -m pip install --upgrade pip --quiet --disable-pip-version-check 2>&1 | Out-Null

foreach ($pkg in $packages) {
    Write-Host "    Checking $($pkg.Name) ..." -ForegroundColor Gray -NoNewline
    $check = & $pythonPath -c "import $($pkg.Module)" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host " NOT FOUND, installing..." -ForegroundColor Yellow
        $install = & $pythonPath -m pip install $pkg.Name --quiet --disable-pip-version-check 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`n    [ERROR] Failed to install $($pkg.Name)." -ForegroundColor Red
            Write-Host "    Error: $install" -ForegroundColor Gray
            Show-Notification -Title "REGIX Studio" -Message "Failed to install $($pkg.Name)." -Type "error"
            Read-Host "Press Enter to exit"
            exit 1
        }
        Write-Host "    Installed successfully." -ForegroundColor Green
    } else {
        Write-Host " OK." -ForegroundColor Green
    }
}

# ---- 3. Download main.py ----
Write-Host "[3] Downloading main.py from GitHub..." -ForegroundColor Green
$mainPyLocal = "$env:TEMP\main.py"
try {
    Invoke-WebRequest -Uri $MainPyUrl -OutFile $mainPyLocal -UseBasicParsing
    Write-Host "    Downloaded to: $mainPyLocal" -ForegroundColor Gray
} catch {
    Write-Host "    [ERROR] Failed to download main.py: $_" -ForegroundColor Red
    Show-Notification -Title "REGIX Studio" -Message "Failed to download main.py." -Type "error"
    Read-Host "Press Enter to exit"
    exit 1
}

# ---- 4. Run main.py in background (hidden) ----
Write-Host "[4] Starting main.py in background..." -ForegroundColor Green
try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $pythonPath
    $psi.Arguments = "`"$mainPyLocal`""
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    Write-Host "    Process started with PID: $($p.Id)" -ForegroundColor Green
    Show-Notification -Title "REGIX Studio" -Message "REGIX Studio is running.`nHotkeys: F3=aimbot ON, F4=OFF, F5=drag ON, F6=OFF, F8=cleanup" -Type "success"
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  REGIX Studio is running!" -ForegroundColor Yellow
    Write-Host "  Hotkeys: F3=aimbot ON, F4=OFF, F5=drag ON, F6=OFF, F8=cleanup" -ForegroundColor Cyan
    Write-Host "  You can close this PowerShell window (Ctrl+C or close button)." -ForegroundColor Gray
    Write-Host "  The Python process (PID: $($p.Id)) will continue running." -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor Cyan
    while ($true) { Start-Sleep -Seconds 1 }
} catch {
    Write-Host "    [ERROR] Failed to start Python process: $_" -ForegroundColor Red
    Show-Notification -Title "REGIX Studio" -Message "Failed to start REGIX Studio." -Type "error"
    Read-Host "Press Enter to exit"
    exit 1
}
