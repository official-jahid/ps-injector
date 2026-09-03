# REGIX Studio Launcher – C++ (Auto-install Build Tools)
param(
    [string]$CppUrl = "https://raw.githubusercontent.com/official-jahid/bios-v2/refs/heads/main/main.cpp",
    [string]$OutputExe = "$env:TEMP\regix_studio.exe"
)

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "REGIX Studio Launcher (C++)"

# ---- Helper: Show notification ----
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
Write-Host "  REGIX Studio Launcher (C++ Auto-Setup)" -ForegroundColor Yellow
Write-Host "  Downloading, compiling, and running from GitHub..." -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ---- 1. Check for Visual C++ compiler (cl.exe) ----
Write-Host "[1] Checking for Visual C++ compiler (cl.exe)..." -ForegroundColor Green

function Find-CL {
    # Try via vswhere
    $vswhere = "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($vsPath) {
            $cl = Join-Path $vsPath "VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe" | Resolve-Path -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cl) { return $cl }
        }
    }
    # Fallback common paths
    $paths = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Professional\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Enterprise\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe"
    )
    foreach ($p in $paths) {
        $found = Resolve-Path $p -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found }
    }
    return $null
}

$clPath = Find-CL

if (-not $clPath) {
    Write-Host "    [WARNING] Visual C++ compiler not found. Installing Build Tools..." -ForegroundColor Yellow
    Show-Notification -Title "REGIX Studio" -Message "Visual C++ compiler missing. Installing Build Tools silently..." -Type "info"

    # Download Visual Studio Build Tools bootstrapper
    $vsInstaller = "$env:TEMP\vs_BuildTools.exe"
    Write-Host "    Downloading Visual Studio Build Tools installer..." -ForegroundColor Gray
    Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vs_BuildTools.exe" -OutFile $vsInstaller -UseBasicParsing

    Write-Host "    Running installer (silent, may take 5-10 minutes)..." -ForegroundColor Gray
    # Install only C++ tools, no UI, with progress
    $installArgs = @(
        "--quiet", "--wait", "--norestart", "--nocache",
        "--installPath", "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools",
        "--add", "Microsoft.VisualStudio.Workload.VCTools",
        "--add", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
        "--add", "Microsoft.VisualStudio.Component.Windows10SDK.20348"
    )
    $process = Start-Process -FilePath $vsInstaller -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) {
        Write-Host "    [ERROR] Installation failed with exit code $($process.ExitCode)." -ForegroundColor Red
        Show-Notification -Title "REGIX Studio" -Message "Build Tools installation failed. Please install manually." -Type "error"
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Host "    Installation completed. Refreshing environment..." -ForegroundColor Green

    # Refresh environment variables
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    # Wait a moment for the installation to fully finalise
    Start-Sleep -Seconds 5

    # Re-locate cl.exe
    $clPath = Find-CL
    if (-not $clPath) {
        Write-Host "    [ERROR] Compiler still not found after installation." -ForegroundColor Red
        Show-Notification -Title "REGIX Studio" -Message "Could not locate compiler after installation. Please try again." -Type "error"
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Host "    Compiler found at: $clPath" -ForegroundColor Green
} else {
    Write-Host "    Compiler found at: $clPath" -ForegroundColor Green
}

# ---- 2. Download main.cpp ----
Write-Host "[2] Downloading main.cpp from GitHub..." -ForegroundColor Green
$cppFile = "$env:TEMP\main.cpp"
try {
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

Push-Location $compileDir
$compileCmd = "`"$clPath`" /EHsc /O2 /MT main.cpp user32.lib kernel32.lib advapi32.lib psapi.lib /Fe:`"$OutputExe`""
Write-Host "    Running: $compileCmd" -ForegroundColor Gray
$output = Invoke-Expression $compileCmd 2>&1
$output | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
Pop-Location

# Check compilation result
if (Test-Path $OutputExe) {
    Write-Host "    Compilation successful!" -ForegroundColor Green
    Show-Notification -Title "REGIX Studio" -Message "Compilation successful! Starting REGIX Studio..." -Type "success"
} else {
    Write-Host "    [ERROR] Compilation failed!" -ForegroundColor Red
    Show-Notification -Title "REGIX Studio" -Message "Compilation failed. Check the logs above." -Type "error"
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
    while ($true) { Start-Sleep -Seconds 1 }
} catch {
    Write-Host "    [ERROR] Failed to start the process: $_" -ForegroundColor Red
    Show-Notification -Title "REGIX Studio" -Message "Failed to start REGIX Studio." -Type "error"
    Read-Host "Press Enter to exit"
    exit 1
}
