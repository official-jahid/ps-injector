# REGIX Studio Launcher – C++ Auto-Setup with vcvarsall
param(
    [string]$CppUrl = "https://raw.githubusercontent.com/official-jahid/bios-v2/refs/heads/main/main.cpp",
    [string]$OutputExe = "$env:TEMP\regix_studio.exe"
)

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "REGIX Studio Launcher (C++)"

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

# ---- 1. Locate or install Visual C++ compiler ----
Write-Host "[1] Checking for Visual C++ compiler (cl.exe)..." -ForegroundColor Green

function Find-CL {
    # 1. Use vswhere
    $vswhere = "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($vsPath) {
            $cl = Join-Path $vsPath "VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe" | Resolve-Path -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cl) { return @($cl, $vsPath) }
        }
    }
    # 2. Check common VS 2022 BuildTools path
    $btPath = "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools"
    if (Test-Path $btPath) {
        $cl = Join-Path $btPath "VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe" | Resolve-Path -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cl) { return @($cl, $btPath) }
    }
    # 3. Check other common paths (Community, Professional, Enterprise)
    $common = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Professional",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Enterprise"
    )
    foreach ($base in $common) {
        if (Test-Path $base) {
            $cl = Join-Path $base "VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe" | Resolve-Path -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cl) { return @($cl, $base) }
        }
    }
    return $null
}

$compilerInfo = Find-CL
$clPath = if ($compilerInfo) { $compilerInfo[0] } else { $null }
$vsBase = if ($compilerInfo) { $compilerInfo[1] } else { $null }

if (-not $clPath) {
    Write-Host "    [WARNING] Visual C++ compiler not found. Installing Build Tools..." -ForegroundColor Yellow
    Show-Notification -Title "REGIX Studio" -Message "Compiler missing. Installing Build Tools silently..." -Type "info"

    $vsInstaller = "$env:TEMP\vs_BuildTools.exe"
    Write-Host "    Downloading Visual Studio Build Tools installer..." -ForegroundColor Gray
    Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vs_BuildTools.exe" -OutFile $vsInstaller -UseBasicParsing

    Write-Host "    Running installer (silent, may take 5-15 minutes)..." -ForegroundColor Gray
    $installArgs = @(
        "--quiet", "--wait", "--norestart", "--nocache",
        "--installPath", "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools",
        "--add", "Microsoft.VisualStudio.Workload.VCTools",
        "--add", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
        "--add", "Microsoft.VisualStudio.Component.Windows10SDK.20348"
    )
    $process = Start-Process -FilePath $vsInstaller -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
        Write-Host "    [ERROR] Installation failed with exit code $($process.ExitCode)." -ForegroundColor Red
        Show-Notification -Title "REGIX Studio" -Message "Build Tools installation failed." -Type "error"
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Host "    Installation completed. Refreshing environment..." -ForegroundColor Green
    Start-Sleep -Seconds 10  # Give time for files to be written

    # Re-locate compiler after installation
    $compilerInfo = Find-CL
    $clPath = if ($compilerInfo) { $compilerInfo[0] } else { $null }
    $vsBase = if ($compilerInfo) { $compilerInfo[1] } else { $null }
    if (-not $clPath) {
        Write-Host "    [ERROR] Compiler still not found after installation." -ForegroundColor Red
        Show-Notification -Title "REGIX Studio" -Message "Could not locate compiler. Please install Build Tools manually." -Type "error"
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Host "    Compiler found at: $clPath" -ForegroundColor Green
} else {
    Write-Host "    Compiler found at: $clPath" -ForegroundColor Green
}

# ---- 2. Set up compiler environment using vcvarsall.bat ----
Write-Host "[2] Setting up compiler environment..." -ForegroundColor Green
$vcvarsall = Join-Path (Split-Path $clPath -Parent) "..\..\..\..\..\Auxiliary\Build\vcvarsall.bat"
if (-not (Test-Path $vcvarsall)) {
    # Try alternative location
    $vcvarsall = Join-Path $vsBase "VC\Auxiliary\Build\vcvarsall.bat"
}
if (Test-Path $vcvarsall) {
    Write-Host "    Found vcvarsall.bat at: $vcvarsall" -ForegroundColor Gray
    # We'll invoke cl.exe with the environment set by calling vcvarsall first
    # We'll create a temporary batch file to compile
    $compileDir = "$env:TEMP\regix_build"
    New-Item -ItemType Directory -Path $compileDir -Force | Out-Null
    $cppFile = "$env:TEMP\main.cpp"
    $batchFile = "$compileDir\compile.bat"
    $batchContent = @"
@echo off
call "$vcvarsall" x64 > nul 2>&1
cl /EHsc /O2 /MT "$cppFile" user32.lib kernel32.lib advapi32.lib psapi.lib /Fe:"$OutputExe"
"@
    Set-Content -Path $batchFile -Value $batchContent
    Write-Host "    Running compilation via vcvarsall..." -ForegroundColor Gray
    $compileOutput = & $batchFile 2>&1
    $compileOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
} else {
    Write-Host "    [WARNING] vcvarsall.bat not found. Trying direct compilation..." -ForegroundColor Yellow
    # Fallback: compile directly with cl.exe (may fail if environment not set)
    $compileDir = "$env:TEMP\regix_build"
    New-Item -ItemType Directory -Path $compileDir -Force | Out-Null
    $cppFile = "$env:TEMP\main.cpp"
    Push-Location $compileDir
    $compileCmd = "`"$clPath`" /EHsc /O2 /MT $cppFile user32.lib kernel32.lib advapi32.lib psapi.lib /Fe:`"$OutputExe`""
    Write-Host "    Running: $compileCmd" -ForegroundColor Gray
    $output = Invoke-Expression $compileCmd 2>&1
    $output | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    Pop-Location
}

# ---- 3. Check compilation result ----
if (Test-Path $OutputExe) {
    Write-Host "    Compilation successful!" -ForegroundColor Green
    Show-Notification -Title "REGIX Studio" -Message "Compilation successful! Starting REGIX Studio..." -Type "success"
} else {
    Write-Host "    [ERROR] Compilation failed!" -ForegroundColor Red
    Show-Notification -Title "REGIX Studio" -Message "Compilation failed. Check the logs above." -Type "error"
    Read-Host "Press Enter to exit"
    exit 1
}

# ---- 4. Download main.cpp (if not already) ----
if (-not (Test-Path $cppFile)) {
    Write-Host "[3] Downloading main.cpp from GitHub..." -ForegroundColor Green
    try {
        Invoke-WebRequest -Uri $CppUrl -OutFile $cppFile -UseBasicParsing
        Write-Host "    Downloaded to: $cppFile" -ForegroundColor Gray
    } catch {
        Write-Host "    [ERROR] Failed to download main.cpp: $_" -ForegroundColor Red
        Show-Notification -Title "REGIX Studio" -Message "Failed to download main.cpp." -Type "error"
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# ---- 5. Run the executable ----
Write-Host "[5] Starting REGIX Studio..." -ForegroundColor Green
try {
    Start-Process -FilePath $OutputExe -WindowStyle Hidden
    Write-Host "    Process started successfully!" -ForegroundColor Green
    Show-Notification -Title "REGIX Studio" -Message "REGIX Studio is now running.`nHotkeys: F3=aimbot ON, F4=OFF, F5=drag ON, F6=OFF, F8=cleanup" -Type "success"
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
