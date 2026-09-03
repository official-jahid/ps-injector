# launcher.ps1 – REGIX Studio Launcher (C++ build + run)

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "REGIX Studio Launcher (C++)"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  REGIX Studio Launcher (C++ Build)" -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# ---- Step 0: Check VC++ Redistributable ----
Write-Host "[0] Checking VC++ Redistributable..." -ForegroundColor Green
$vcRedistInstalled = $false
$vcRegPaths = @(
    "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86"
)
foreach ($path in $vcRegPaths) {
    if (Test-Path $path) {
        $vcRedistInstalled = $true
        break
    }
}
if (-not $vcRedistInstalled) {
    Write-Host "    VC++ Redistributable not found. Installing..." -ForegroundColor Yellow
    $vcUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    $installer = "$env:TEMP\vc_redist.x64.exe"
    Write-Host "    Downloading from $vcUrl ..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $vcUrl -OutFile $installer -UseBasicParsing
    Write-Host "    Running installer (silent)..." -ForegroundColor Gray
    Start-Process -FilePath $installer -ArgumentList "/install /quiet /norestart" -Wait -WindowStyle Hidden
    Remove-Item $installer -Force
    Write-Host "    VC++ Redistributable installed." -ForegroundColor Green
} else {
    Write-Host "    VC++ Redistributable already installed." -ForegroundColor Green
}

# ---- Step 1: Check MSVC Compiler (cl.exe) ----
Write-Host "[1] Checking MSVC compiler (cl.exe)..." -ForegroundColor Green
$clPath = (Get-Command cl.exe -ErrorAction SilentlyContinue).Source
if (-not $clPath) {
    Write-Host "    MSVC compiler not found. Installing Visual Studio Build Tools..." -ForegroundColor Yellow
    $vsUrl = "https://aka.ms/vs/17/release/vs_BuildTools.exe"
    $installer = "$env:TEMP\vs_BuildTools.exe"
    Write-Host "    Downloading from $vsUrl ..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $vsUrl -OutFile $installer -UseBasicParsing
    Write-Host "    Running installer (select C++ build tools)..." -ForegroundColor Gray
    # নীরবে ইনস্টল করা কঠিন, তাই ম্যানুয়াল ইনস্টল প্রম্পট
    Write-Host "    Please install 'Desktop development with C++' workload manually." -ForegroundColor Yellow
    Start-Process -FilePath $installer -Wait
    Remove-Item $installer -Force
    # আবার চেক
    $clPath = (Get-Command cl.exe -ErrorAction SilentlyContinue).Source
    if (-not $clPath) {
        Write-Host "    [ERROR] MSVC compiler still not found. Please install manually." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Host "    MSVC compiler installed successfully." -ForegroundColor Green
} else {
    Write-Host "    MSVC compiler found at: $clPath" -ForegroundColor Green
}

# ---- Step 2: Compile main.cpp ----
Write-Host "[2] Compiling main.cpp..." -ForegroundColor Green
$cppFile = "$env:TEMP\main.cpp"
$exeFile = "$env:TEMP\REGIX.exe"

# Write C++ code to file
@"
// main.cpp – (paste the full C++ code from above here)
"@ | Out-File -FilePath $cppFile -Encoding ascii

# (Alternatively, download from a URL)

Write-Host "    Compiling (this may take a moment)..." -ForegroundColor Gray
$compileCmd = "`"$clPath`" /EHsc /O2 /MT $cppFile /Fe:$exeFile user32.lib kernel32.lib advapi32.lib psapi.lib"
$compileResult = Invoke-Expression -Command $compileCmd 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "    [ERROR] Compilation failed!" -ForegroundColor Red
    Write-Host "    Error: $compileResult" -ForegroundColor Red
    [System.Windows.Forms.MessageBox]::Show("REGIX Studio compilation failed! See PowerShell log for details.", "Error", "OK", "Error")
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "    Compilation successful. EXE created at: $exeFile" -ForegroundColor Green

# ---- Step 3: Run EXE ----
Write-Host "[3] Running REGIX.exe..." -ForegroundColor Green
try {
    Start-Process -FilePath $exeFile -WindowStyle Hidden
    Write-Host "    REGIX Studio started successfully in background." -ForegroundColor Green
    [System.Windows.Forms.MessageBox]::Show("REGIX Studio started successfully!`nHotkeys: F3=aimbot ON, F4=OFF, F5=drag ON, F6=OFF, F8=cleanup", "REGIX Studio", "OK", "Information")
} catch {
    Write-Host "    [ERROR] Failed to run REGIX.exe: $_" -ForegroundColor Red
    [System.Windows.Forms.MessageBox]::Show("Failed to run REGIX Studio: $_", "Error", "OK", "Error")
    exit 1
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Setup complete. REGIX Studio is running." -ForegroundColor Yellow
Write-Host "  Press Ctrl+C in this window to exit launcher." -ForegroundColor Gray
Write-Host "==============================================" -ForegroundColor Cyan

# Keep window open
while ($true) { Start-Sleep -Seconds 1 }
