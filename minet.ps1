<#
.SYNOPSIS
    minet.ps1 - Quan ly Minet tunnel + worker tren Windows (PowerShell 5+).

.DESCRIPTION
    Subcommands:
      setup      One-shot: install + link + PATH + start
      install    Fetch cau hinh tu dashboard (hoi email + proxy neu thieu)
      start      Chay proxy + frpc + worker o background
      stop       Dung tat ca
      status     Xem trang thai tien trinh
      logs       Xem log (worker | tunnel | tp)
      run        Chay foreground (Ctrl+C de dung)
      worker     Chi chay worker (duoc 'start' goi lai)
      proxy      Xem/doi proxy cho API calls
      link       Tao launcher 'minet' tren PATH
      uninstall  Go sach
      dashboard  minet dashboard {start|stop|status|restart|logs|uninstall}

.EXAMPLE
    .\minet.ps1
    .\minet.ps1 setup -Email me@example.com
    .\minet.ps1 start
    .\minet.ps1 status
    .\minet.ps1 logs worker
    .\minet.ps1 stop
#>

param(
    [Parameter(Position=0)] [string]$Command = "",
    [Parameter(Position=1)] [string]$Arg1    = "",
    [string]$Email  = "",
    [string]$Proxy  = "",
    [switch]$Force,
    [int]   $Lines  = 50,
    [int]   $Port   = 8888
)

$ErrorActionPreference = "Stop"

# ---------- Constants ----------

$BASE_URL    = "https://dashboard.minet.vn"
$INTERVAL    = 30
$FRP_VERSION = "0.61.1"

if ($env:LOCALAPPDATA) { $_base = $env:LOCALAPPDATA } else { $_base = $HOME }
$MINET_ROOT  = Join-Path $_base "minet"
$LOG_DIR     = Join-Path $MINET_ROOT "logs"
$PID_DIR     = Join-Path $MINET_ROOT "pids"
$TUN_TOML    = Join-Path $MINET_ROOT "tun.toml"
$CONFIG_JSON = Join-Path $MINET_ROOT "config.json"
$FRPC_TARGET = Join-Path $MINET_ROOT "frpc.exe"

# ---------- Directories ----------

function Ensure-Dirs {
    foreach ($d in @($MINET_ROOT, $LOG_DIR, $PID_DIR)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

# ---------- PID helpers ----------

function Get-PidFile([string]$name) { Join-Path $PID_DIR "$name.pid" }

function Save-Pid([string]$name, [int]$pidVal) {
    Set-Content -Path (Get-PidFile $name) -Value $pidVal -Encoding UTF8
}

function Read-Pid([string]$name) {
    $f = Get-PidFile $name
    if (-not (Test-Path $f)) { return $null }
    $v = (Get-Content $f -Raw -ErrorAction SilentlyContinue).Trim()
    if ($v -match '^\d+$') { return [int]$v }
    return $null
}

function Test-PidAlive([object]$pidVal) {
    if ($null -eq $pidVal) { return $false }
    try {
        $proc = Get-Process -Id ([int]$pidVal) -ErrorAction SilentlyContinue
        return ($null -ne $proc)
    } catch { return $false }
}

function Stop-Pid([object]$pidVal) {
    if ($null -eq $pidVal) { return }
    try {
        $proc = Get-Process -Id ([int]$pidVal) -ErrorAction SilentlyContinue
        if ($proc) { $proc | Stop-Process -Force -ErrorAction SilentlyContinue }
    } catch {}
}

function Remove-Named([string]$name) {
    $pidVal = Read-Pid $name
    if ($null -ne $pidVal -and (Test-PidAlive $pidVal)) { Stop-Pid $pidVal }
    $f = Get-PidFile $name
    if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
}

# ---------- Proxy state ----------

$script:_proxies  = @()
$script:_proxyIdx = 0

$PROXY_RX = [regex]'(?i)^(?<scheme>socks5h?|socks4|http|https)://(?:(?<user>[^:@]+):(?<pw>[^@]+)@)?(?<host>[^:]+):(?<port>\d+)/?$'

function Load-ProxySource([string]$src) {
    if (-not $src) { return @() }
    if (Test-Path $src -PathType Leaf) {
        $lines = Get-Content $src | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }
        return @($lines | ForEach-Object { $_.Trim() })
    }
    return @($src.Trim())
}

function Set-Proxy([string]$src) {
    $script:_proxies  = @()
    $script:_proxyIdx = 0
    if (-not $src) { return }
    $list  = @(Load-ProxySource $src)
    if ($list.Count -eq 0) { Write-Host "  proxy: khong load duoc tu '$src'" -ForegroundColor Yellow; return }
    $valid = @($list | Where-Object { $PROXY_RX.IsMatch($_) })
    $bad   = @($list | Where-Object { -not $PROXY_RX.IsMatch($_) })
    if ($bad.Count -gt 0) {
        $badStr = ($bad[0..([Math]::Min(2, $bad.Count-1))] -join ', ')
        Write-Host "  proxy: bo qua URL sai format: $badStr" -ForegroundColor Yellow
    }
    if ($valid.Count -eq 0) { return }
    $script:_proxies = $valid
    Write-Host "  proxy: $($script:_proxies.Count) entry" -ForegroundColor Gray
}

function Get-NextProxy {
    if ($script:_proxies.Count -eq 0) { return $null }
    $p = $script:_proxies[$script:_proxyIdx % $script:_proxies.Count]
    $script:_proxyIdx++
    return $p
}

# ---------- HTTP helpers ----------

function Invoke-HttpGet([string]$url, [int]$timeout = 20) {
    return Invoke-HttpRequest $url $null $null $timeout
}

function Invoke-HttpPostJson([string]$url, [hashtable]$data, [int]$timeout = 15) {
    $body = $data | ConvertTo-Json -Compress
    return Invoke-HttpRequest $url $body "application/json" $timeout
}

function Invoke-HttpRequest([string]$url, [string]$body, [string]$contentType, [int]$timeout) {
    $proxyUrl = Get-NextProxy
    $headers = @{
        "User-Agent"      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        "Accept"          = "*/*"
        "Accept-Language" = "en-US,en;q=0.9"
        "Referer"         = "$BASE_URL/"
    }
    $params = @{
        Uri             = $url
        Headers         = $headers
        UseBasicParsing = $true
        TimeoutSec      = $timeout
    }
    if ($body) {
        $params["Method"]      = "POST"
        $params["Body"]        = [System.Text.Encoding]::UTF8.GetBytes($body)
        $params["ContentType"] = $contentType
    }
    if ($proxyUrl) {
        $params["Proxy"] = $proxyUrl
        $params["ProxyUseDefaultCredentials"] = $false
        if ($proxyUrl -match '^https?://(?<u>[^:@]+):(?<p>[^@]+)@') {
            $secPw = ConvertTo-SecureString $Matches['p'] -AsPlainText -Force
            $cred  = New-Object System.Management.Automation.PSCredential($Matches['u'], $secPw)
            $params["ProxyCredential"] = $cred
        }
    }
    $resp = Invoke-WebRequest @params
    return $resp.Content
}

function Get-PublicIp {
    $sources = @(
        "https://api.ipify.org",
        "https://icanhazip.com",
        "https://ifconfig.me/ip",
        "https://api4.my-ip.io/ip"
    )
    foreach ($src in $sources) {
        try {
            $ip = (Invoke-RestMethod -Uri $src -TimeoutSec 10).Trim()
            if ($ip) { return $ip }
        } catch {}
    }
    return ""
}

function Invoke-UrlEncode([string]$s) { [System.Uri]::EscapeDataString($s) }

# ---------- Fetch + extract setup script ----------

function Get-SetupScript([string]$email) {
    $ip = Get-PublicIp
    if (-not $ip) { throw "Khong lay duoc IP public." }
    $eEnc = Invoke-UrlEncode $email
    $iEnc = Invoke-UrlEncode $ip
    $url  = "$BASE_URL/api/minecoin/setup?email=$eEnc&ip=$iEnc&mode=dashboard"
    $raw  = (Invoke-HttpGet $url 30).Trim()
    if ($raw -match '^[A-Za-z0-9+/\s]+=*$') {
        try {
            $bytes   = [Convert]::FromBase64String(($raw -replace '\s',''))
            $decoded = [System.Text.Encoding]::UTF8.GetString($bytes)
            if ($decoded) { $raw = $decoded }
        } catch {}
    }
    return $raw, $ip
}

function Get-EmbeddedFiles([string]$setupScript) {
    # Unwrap outer base64 | sh wrapper
    $unwrapRx = [regex]'(?ms)printf\s+"%[bs]"\s+"([A-Za-z0-9+/=\\\n\s]+?)"\s*\|\s*base64\s+-d\s*\|\s*sh'
    for ($i = 0; $i -lt 5; $i++) {
        $m = $unwrapRx.Match($setupScript)
        if (-not $m.Success) { break }
        try {
            $b64   = $m.Groups[1].Value -replace '\\n|\s',''
            $inner = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
            if ($inner -match 'printf' -and $inner -match 'base64') { $setupScript = $inner } else { break }
        } catch { break }
    }

    $fileRx = [regex]'(?ms)printf\s+"%[bs]"\s+"([A-Za-z0-9+/=\\\n\s]+?)"\s*\|\s*base64\s+-d\s*>\s*("?[^"\n]+?"?)\s*$'
    $out = @{}
    foreach ($m in $fileRx.Matches($setupScript)) {
        try {
            $b64  = $m.Groups[1].Value -replace '\\n|\s',''
            $data = [Convert]::FromBase64String($b64)
            $path = $m.Groups[2].Value.Trim().Trim('"')
            $path = $path -replace '\$MR', $MINET_ROOT -replace '\$PREFIX', ''
            $out[$path] = $data
        } catch {}
    }
    return $out
}

# ---------- frpc download ----------

function Get-FrpcUrl {
    $arch = (Get-WmiObject Win32_Processor).AddressWidth
    if ([System.Environment]::Is64BitOperatingSystem) { $fa = "amd64" } else { $fa = "386" }
    # Kiem tra ARM
    $procArch = [System.Environment]::GetEnvironmentVariable("PROCESSOR_ARCHITECTURE")
    if ($procArch -match "ARM") { $fa = "arm64" }
    return "https://github.com/fatedier/frp/releases/download/v$FRP_VERSION/frp_${FRP_VERSION}_windows_${fa}.zip"
}

function Install-Frpc {
    if (Test-Path $FRPC_TARGET) { return $FRPC_TARGET }
    $existing = Get-Command "frpc.exe" -ErrorAction SilentlyContinue
    if ($existing) { return $existing.Source }

    $url = Get-FrpcUrl
    Write-Host "  tai frpc: $url" -ForegroundColor Gray

    Ensure-Dirs
    $tmp = Join-Path $MINET_ROOT "_dl"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $archive = Join-Path $tmp "frp.zip"

    $ua      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    $lastErr = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", $ua)
            $wc.DownloadFile($url, $archive)
            if ((Get-Item $archive).Length -gt 100000) { $lastErr = $null; break }
            $lastErr = "file qua nho, co the redirect/error"
        } catch {
            $lastErr = $_.Exception.Message
            Write-Host "  tai lan $attempt fail: $lastErr" -ForegroundColor Yellow
            Start-Sleep 2
        }
    }
    if ($lastErr) {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        throw "Tai frpc that bai: $lastErr"
    }

    try {
        Expand-Archive -Path $archive -DestinationPath $tmp -Force
    } catch {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        throw "Khong giai nen duoc: $($_.Exception.Message)"
    }

    $found = Get-ChildItem -Path $tmp -Recurse -Filter "frpc.exe" | Select-Object -First 1
    if (-not $found) {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        throw "Khong tim thay frpc.exe trong archive."
    }

    try {
        Copy-Item $found.FullName $FRPC_TARGET -Force
    } catch {
        Remove-Named "frpc"
        Start-Sleep 1
        Copy-Item $found.FullName $FRPC_TARGET -Force
    }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  frpc: $FRPC_TARGET" -ForegroundColor Gray
    return $FRPC_TARGET
}

# ---------- Config ----------

function Read-Config {
    if (-not (Test-Path $CONFIG_JSON)) { throw "Chua co config. Chay: .\minet.ps1 install" }
    $cfg = Get-Content $CONFIG_JSON -Raw | ConvertFrom-Json
    try { Set-Proxy $cfg.proxy } catch { Write-Host "  proxy warn: $($_.Exception.Message)" -ForegroundColor Yellow }
    return $cfg
}

function Write-Config([pscustomobject]$cfg) {
    $cfg | ConvertTo-Json -Depth 5 | Set-Content $CONFIG_JSON -Encoding UTF8
}

# ---------- Prompts ----------

function Read-Email([string]$current = "") {
    if ($current) { return $current }
    while ($true) {
        $v = (Read-Host "Email").Trim()
        if ($v) { return $v }
        Write-Host "  Email khong duoc de trong." -ForegroundColor Yellow
    }
}

function Read-ProxySetting([string]$default = "") {
    Write-Host ""
    Write-Host "Proxy (cho API calls: fetch/heartbeat/update-ip, KHONG anh huong tunnel):"
    Write-Host "  - URL: socks5://host:port, http://user:pass@host:port, ..."
    Write-Host "  - Path toi file danh sach (mot dong mot URL)"
    Write-Host "  - Enter de khong dung proxy, 'none' de xoa proxy hien tai"
    if ($default) { $prompt = "Proxy [$default]" } else { $prompt = "Proxy [none]" }
    $v = (Read-Host $prompt).Trim()
    if (-not $v) { return $default }
    if ($v -in @('none','no','n','off')) { return "" }
    return $v
}

# ---------- Background process ----------

function Start-BgProcess([string]$name, [string[]]$cmd, [string]$logPath) {
    $logDir = Split-Path $logPath
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

    $exe = $cmd[0]
    $argList = if ($cmd.Count -gt 1) { $cmd[1..($cmd.Count - 1)] } else { @() }

    # Build arg string voi quoting dung cho exe co dau cach
    $argStr = ($argList | ForEach-Object {
        if ($_ -match '[\s"]') { "`"$($_ -replace '"','\"')`"" } else { $_ }
    }) -join ' '

    $si = New-Object System.Diagnostics.ProcessStartInfo
    $si.FileName               = $exe
    $si.Arguments              = $argStr
    $si.UseShellExecute        = $false
    $si.CreateNoWindow         = $true
    $si.RedirectStandardOutput = $true
    $si.RedirectStandardError  = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $si

    # Ghi stdout+stderr vao log qua event (khong dung Thread)
    $lp = $logPath
    $outHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($s, $e)
        if ($null -ne $e.Data) {
            try { Add-Content -Path $lp -Value $e.Data -Encoding UTF8 } catch {}
        }
    }
    $proc.add_OutputDataReceived($outHandler)
    $proc.add_ErrorDataReceived($outHandler)

    $proc.Start() | Out-Null
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()

    Save-Pid $name $proc.Id
    return $proc.Id
}

# ---------- Builtin proxy server (chay qua Start-Job) ----------

$PROXY_SERVER_CODE = @'
param([int]$ListenPort, [string]$LogFile)
try {
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $ListenPort)
    $listener.Start()
    Add-Content -Path $LogFile -Value "builtin-proxy listening 127.0.0.1:$ListenPort" -Encoding UTF8
} catch {
    Add-Content -Path $LogFile -Value "proxy start error: $_" -Encoding UTF8
    return
}

# Pipe hai stream voi nhau; moi huong chay tren thread rieng
# Dung [System.Threading.ParameterizedThreadStart] de tranh ambiguous overload tren PS5
Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Threading;

public class ProxyHelper {
    public static void RunServer(object listenerObj) {
        var listener = (System.Net.Sockets.TcpListener)listenerObj;
        while (true) {
            try {
                System.Net.Sockets.TcpClient client = listener.AcceptTcpClient();
                Thread t = new Thread(new ParameterizedThreadStart(ProxyHelper.HandleClient));
                t.IsBackground = true;
                t.Start(client);
            } catch {}
        }
    }

    public static void Pipe(object state) {
        object[] args = (object[])state;
        Stream src = (Stream)args[0];
        Stream dst = (Stream)args[1];
        byte[] buf = new byte[65536];
        try {
            int n;
            while ((n = src.Read(buf, 0, buf.Length)) > 0)
                dst.Write(buf, 0, n);
        } catch {}
    }

    public static void HandleClient(object state) {
        TcpClient client = (TcpClient)state;
        try {
            client.ReceiveTimeout = 30000;
            NetworkStream ns = client.GetStream();
            byte[] buf = new byte[4096];
            StringBuilder sb = new StringBuilder();
            int total = 0;
            do {
                int n = ns.Read(buf, 0, buf.Length);
                if (n <= 0) return;
                sb.Append(Encoding.GetEncoding("Latin1").GetString(buf, 0, n));
                total += n;
            } while (sb.ToString().IndexOf("\r\n\r\n") < 0 && total < 16384);

            string raw = sb.ToString();
            string[] lines = raw.Split(new string[]{"\r\n"}, 2, StringSplitOptions.None);
            string[] parts = lines[0].Split(' ');
            if (parts.Length < 2) return;
            string method = parts[0].ToUpper();
            string target = parts[1];

            TcpClient upstream = null;
            if (method == "CONNECT") {
                int colon = target.LastIndexOf(':');
                if (colon < 0) return;
                string rHost = target.Substring(0, colon);
                int rPort = int.Parse(target.Substring(colon + 1));
                upstream = new TcpClient(rHost, rPort);
                byte[] reply = Encoding.ASCII.GetBytes("HTTP/1.1 200 Connection established\r\n\r\n");
                ns.Write(reply, 0, reply.Length);
            } else {
                int hi = raw.IndexOf("Host:", StringComparison.OrdinalIgnoreCase);
                if (hi >= 0) {
                    int end = raw.IndexOf("\r\n", hi);
                    string hostHdr = raw.Substring(hi + 5, end - hi - 5).Trim();
                    string rHost; int rPort;
                    int colon2 = hostHdr.LastIndexOf(':');
                    if (colon2 > 0) { rHost = hostHdr.Substring(0, colon2); rPort = int.Parse(hostHdr.Substring(colon2 + 1)); }
                    else { rHost = hostHdr; rPort = 80; }
                    upstream = new TcpClient(rHost, rPort);
                    byte[] rawBytes = Encoding.GetEncoding("Latin1").GetBytes(raw);
                    upstream.GetStream().Write(rawBytes, 0, rawBytes.Length);
                }
            }

            if (upstream != null) {
                client.ReceiveTimeout = 0;
                NetworkStream usns = upstream.GetStream();
                Thread t1 = new Thread(new ParameterizedThreadStart(ProxyHelper.Pipe));
                t1.IsBackground = true;
                t1.Start(new object[]{ usns, ns });
                try { ns.CopyTo(usns); } catch {}
                t1.Join(3000);
                try { upstream.Close(); } catch {}
            }
        } catch {}
        finally { try { client.Close(); } catch {} }
    }
}
"@

[ProxyHelper]::RunServer($listener)
'@

function Start-BuiltinProxy([int]$localPort) {
    Ensure-Dirs
    $logPath = Join-Path $LOG_DIR "tp.log"
    if (-not (Test-Path $logPath)) { "" | Set-Content $logPath -Encoding UTF8 }

    $tmpScript = Join-Path $MINET_ROOT "_proxy.ps1"
    Set-Content $tmpScript $PROXY_SERVER_CODE -Encoding UTF8

    $pidVal = Start-BgProcess "tinyproxy" @(
        "powershell.exe",
        "-NonInteractive",
        "-ExecutionPolicy", "Bypass",
        "-File", $tmpScript,
        "-ListenPort", [string]$localPort,
        "-LogFile", $logPath
    ) $logPath
    Write-Host "  builtin-proxy pid=$pidVal (port $localPort)" -ForegroundColor Gray
    return $pidVal
}

function Start-TinyProxy([pscustomobject]$cfg) {
    if ($cfg.local_port) { $localPort = [int]$cfg.local_port } else { $localPort = 8888 }
    Remove-Named "tinyproxy"
    return Start-BuiltinProxy $localPort
}

function Start-Frpc {
    if (-not (Test-Path $TUN_TOML)) { throw "Thieu $TUN_TOML. Chay 'install' truoc." }
    $frpcPath = $FRPC_TARGET
    if (-not (Test-Path $frpcPath)) {
        $found = Get-Command "frpc.exe" -ErrorAction SilentlyContinue
        if ($found) { $frpcPath = $found.Source } else { throw "Chua co frpc. Chay 'install' truoc." }
    }

    Remove-Named "frpc"
    $tunLog = Join-Path $LOG_DIR "tun.log"
    Ensure-Dirs

    $pidVal = Start-BgProcess "frpc" @($frpcPath, "-c", $TUN_TOML) $tunLog
    Write-Host "  frpc pid=$pidVal" -ForegroundColor Gray

    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep 1
        try {
            $log = Get-Content $tunLog -Raw -ErrorAction SilentlyContinue
            if ($log -match "login to server success") {
                Write-Host "  frpc: login OK" -ForegroundColor Green
                return $pidVal
            }
        } catch {}
        if (-not (Test-PidAlive $pidVal)) {
            Write-Host "  frpc: die - xem logs/tun.log" -ForegroundColor Yellow
            return $pidVal
        }
    }
    Write-Host "  frpc: chua thay 'login success' (xem logs/tun.log)" -ForegroundColor Yellow
    return $pidVal
}

# ---------- Worker loop ----------

function Start-WorkerLoop {
    $cfg = Read-Config
    $email = $cfg.email
    if (-not $cfg.remote_port) { throw "Config thieu remote_port." }
    $portEnc  = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$cfg.remote_port))
    $emailEnc = Invoke-UrlEncode $email

    try {
        $ip = Get-PublicIp
        if ($ip) {
            Invoke-HttpPostJson "$BASE_URL/api/minecoin/update-ip" @{ email=$email; port=$portEnc; ip=$ip } | Out-Null
            Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] update-ip $ip" -ForegroundColor Gray
        }
    } catch { Write-Host "update-ip err: $($_.Exception.Message)" -ForegroundColor Yellow }

    $ok = 0; $err = 0
    while ($true) {
        try {
            $ch = (Invoke-HttpGet "$BASE_URL/api/minecoin/challenge?email=$emailEnc&port=$portEnc").Trim()
            if ($ch) {
                $tokenBytes = [Convert]::FromBase64String($ch)
                $resp = [Convert]::ToBase64String($tokenBytes)
                Invoke-HttpPostJson "$BASE_URL/api/minecoin/verify" @{ email=$email; port=$portEnc; response=$resp } | Out-Null
                $ok++
                Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] ok (s=$ok e=$err)" -ForegroundColor Green
            }
        } catch {
            $err++
            $msg = $_.Exception.Message
            if ($msg.Length -gt 80) { $msg = $msg.Substring(0, 80) }
            Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] err: $msg (s=$ok e=$err)" -ForegroundColor Red
        }
        Start-Sleep $INTERVAL
    }
}

function Start-WorkerBg {
    $scriptFile = $PSCommandPath
    $pidVal = Start-BgProcess "worker" @(
        "powershell.exe",
        "-NonInteractive",
        "-ExecutionPolicy", "Bypass",
        "-File", $scriptFile,
        "worker"
    ) (Join-Path $LOG_DIR "worker.log")
    return $pidVal
}

# ---------- Commands ----------

function Cmd-Install {
    Ensure-Dirs
    $email    = Read-Email $Email
    if ($Proxy) { $proxySrc = $Proxy } else { $proxySrc = Read-ProxySetting }
    try { Set-Proxy $proxySrc } catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow; $proxySrc = "" }

    Write-Host "[1/4] Fetch cau hinh..." -ForegroundColor Cyan
    $result   = Get-SetupScript $email
    $rawScript = $result[0]
    $ip        = $result[1]
    $files     = Get-EmbeddedFiles $rawScript

    if ($files.Count -eq 0) {
        $dbg = Join-Path $env:TEMP "minet_setup_debug.sh"
        Set-Content $dbg $rawScript -Encoding UTF8
        throw "Khong trich duoc file. Xem $dbg"
    }

    Write-Host "[2/4] Ghi cau hinh (.toml / .conf)..." -ForegroundColor Cyan
    $localPaths = @{}
    foreach ($kv in $files.GetEnumerator()) {
        $fPath = $kv.Key
        $fData = $kv.Value
        if (-not ($fPath -match '\.(toml|conf)$')) { continue }
        $fBase   = Split-Path $fPath -Leaf
        $fTarget = Join-Path $MINET_ROOT $fBase
        $fDir    = Split-Path $fTarget
        if (-not (Test-Path $fDir)) { New-Item -ItemType Directory -Path $fDir -Force | Out-Null }
        [System.IO.File]::WriteAllBytes($fTarget, $fData)
        $localPaths[$fBase] = $fTarget
        Write-Host "  $fTarget ($($fData.Length) bytes)" -ForegroundColor Gray
    }

    # Parse tun.toml
    if ($localPaths["tun.toml"]) { $tunPath = $localPaths["tun.toml"] } else { $tunPath = $TUN_TOML }
    if (Test-Path $tunPath) { $tun = Get-Content $tunPath -Raw } else { $tun = "" }

    if ($tun -match 'remotePort\s*=\s*(\d+)')    { $rp = [int]$Matches[1] } else { $rp = $null }
    if ($tun -match 'serverAddr\s*=\s*"([^"]+)"') { $sa = $Matches[1] }     else { $sa = $null }
    if ($tun -match 'serverPort\s*=\s*(\d+)')    { $sp = [int]$Matches[1] } else { $sp = $null }
    if ($tun -match 'localPort\s*=\s*(\d+)')     { $lp = [int]$Matches[1] } else { $lp = 8888 }

    $cfg = [pscustomobject]@{
        email       = $email
        ip          = $ip
        proxy       = $proxySrc
        remote_port = $rp
        server_addr = $sa
        server_port = $sp
        local_port  = $lp
    }
    Write-Config $cfg

    Write-Host "[3/4] Kiem tra binary..." -ForegroundColor Cyan
    $frpcBin = Install-Frpc
    Write-Host "  frpc: $frpcBin" -ForegroundColor Gray
    Write-Host "  HTTP proxy: builtin PowerShell proxy." -ForegroundColor Gray

    Write-Host "[4/4] Xong." -ForegroundColor Green
    Write-Host "  remote ${sa}:${sp} -> tunnel port $rp" -ForegroundColor Gray
}

function Cmd-Start {
    Ensure-Dirs
    $cfg = Read-Config
    Write-Host "Starting..." -ForegroundColor Cyan
    Start-TinyProxy $cfg | Out-Null
    Start-Frpc | Out-Null
    $pidVal = Start-WorkerBg
    Write-Host "  worker pid=$pidVal" -ForegroundColor Gray
    Write-Host "Done." -ForegroundColor Green
}

function Cmd-Stop {
    foreach ($n in @("worker","frpc","tinyproxy")) { Remove-Named $n }
    Write-Host "Stopped." -ForegroundColor Green
}

function Cmd-Status {
    foreach ($n in @("tinyproxy","frpc","worker")) {
        $pidVal = Read-Pid $n
        if (Test-PidAlive $pidVal) { $state = "running" } else { $state = "stopped" }
        if ($null -eq $pidVal) { $pidStr = "-" } else { $pidStr = [string]$pidVal }
        Write-Host ("  {0,-10} {1,-8} pid={2}" -f $n, $state, $pidStr)
    }
}

function Cmd-DashboardStatus {
    $workerAlive = Test-PidAlive (Read-Pid "worker")
    $frpcAlive   = Test-PidAlive (Read-Pid "frpc")
    if ($workerAlive) { Write-Host "Mining: running" } else { Write-Host "Mining: stopped" }
    if ($frpcAlive)   { Write-Host "Tunnel: running" } else { Write-Host "Tunnel: stopped" }
}

function Cmd-Dashboard([string]$action = "status") {
    switch ($action.ToLower()) {
        "start"     { Cmd-Start }
        "stop"      { Cmd-Stop }
        "restart"   { Cmd-Stop; Cmd-Start }
        "status"    { Cmd-DashboardStatus }
        "logs"      { Cmd-Logs "worker" 20 }
        "uninstall" { Cmd-Uninstall }
        default     { Write-Host "Usage: minet dashboard {start|stop|status|restart|logs|uninstall}"; exit 1 }
    }
}

function Cmd-Logs([string]$target = "worker", [int]$numLines = 50) {
    $map = @{ worker = "worker.log"; tunnel = "tun.log"; tp = "tp.log" }
    if (-not $map.ContainsKey($target)) { Write-Host "Target phai la: worker, tunnel, tp"; return }
    $logPath = Join-Path $LOG_DIR $map[$target]
    if (-not (Test-Path $logPath)) { Write-Host "no log: $logPath"; return }
    Get-Content $logPath -Tail $numLines
}

function Cmd-Run {
    Ensure-Dirs
    $cfg = Read-Config
    Write-Host "Foreground run. Ctrl+C de dung." -ForegroundColor Cyan
    Start-TinyProxy $cfg | Out-Null
    Start-Frpc | Out-Null
    try {
        Start-WorkerLoop
    } finally {
        Cmd-Stop
    }
}

function Cmd-Worker {
    Start-WorkerLoop
}

function Cmd-Proxy {
    if (-not (Test-Path $CONFIG_JSON)) { throw "Chua co config. Chay 'install' truoc." }
    $cfg     = Get-Content $CONFIG_JSON -Raw | ConvertFrom-Json
    $current = $cfg.proxy
    if ($Proxy) { $newProxy = $Proxy } else { $newProxy = Read-ProxySetting $current }
    try { Set-Proxy $newProxy } catch { Write-Host "Loi: $($_.Exception.Message)" -ForegroundColor Red; return }
    $cfg | Add-Member -MemberType NoteProperty -Name proxy -Value $newProxy -Force
    Write-Config $cfg
    if ($newProxy) { Write-Host "Da luu proxy: $newProxy" -ForegroundColor Green } else { Write-Host "Da luu proxy: none" -ForegroundColor Green }
    Write-Host "Can 'stop' roi 'start' lai de worker ap dung proxy moi." -ForegroundColor Yellow
}

function Cmd-Link {
    Ensure-Dirs
    $scriptFile  = $PSCommandPath
    $launcher    = Join-Path $MINET_ROOT "minet.cmd"
    $cmdContent  = "@echo off`r`npowershell.exe -NonInteractive -ExecutionPolicy Bypass -File `"$scriptFile`" %*`r`n"
    Set-Content $launcher -Value $cmdContent -Encoding UTF8
    Write-Host "Da tao: $launcher" -ForegroundColor Green

    $bashLauncher = Join-Path $MINET_ROOT "minet"
    $bashContent  = "#!/bin/sh`nexec powershell.exe -NonInteractive -ExecutionPolicy Bypass -File `"$scriptFile`" `"`$@`"`n"
    Set-Content $bashLauncher -Value $bashContent -Encoding UTF8
    Write-Host "Da tao (bash): $bashLauncher" -ForegroundColor Green
    return $launcher
}

function Add-WindowsPath([string]$folder) {
    try {
        $regPath = "HKCU:\Environment"
        $existing = (Get-ItemProperty -Path $regPath -Name PATH -ErrorAction SilentlyContinue).PATH
        if (-not $existing) { $existing = "" }
        $parts = @($existing -split ';' | Where-Object { $_ -ne "" })
        $already = $parts | Where-Object { [System.IO.Path]::GetFullPath($_) -eq [System.IO.Path]::GetFullPath($folder) }
        if ($already) { return $false }
        $parts += $folder
        $newPath = $parts -join ';'
        Set-ItemProperty -Path $regPath -Name PATH -Value $newPath -Type ExpandString

        # Broadcast WM_SETTINGCHANGE
        $sig = 'using System;using System.Runtime.InteropServices;
public class WinEnv {
    [DllImport("user32.dll",CharSet=CharSet.Unicode)]
    public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,UIntPtr w,string l,uint f,uint t,out UIntPtr r);
}'
        Add-Type -TypeDefinition $sig -ErrorAction SilentlyContinue
        try {
            $result = [UIntPtr]::Zero
            [WinEnv]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result) | Out-Null
        } catch {}
        return $true
    } catch {
        Write-Host "  khong ghi duoc PATH: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

function Cmd-Setup {
    Write-Host "===== Minet Setup =====" -ForegroundColor Cyan
    Write-Host "  platform: Windows  root: $MINET_ROOT" -ForegroundColor Gray
    Write-Host ""

    # 1) Install
    $hasConfig = Test-Path $CONFIG_JSON
    $doInstall = $Force -or (-not $hasConfig)
    if ($hasConfig -and -not $Force) {
        Write-Host "Da co config tai $CONFIG_JSON." -ForegroundColor Gray
        $ans = (Read-Host "Fetch lai cau hinh? [y/N]").Trim().ToLower()
        $doInstall = ($ans -eq "y" -or $ans -eq "yes")
    }
    if ($doInstall) {
        try { Cmd-Install } catch { Write-Host "Install fail: $($_.Exception.Message)" -ForegroundColor Red; return }
    }

    # 2) Launcher
    Write-Host ""
    Write-Host "----- Launcher -----" -ForegroundColor Cyan
    $launcher = Cmd-Link

    # 3) PATH
    if ($launcher) {
        $folder = Split-Path $launcher
        Write-Host ""
        Write-Host "----- PATH -----" -ForegroundColor Cyan
        if (Add-WindowsPath $folder) {
            Write-Host "Da them vao User PATH: $folder" -ForegroundColor Green
            Write-Host "Mo terminal MOI de 'minet' co tac dung." -ForegroundColor Yellow
        } else {
            Write-Host "PATH da co san: $folder" -ForegroundColor Gray
        }
        if ($env:PATH -notmatch [regex]::Escape($folder)) {
            $env:PATH = $env:PATH + ";" + $folder
        }
    }

    # 4) Start
    Write-Host ""
    Write-Host "----- Starting services -----" -ForegroundColor Cyan
    try { Cmd-Start } catch { Write-Host "Start fail: $($_.Exception.Message)" -ForegroundColor Red; return }

    # 5) Summary
    Write-Host ""
    Write-Host "===== Done =====" -ForegroundColor Green
    Write-Host "Su dung (mo terminal moi):"
    Write-Host "  minet status"
    Write-Host "  minet start"
    Write-Host "  minet stop"
    Write-Host "  minet logs"
    Write-Host ""
    Cmd-DashboardStatus
}

function Cmd-Uninstall {
    Cmd-Stop
    if (Test-Path $MINET_ROOT) { Remove-Item $MINET_ROOT -Recurse -Force }
    Write-Host "Uninstalled." -ForegroundColor Green
}

# ---------- Interactive Menu ----------

function Show-Menu {
    $menu = @(
        [pscustomobject]@{ key="setup";     desc="Setup     - one-shot: install + link + PATH + start" }
        [pscustomobject]@{ key="install";   desc="Install   - fetch cau hinh (hoi email + proxy)" }
        [pscustomobject]@{ key="start";     desc="Start     - chay tat ca o background" }
        [pscustomobject]@{ key="stop";      desc="Stop      - dung tat ca" }
        [pscustomobject]@{ key="status";    desc="Status    - xem trang thai tien trinh" }
        [pscustomobject]@{ key="run";       desc="Run       - chay foreground (Ctrl+C de dung)" }
        [pscustomobject]@{ key="logs";      desc="Logs      - xem log (worker/tunnel/tp)" }
        [pscustomobject]@{ key="proxy";     desc="Proxy     - xem/doi proxy" }
        [pscustomobject]@{ key="link";      desc="Link      - tao launcher 'minet' tren PATH" }
        [pscustomobject]@{ key="uninstall"; desc="Uninstall - go sach" }
        [pscustomobject]@{ key="exit";      desc="Exit      - thoat" }
    )

    while ($true) {
        Write-Host ""
        Write-Host "===== Minet Manager =====" -ForegroundColor Cyan
        Write-Host "  (platform: Windows, root: $MINET_ROOT)" -ForegroundColor Gray
        for ($i = 0; $i -lt $menu.Count; $i++) {
            Write-Host "  $($i+1). $($menu[$i].desc)"
        }

        $choice = (Read-Host "Chon so (hoac ten)").Trim().ToLower()
        $selected = $null

        if ($choice -match '^\d+$') {
            $idx = [int]$choice - 1
            if ($idx -ge 0 -and $idx -lt $menu.Count) { $selected = $menu[$idx] }
        } else {
            $selected = $menu | Where-Object { $_.key -eq $choice } | Select-Object -First 1
        }

        if (-not $selected) { Write-Host "Lua chon khong hop le." -ForegroundColor Yellow; continue }
        if ($selected.key -eq "exit") { return }

        if ($selected.key -eq "logs") {
            $t = (Read-Host "Target (worker/tunnel/tp) [worker]").Trim()
            if (-not $t) { $t = "worker" }
            if ($t -notin @("worker","tunnel","tp")) { Write-Host "Target khong hop le." -ForegroundColor Yellow; continue }
            $ln = (Read-Host "So dong [50]").Trim()
            if (-not $ln) { $ln = "50" }
            try { Cmd-Logs $t ([int]$ln) } catch { Write-Host "Loi: $($_.Exception.Message)" -ForegroundColor Red }
            continue
        }

        try {
            switch ($selected.key) {
                "setup"     { Cmd-Setup }
                "install"   { Cmd-Install }
                "start"     { Cmd-Start }
                "stop"      { Cmd-Stop }
                "status"    { Cmd-Status }
                "run"       { Cmd-Run }
                "proxy"     { Cmd-Proxy }
                "link"      { Cmd-Link | Out-Null }
                "uninstall" { Cmd-Uninstall }
            }
        } catch { Write-Host "Loi: $($_.Exception.Message)" -ForegroundColor Red }
    }
}

# ---------- Main ----------

switch ($Command.ToLower()) {
    ""           { Show-Menu }
    "setup"      { Cmd-Setup }
    "install"    { Cmd-Install }
    "start"      { Cmd-Start }
    "stop"       { Cmd-Stop }
    "status"     { Cmd-Status }
    "run"        { Cmd-Run }
    "worker"     { Cmd-Worker }
    "proxy"      { Cmd-Proxy }
    "link"       { Cmd-Link | Out-Null }
    "uninstall"  { Cmd-Uninstall }
    "logs"       {
        if ($Arg1) { $tgt = $Arg1 } else { $tgt = "worker" }
        Cmd-Logs $tgt $Lines
    }
    "dashboard"  {
        if ($Arg1) { $act = $Arg1 } else { $act = "status" }
        Cmd-Dashboard $act
    }
    default { Write-Host "Unknown command: $Command. Bo tham so de vao menu." -ForegroundColor Red; exit 1 }
}
