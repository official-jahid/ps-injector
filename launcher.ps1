# REGIX Studio Launcher – Portable MinGW (g++) Version
# No installation required – downloads and uses portable compiler
param(
    [string]$CppUrl = "https://raw.githubusercontent.com/official-jahid/bios-v2/refs/heads/main/main.cpp",
    [string]$OutputExe = "$env:TEMP\regix_studio.exe",
    [string]$MinGwUrl = "https://github.com/niXman/mingw-builds-binaries/releases/download/13.2.0-rt_v11-rev1/x86_64-13.2.0-release-win32-seh-msvcrt-rt_v11-rev1.7z"
)

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "REGIX Studio Launcher (MinGW)"

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
Write-Host "  REGIX Studio Launcher (Portable MinGW)" -ForegroundColor Yellow
Write-Host "  Downloads compiler, compiles, and runs from GitHub..." -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ---- 1. Download main.cpp ----
Write-Host "[1] Downloading main.cpp from GitHub..." -ForegroundColor Green
$cppFile = "$env:TEMP\main.cpp"
try {
    Invoke-WebRequest -Uri $CppUrl -OutFile $cppFile -UseBasicParsing
    Write-Host "    Downloaded to: $cppFile" -ForegroundColor Gray
} catch {
    Write-Host "    [ERROR] Failed to download main.cpp: $_" -ForegroundColor Red
    Show-Notification -Title "REGIX Studio" -Message "Failed to download main.cpp." -Type "error"
    Read-Host "Press Enter to exit"
    exit 1
}

# ---- 2. Check for portable MinGW ----
Write-Host "[2] Checking for portable MinGW compiler (g++)..." -ForegroundColor Green
$mingwDir = "$env:TEMP\mingw64"
$gppPath = "$mingwDir\bin\g++.exe"

if (-not (Test-Path $gppPath)) {
    Write-Host "    MinGW not found. Downloading portable MinGW..." -ForegroundColor Yellow
    Show-Notification -Title "REGIX Studio" -Message "Downloading MinGW compiler (approx 50MB)..." -Type "info"

    $archiveFile = "$env:TEMP\mingw.7z"
    Write-Host "    Downloading from: $MinGwUrl" -ForegroundColor Gray
    try {
        Invoke-WebRequest -Uri $MinGwUrl -OutFile $archiveFile -UseBasicParsing
    } catch {
        Write-Host "    [ERROR] Failed to download MinGW: $_" -ForegroundColor Red
        Show-Notification -Title "REGIX Studio" -Message "Failed to download MinGW compiler." -Type "error"
        Read-Host "Press Enter to exit"
        exit 1
    }

    Write-Host "    Extracting MinGW (this may take a minute)..." -ForegroundColor Gray
    # Check if 7zip is available; if not, use built-in Expand-Archive (but 7z is better)
    $7zip = "${env:ProgramFiles}\7-Zip\7z.exe"
    if (Test-Path $7zip) {
        & $7zip x $archiveFile -o"$env:TEMP" -y | Out-Null
    } else {
        # Use Expand-Archive (slower but works)
        Expand-Archive -Path $archiveFile -DestinationPath "$env:TEMP" -Force
    }
    Remove-Item $archiveFile -Force

    # Rename extracted folder to mingw64 if needed
    $extracted = Get-ChildItem "$env:TEMP" -Directory | Where-Object { $_.Name -like "mingw*" -or $_.Name -like "x86_64-*" } | Select-Object -First 1
    if ($extracted -and $extracted.FullName -ne $mingwDir) {
        Remove-Item $mingwDir -Recurse -Force -ErrorAction SilentlyContinue
        Move-Item $extracted.FullName -Destination $mingwDir -Force
    }

    if (-not (Test-Path $gppPath)) {
        Write-Host "    [ERROR] MinGW extraction failed. g++.exe not found." -ForegroundColor Red
        Show-Notification -Title "REGIX Studio" -Message "MinGW extraction failed." -Type "error"
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Host "    MinGW ready at: $mingwDir" -ForegroundColor Green
} else {
    Write-Host "    MinGW already available at: $mingwDir" -ForegroundColor Green
}

# ---- 3. Compile using g++ ----
Write-Host "[3] Compiling main.cpp with g++..." -ForegroundColor Green
$compileCmd = "`"$gppPath`" -O2 -static -mwindows -o `"$OutputExe`" `"$cppFile`" -luser32 -lkernel32 -ladvapi32 -lpsapi -lgdi32 -lcomctl32 -lole32 -lshell32"
Write-Host "    Running: $compileCmd" -ForegroundColor Gray
$output = Invoke-Expression $compileCmd 2>&1
$output | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }

if (-not (Test-Path $OutputExe)) {
    Write-Host "    [ERROR] Compilation failed!" -ForegroundColor Red
    Show-Notification -Title "REGIX Studio" -Message "Compilation failed. Check the logs above." -Type "error"
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "    Compilation successful!" -ForegroundColor Green
Show-Notification -Title "REGIX Studio" -Message "Compilation successful! Starting REGIX Studio..." -Type "success"

# ---- 4. Run the executable ----
Write-Host "[4] Starting REGIX Studio..." -ForegroundColor Green
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
