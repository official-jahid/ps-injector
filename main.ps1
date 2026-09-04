# main.ps1 – Silent REGIX Studio Launcher with GitHub Gist SID Authorization
param(
    [string]$GistUrl = "https://gist.githubusercontent.com/official-jahid/dade88889d20679a7c54636d216bdb48/raw/eea2d85f06eb623dd0fa2cbdc61e27a4a9dc3918/allowed_sid.json",
    [string]$PythonInstallerUrl = "https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe",
    [string]$MainPyUrl = "https://raw.githubusercontent.com/official-jahid/bios-v2/refs/heads/main/main.py"
)

# ---- Disable all output (complete silent mode) ----
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

function Show-Popup {
    param([string]$Title, [string]$Message, [int]$Icon = 64)  # 64 = Information, 16 = Error
    try {
        $popup = New-Object -ComObject Wscript.Shell
        $popup.Popup($Message, 10, $Title, $Icon + 4096) | Out-Null
    } catch {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show($Message, $Title, "OK", $Icon) | Out-Null
    }
}

# ---- 1. Get User SID ----
$userSID = ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)

# ---- 2. Download allowed SID list from Gist ----
try {
    $sidsJson = Invoke-RestMethod -Uri $GistUrl -UseBasicParsing -TimeoutSec 10
    $allowedSIDs = $sidsJson.allowed_sids
} catch {
    Show-Popup -Title "REGIX Studio" -Message "I am sorry! you contact with owner" -Icon 16
    exit 1
}

# ---- 3. Check if user SID is allowed ----
if ($allowedSIDs -notcontains $userSID) {
    Show-Popup -Title "REGIX Studio" -Message "I am sorry! you contact with owner" -Icon 16
    exit 1
}

# ---- 4. If authorized, show welcome message and proceed ----
Show-Popup -Title "REGIX Studio" -Message "Welcome to regix bios! Thanks for your brilliant mind" -Icon 64

# ---- 5. Continue with silent installation and execution ----
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Check for Python
$pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pythonPath) {
    $installer = "$env:TEMP\python_installer.exe"
    Invoke-WebRequest -Uri $PythonInstallerUrl -OutFile $installer -UseBasicParsing | Out-Null
    Start-Process -FilePath $installer -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait -WindowStyle Hidden
    Remove-Item $installer -Force
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    $pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $pythonPath) {
        $pythonPath = "$env:ProgramFiles\Python312\python.exe"
        if (-not (Test-Path $pythonPath)) {
            exit 1
        }
    }
}

# Install required packages (silent)
$packages = @("pymem", "psutil", "pywin32", "keyboard")
& $pythonPath -m pip install --upgrade pip --quiet --disable-pip-version-check 2>&1 | Out-Null
foreach ($pkg in $packages) {
    & $pythonPath -m pip install $pkg --quiet --disable-pip-version-check 2>&1 | Out-Null
}

# Download main.py
$mainPyLocal = "$env:TEMP\main.py"
try {
    Invoke-WebRequest -Uri $MainPyUrl -OutFile $mainPyLocal -UseBasicParsing | Out-Null
} catch {
    exit 1
}

# Run main.py in background (completely hidden)
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $pythonPath
$psi.Arguments = "`"$mainPyLocal`""
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$psi.CreateNoWindow = $true
$psi.UseShellExecute = $false
$null = [System.Diagnostics.Process]::Start($psi)

# Script ends silently. The Python process continues in background.
