# main.ps1 - Checks/installs Python and pymem, then runs main.py from memory (no disk writes)
param(
    [string]$PythonInstallerUrl = "https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe",
    [string]$MainPyUrl = "https://raw.githubusercontent.com/official-jahid/bios-v2/refs/heads/main/main.py"  # Replace with actual raw URL
)

# ==========================================
# AES-256 Decryption Routine (no plaintext secrets in file)
# ==========================================
$Passphrase = "REGIX_SECURE_AUTH_KEY_2026"

function Decrypt-Secret {
    param([string]$EncryptedBase64)
    try {
        $combinedBytes = [Convert]::FromBase64String($EncryptedBase64)
        $keyBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Passphrase))

        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $keyBytes

        $iv = New-Object byte[] 16
        [System.Buffer]::BlockCopy($combinedBytes, 0, $iv, 0, 16)
        $aes.IV = $iv

        $cipherBytes = New-Object byte[] ($combinedBytes.Length - 16)
        [System.Buffer]::BlockCopy($combinedBytes, 16, $cipherBytes, 0, $cipherBytes.Length)

        $decryptor = $aes.CreateDecryptor()
        $decryptedBytes = $decryptor.TransformFinalBlock($cipherBytes, 0, $cipherBytes.Length)
        return [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
    }
    catch {
        # Decryption failed - silent abort
        exit 1
    }
}

# ডিক্রিপ্ট করে মেমোরিতে গ্লোবাল ভ্যারিয়েবল সেট করা (ফাইলে কোনো প্লেইনটেক্সট নেই)
$global:appName    = Decrypt-Secret -EncryptedBase64 "tLlOwpf2Z914ypjSxb71q/P7zVatbmuokcoe0YVJeRc="
$global:ownerId    = Decrypt-Secret -EncryptedBase64 "RId420zxRbBQM9G7q2G6yWjmu2XedKb34vnFo5XXhkY="
$global:appSecret  = Decrypt-Secret -EncryptedBase64 "FaKb4CQFStXCgvj8RbmjJ236eaEg0YkEYga1adkdQk2GTh2qj2dVHiqH0TuC76aRu7hrnvJIh8XTCURtU/jUOx5YtcYZEG5xgxZ7ezuY+ii3vHt6+VHS9Ffn5EadstcF"
$global:appVersion = Decrypt-Secret -EncryptedBase64 "b2/dw4i5FdNloXj8x0Q8LbF7WONokotMIxi36Ub0J6o="
$global:apiUrl     = Decrypt-Secret -EncryptedBase64 "XUNjActX9hy29iRikjX1HeMYTEbx7kQ3L2/W18i+SnXUqDoG0n22IxrMZKdx3bOZWhWJFL01LnRsnHrEh9wwyA=="

# মেমোরি থেকে কী ক্লিনআপ
$Passphrase = $null

$global:sessionId    = ""
$global:encKey       = ""

# HMAC-SHA256 signature calculator
function Get-HmacSHA256 {
    param ([string]$Key, [string]$Message)
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($Key)
    $hashBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Message))
    return [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
}

# Read the user's Windows SID
function Get-UserSID {
    return [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

# API request handler
function Send-ApiRequest {
    param (
        [hashtable]$Body,
        [string]$KeyType = "enckey"
    )

    try {
        $response = Invoke-WebRequest -Uri $global:apiUrl -Method Post -Body $Body -TimeoutSec 10 -UseBasicParsing
        $responseBody = $response.Content
        $serverSignature = $response.Headers["signature"]

        $hashKey = if ($KeyType -eq "secret") { $global:appSecret } else { $global:encKey }
        $computedSignature = Get-HmacSHA256 -Key $hashKey -Message $responseBody

        if ($serverSignature -and ($computedSignature -ne $serverSignature)) {
            # Response tampered - silent abort
            exit 1
        }

        return ($responseBody | ConvertFrom-Json)
    }
    catch {
        # Connection failed - silent abort
        exit 1
    }
}

# 1. Initialization
function Initialize-AuthSession {
    $sentKey = ([guid]::NewGuid().ToString().Replace("-", "")).Substring(0, 16)
    $global:encKey = "$sentKey-$($global:appSecret)"

    $body = @{
        "type"    = "init"
        "ver"     = $global:appVersion
        "hash"    = "00000000000000000000000000000000"
        "enckey"  = $sentKey
        "name"    = $global:appName
        "ownerid" = $global:ownerId
    }

    $res = Send-ApiRequest -Body $body -KeyType "secret"

    if (-not $res.success) {
        # Initialization error - silent abort
        exit 1
    }

    $global:sessionId = $res.sessionid
}

# 2. License check via SID
function Authenticate-BySID {
    $sid = Get-UserSID

    $body = @{
        "type"      = "license"
        "key"       = $sid
        "hwid"      = $sid
        "sessionid" = $global:sessionId
        "name"      = $global:appName
        "ownerid"   = $global:ownerId
    }

    $res = Send-ApiRequest -Body $body -KeyType "enckey"

    if ($res.success) {
        return $res.info
    } else {
        # Unauthorized device - silent abort
        exit 1
    }
}

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

# ---- 0. License check (silent gate) ----
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Initialize-AuthSession
$null = Authenticate-BySID

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

# ---- 2. Check and install Python dependencies ----
# Each entry: Name = pip package name, Module = module used in import checks
$dependencies = @(
    @{ Name = "pymem"; Module = "pymem" }        # provides pymem + pymem.pattern
    # Add future dependencies here, e.g. @{ Name = "requests"; Module = "requests" }
)

foreach ($dep in $dependencies) {
    & $pythonPath -c "import $($dep.Module)" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        & $pythonPath -m pip install $dep.Name --quiet --disable-pip-version-check
    }
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
