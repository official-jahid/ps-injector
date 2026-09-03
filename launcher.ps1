# REGIX Studio Launcher – C++ Version
# Downloads, compiles, and runs main.cpp from GitHub

param(
    [string]$CppUrl = "https://raw.githubusercontent.com/official-jahid/bios-v2/refs/heads/main/main.cpp",
    [string]$OutputExe = "$env:TEMP\regix_studio.exe"
)

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "REGIX Studio Launcher (C++)"

# ---- Helper: Show notification ----
function Show-Notification {
    param([string]$Title, [string]$Message, [string]$Type = "info")
    # Console output
    $color = if ($Type -eq "error") { "Red" } elseif ($Type -eq "success") { "Green" } else { "Cyan" }
    Write-Host "[$Type] $Message" -ForegroundColor $color
    # Windows popup
    try {
        $popup = New-Object -ComObject Wscript.Shell
        $icon = if ($Type -eq "error") { 16 } elseif ($Type -eq "success") { 64 } else { 64 }
        $popup.Popup($Message, 5, $Title, $icon + 4096) | Out-Null
    } catch {
        # Fallback: use MessageBox
        Add-Type -AssemblyName System.Windows.Forms
        $buttons = if ($Type -eq "error") { [System.Windows.Forms.MessageBoxButtons]::OK } else { [System.Windows.Forms.MessageBoxButtons]::OK }
        $icon = if ($Type -eq "error") { [System.Windows.Forms.MessageBoxIcon]::Error } else { [System.Windows.Forms.MessageBoxIcon]::Information }
        [System.Windows.Forms.MessageBox]::Show($Message, $Title, $buttons, $icon) | Out-Null
    }
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  REGIX Studio Launcher (C++ Version)" -ForegroundColor Yellow
Write-Host "  Downloading and compiling from GitHub..." -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ---- 1. Check for Visual C++ compiler (cl.exe) ----
Write-Host "[1] Checking for Visual C++ compiler (cl.exe)..." -ForegroundColor Green

# Try to find cl.exe via vswhere or common paths
$clPath = $null
$vswhere = "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    Write-Host "    Found vswhere, locating Visual Studio..." -ForegroundColor Gray
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($vsPath) {
        $clPath = Join-Path $vsPath "VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe" | Resolve-Path -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $clPath) {
            $clPath = Join-Path $vsPath "VC\Tools\MSVC\*\bin\Hostx86\x86\cl.exe" | Resolve-Path -ErrorAction SilentlyContinue | Select-Object -First 1
        }
    }
}

# Fallback: check common paths
if (-not $clPath) {
    $commonPaths = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Professional\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Enterprise\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe"
    )
    foreach ($p in $commonPaths) {
        $found = Resolve-Path $p -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $clPath = $found
            break
        }
    }
}

if (-not $clPath) {
    Write-Host "    [ERROR] Visual C++ compiler not found!" -ForegroundColor Red
    Show-Notification -Title "REGIX Studio" -Message "Visual C++ compiler not found. Please install Visual Studio Build Tools with C++ support." -Type "error"
    Write-Host ""
    Write-Host "    You can download Build Tools from:" -ForegroundColor Yellow
    Write-Host "    https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    Make sure to select 'Desktop development with C++' during installation." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "    Compiler found at: $clPath" -ForegroundColor Green

# ---- 2. Download main.cpp ----
Write-Host "[2] Downloading main.cpp from GitHub..." -ForegroundColor Green
try {
    $cppFile = "$env:TEMP\main.cpp"
    Invoke-WebRequest -Uri $CppUrl -OutFile $cppFile -UseBasicParsing
    Write-Host "    Downloaded to: $cppFile" -ForegroundColor Gray
} catch {
    Write-Host "    [ERROR] Failed to download main.cpp: $_" -ForegroundColor Red
    Show-Notification -Title "REGIX Studio" -Message "Failed to download main.cpp from GitHub." -Type "error"
    Read-Host "Press Enter to exit"
    exit 1
}

# ---- 3. Compile the C++ code ----
Write-Host "[3] Compiling main.cpp..." -ForegroundColor Green
$compileDir = "$env:TEMP\regix_build"
New-Item -ItemType Directory -Path $compileDir -Force | Out-Null
Copy-Item $cppFile -Destination "$compileDir\main.cpp" -Force

# Set up Visual Studio environment
$vsDevCmd = Join-Path (Split-Path $clPath -Parent) "..\..\..\..\Common7\Tools\VsDevCmd.bat"
if (Test-Path $vsDevCmd) {
    Write-Host "    Setting up Visual Studio environment..." -ForegroundColor Gray
    cmd /c "`"$vsDevCmd`" -arch=amd64 && cd /d `"$compileDir`" && cl /EHsc /O2 /MT main.cpp user32.lib kernel32.lib advapi32.lib psapi.lib /Fe:`"$OutputExe`" 2>&1"
} else {
    # Fallback: run cl directly with full paths
    Push-Location $compileDir
    $compileCmd = "`"$clPath`" /EHsc /O2 /MT main.cpp user32.lib kernel32.lib advapi32.lib psapi.lib /Fe:`"$OutputExe`""
    Write-Host "    Running: $compileCmd" -ForegroundColor Gray
    Invoke-Expression $compileCmd 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    Pop-Location
}

# Check if compilation succeeded
if (Test-Path $OutputExe) {
    Write-Host "    Compilation successful!" -ForegroundColor Green
    Show-Notification -Title "REGIX Studio" -Message "Compilation successful! Starting REGIX Studio..." -Type "success"
} else {
    Write-Host "    [ERROR] Compilation failed!" -ForegroundColor Red
    Show-Notification -Title "REGIX Studio" -Message "Compilation failed. Please check the logs above." -Type "error"
    Read-Host "Press Enter to exit"
    exit 1
}

# ---- 4. Run the executable ----
Write-Host "[4] Starting REGIX Studio..." -ForegroundColor Green
try {
    Start-Process -FilePath $OutputExe -WindowStyle Hidden
    Write-Host "    Process started successfully!" -ForegroundColor Green
    Show-Notification -Title "REGIX Studio" -Message "REGIX Studio is now running in the background.`nHotkeys: F3=aimbot ON, F4=OFF, F5=drag ON, F6=OFF, F8=cleanup" -Type "success"
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  REGIX Studio is running!" -ForegroundColor Yellow
    Write-Host "  Hotkeys: F3=aimbot ON, F4=OFF, F5=drag ON, F6=OFF, F8=cleanup" -ForegroundColor Cyan
    Write-Host "  Press Ctrl+C in this window to stop the launcher." -ForegroundColor Gray
    Write-Host "  (The C++ process will continue running in background.)" -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    # Keep the launcher alive so user can see the logs
    while ($true) {
        Start-Sleep -Seconds 1
    }
} catch {
    Write-Host "    [ERROR] Failed to start the process: $_" -ForegroundColor Red
    Show-Notification -Title "REGIX Studio" -Message "Failed to start REGIX Studio." -Type "error"
    Read-Host "Press Enter to exit"
    exit 1
}
