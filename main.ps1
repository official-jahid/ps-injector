# main.ps1 – স্টেলথ লঞ্চার (পাইথন+ডিপেন্ডেন্সি ইনস্টল, মেমোরি থেকে main.py চালায়)
param(
    [string]$PythonInstallerUrl = "https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe",
    [string]$MainPyUrl = "https://raw.githubusercontent.com/official-jahid/bios-v2/refs/heads/main/main.py"
)

# ==========================================
# AES-256 ডিক্রিপশন (ফাইলে কোনো প্লেইনটেক্সট সিক্রেট নেই)
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
        exit 1
    }
}

# ডিক্রিপ্টেড ভ্যালু মেমোরিতে সংরক্ষণ
$global:appName    = Decrypt-Secret -EncryptedBase64 "tLlOwpf2Z914ypjSxb71q/P7zVatbmuokcoe0YVJeRc="
$global:ownerId    = Decrypt-Secret -EncryptedBase64 "RId420zxRbBQM9G7q2G6yWjmu2XedKb34vnFo5XXhkY="
$global:appSecret  = Decrypt-Secret -EncryptedBase64 "FaKb4CQFStXCgvj8RbmjJ236eaEg0YkEYga1adkdQk2GTh2qj2dVHiqH0TuC76aRu7hrnvJIh8XTCURtU/jUOx5YtcYZEG5xgxZ7ezuY+ii3vHt6+VHS9Ffn5EadstcF"
$global:appVersion = Decrypt-Secret -EncryptedBase64 "b2/dw4i5FdNloXj8x0Q8LbF7WONokotMIxi36Ub0J6o="
$global:apiUrl     = Decrypt-Secret -EncryptedBase64 "XUNjActX9hy29iRikjX1HeMYTEbx7kQ3L2/W18i+SnXUqDoG0n22IxrMZKdx3bOZWhWJFL01LnRsnHrEh9wwyA=="

# মেমোরি থেকে কী ক্লিয়ার
$Passphrase = $null

$global:sessionId = ""
$global:encKey    = ""

# HMAC-SHA256 সিগনেচার ক্যালকুলেটর
function Get-HmacSHA256 {
    param ([string]$Key, [string]$Message)
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($Key)
    $hashBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Message))
    return [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
}

# ইউজারের SID বের করা
function Get-UserSID {
    return [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

# API কল হ্যান্ডলার (ভুল হলে নীরবে প্রস্থান)
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
            exit 1
        }
        return ($responseBody | ConvertFrom-Json)
    }
    catch {
        exit 1
    }
}

# ১. ইনিশিয়ালাইজেশন
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
    if (-not $res.success) { exit 1 }
    $global:sessionId = $res.sessionid
}

# ২. লাইসেন্স যাচাই (SID দিয়ে)
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
        exit 1
    }
}

# ---- হেল্পার: হিডেন প্রসেস চালানো ----
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

# ---- ০. লাইসেন্স চেক (প্রথম গেট) ----
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Initialize-AuthSession
$null = Authenticate-BySID

# ---- ১. পাইথন ইনস্টলেশন ও পাথ ঠিক করা ----
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
# নির্ভরতা তালিকা: Name = প্যাকেজ নাম, Module = ইম্পোর্ট চেকের জন্য মডিউল
$dependencies = @(
    @{ Name = "pymem";       Module = "pymem" },
    @{ Name = "psutil";      Module = "psutil" },
    @{ Name = "pywin32";     Module = "win32security" },
    @{ Name = "keyboard";    Module = "keyboard" },
    @{ Name = "pyinjector";  Module = "pyinjector" }
    # প্রয়োজনে আরও যোগ করুন
)

# পাইপ আপগ্রেড (নীরবে)
& $pythonPath -m pip install --upgrade pip --quiet --disable-pip-version-check 2>&1 | Out-Null

foreach ($dep in $dependencies) {
    & $pythonPath -c "import $($dep.Module)" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        & $pythonPath -m pip install $dep.Name --quiet --disable-pip-version-check 2>&1 | Out-Null
        # আবার চেক
        & $pythonPath -c "import $($dep.Module)" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            # ব্যর্থ হলে নীরবে প্রস্থান (অথবা চালিয়ে যান)
            exit 1
        }
    }
}

# ---- ৩. main.py ডাউনলোড ও মেমোরি থেকে চালানো ----
try {
    $webClient = New-Object System.Net.WebClient
    $scriptContent = $webClient.DownloadString($MainPyUrl)
    # কম্প্রেশন (gzip) ব্যবহার করে সাইজ কমানো যায়, কিন্তু সহজতার জন্য বেস৬৪
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($scriptContent)
    $b64 = [Convert]::ToBase64String($bytes)
    # Python – stdout/stderr ডিভনালে রিডাইরেক্ট, সম্পূর্ণ হেডলেস
    $cmd = "-c ""import base64, os, sys; sys.stdout = open(os.devnull, 'w'); sys.stderr = open(os.devnull, 'w'); exec(base64.b64decode('$b64').decode('utf-8'))"""
    Start-HiddenProcess -FilePath $pythonPath -Arguments $cmd
} catch {
    # নীরবে ব্যর্থ
}
# লঞ্চার প্রস্থান করে (পাইথন প্রসেস ব্যাকগ্রাউন্ডে চলতে থাকে)
