#!/usr/bin/env pwsh
<#
.SYNOPSIS
    minet.ps1 - Quan ly Minet tunnel + worker tren Windows (PowerShell).

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
    .\minet.ps1 setup --email me@example.com
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

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------- Constants ----------

$BASE_URL   = "https://dashboard.minet.vn"
$INTERVAL   = 30
$FRP_VERSION = "0.61.1"

$_base      = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $HOME }
$MINET_ROOT = Join-Path $_base "minet"
$LOG_DIR    = Join-Path $MINET_ROOT "logs"
$PID_DIR    = Join-Path $MINET_ROOT "pids"
$TUN_TOML   = Join-Path $MINET_ROOT "tun.toml"
$CONFIG_JSON = Join-Path $MINET_ROOT "config.json"
$FRPC_TARGET = Join-Path $MINET_ROOT "frpc.exe"
$TP_CONF    = Join-Path $MINET_ROOT "tinyproxy.conf"

# ---------- Directories ----------

function Ensure-Dirs {
    foreach ($d in @($MINET_ROOT, $LOG_DIR, $PID_DIR)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

# ---------- PID helpers ----------

function PidFile([string]$name) { Join-Path $PID_DIR "$name.pid" }

function Save-Pid([string]$name, [int]$pid) {
    Set-Content -Path (PidFile $name) -Value $pid -Encoding UTF8
}

function Read-Pid([string]$name) {
    $f = PidFile $name
    if (-not (Test-Path $f)) { return $null }
    $v = (Get-Content $f -Raw -ErrorAction SilentlyContinue).Trim()
    if ($v -match '^\d+$') { return [int]$v }
    return $null
}

function Pid-Alive([object]$pid) {
    if ($null -eq $pid) { return $false }
    try {
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        return ($null -ne $proc)
    } catch { return $false }
}

function Kill-Pid([object]$pid) {
    if ($null -eq $pid) { return }
    try {
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($proc) { $proc | Stop-Process -Force -ErrorAction SilentlyContinue }
    } catch {}
}

function Kill-Named([string]$name) {
    $pid = Read-Pid $name
    if ($pid -and (Pid-Alive $pid)) { Kill-Pid $pid }
    $f = PidFile $name
    if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
}

# ---------- Proxy state ----------

$script:_proxies   = @()
$script:_proxyIdx  = 0

$PROXY_RX = [regex]'(?i)^(?<scheme>socks5h?|socks4|http|https)://(?:(?<user>[^:@]+):(?<pw>[^@]+)@)?(?<host>[^:]+):(?<port>\d+)/?$'

function Load-ProxySource([string]$src) {
    if (-not $src) { return @() }
    if (Test-Path $src -PathType Leaf) {
        return (Get-Content $src | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() })
    }
    return @($src.Trim())
}

function Configure-Proxy([string]$src) {
    $script:_proxies  = @()
    $script:_proxyIdx = 0
    if (-not $src) { return }
    $list = @(Load-ProxySource $src)
    if (-not $list) { Write-Host "  proxy: khong load duoc tu '$src'" -ForegroundColor Yellow; return }
    $valid = @($list | Where-Object { $PROXY_RX.IsMatch($_) })
    $bad   = @($list | Where-Object { -not $PROXY_RX.IsMatch($_) })
    if ($bad) { Write-Host "  proxy: bo qua URL sai format: $($bad[0..2] -join ', ')" -ForegroundColor Yellow }
    if (-not $valid) { return }
    $script:_proxies = $valid
    Write-Host "  proxy: $($script:_proxies.Count) entry" -ForegroundColor Gray
}

function Pick-Proxy {
    if (-not $script:_proxies) { return $null }
    $p = $script:_proxies[$script:_proxyIdx % $script:_proxies.Count]
    $script:_proxyIdx++
    return $p
}

# ---------- HTTP helpers ----------

function Http-Get([string]$url, [int]$timeout = 20) {
    return Http-Request $url $null $null $timeout
}

function Http-PostJson([string]$url, [hashtable]$data, [int]$timeout = 15) {
    $body = $data | ConvertTo-Json -Compress
    return Http-Request $url $body "application/json" $timeout
}

function Http-Request([string]$url, [string]$body, [string]$contentType, [int]$timeout) {
    $proxy = Pick-Proxy
    $headers = @{
        "User-Agent"      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        "Accept"          = "*/*"
        "Accept-Language" = "en-US,en;q=0.9"
        "Referer"         = "$BASE_URL/"
    }
    $params = @{
        Uri                = $url
        Headers            = $headers
        UseBasicParsing    = $true
        TimeoutSec         = $timeout
    }
    if ($body) {
        $params["Method"]      = "POST"
        $params["Body"]        = [System.Text.Encoding]::UTF8.GetBytes($body)
        $params["ContentType"] = $contentType
    }
    if ($proxy) {
        $params["Proxy"] = $proxy
        $params["ProxyUseDefaultCredentials"] = $false
        if ($proxy -match '^(?<scheme>https?)://(?:(?<u>[^:@]+):(?<p>[^@]+)@)') {
            $cred = New-Object System.Management.Automation.PSCredential(
                $Matches['u'],
                (ConvertTo-SecureString $Matches['p'] -AsPlainText -Force)
            )
            $params["ProxyCredential"] = $cred
        }
    }
    $resp = Invoke-WebRequest @params
    return $resp.Content
}

function Public-Ip {
    $sources = @("https://api.ipify.org", "https://icanhazip.com", "https://ifconfig.me/ip", "https://api4.my-ip.io/ip")
    foreach ($src in $sources) {
        try {
            $ip = (Invoke-RestMethod -Uri $src -TimeoutSec 10).Trim()
            if ($ip) { return $ip }
        } catch {}
    }
    return ""
}

# ---------- Fetch + extract setup script ----------

function Url-Encode([string]$s) { [System.Uri]::EscapeDataString($s) }

function Fetch-SetupScript([string]$email) {
    $ip = Public-Ip
    if (-not $ip) { throw "Khong lay duoc IP public." }
    $url = "$BASE_URL/api/minecoin/setup?email=$(Url-Encode $email)&ip=$(Url-Encode $ip)&mode=dashboard"
    $raw = (Http-Get $url 30).Trim()
    # Neu la base64 thuan tuy thi giai ma
    if ($raw -match '^[A-Za-z0-9+/\s]+=*$') {
        try {
            $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($raw -replace '\s','')))
            if ($decoded) { $raw = $decoded }
        } catch {}
    }
    return $raw, $ip
}

function Extract-Embedded([string]$script) {
    # Giai nen outer wrapper neu co (printf "%b" "..." | base64 -d | sh)
    $unwrapRx = [regex]'(?ms)printf\s+"%[bs]"\s+"([A-Za-z0-9+/=\\\n\s]+?)"\s*\|\s*base64\s+-d\s*\|\s*sh'
    for ($i = 0; $i -lt 5; $i++) {
        $m = $unwrapRx.Match($script)
        if (-not $m.Success) { break }
        try {
            $inner = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($m.Groups[1].Value -replace '\\n|\s','')))
            if ($inner -match 'printf' -and $inner -match 'base64') { $script = $inner } else { break }
        } catch { break }
    }

    $fileRx = [regex]'(?ms)printf\s+"%[bs]"\s+"([A-Za-z0-9+/=\\\n\s]+?)"\s*\|\s*base64\s+-d\s*>\s*("?[^"\n]+?"?)\s*$'
    $out = @{}
    foreach ($m in $fileRx.Matches($script)) {
        try {
            $data = [Convert]::FromBase64String(($m.Groups[1].Value -replace '\\n|\s',''))
            $path = $m.Groups[2].Value.Trim().Trim('"')
            $path = $path -replace '\$MR', $MINET_ROOT -replace '\$PREFIX', ''
            $out[$path] = $data
        } catch {}
    }
    return $out
}

# ---------- frpc download ----------

function FrpcDownloadUrl {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
    $fa = switch ($arch) {
        "X64"   { "amd64" }
        "Arm64" { "arm64" }
        "X86"   { "386" }
        default { throw "Kien truc khong ho tro: $arch" }
    }
    $url = "https://github.com/fatedier/frp/releases/download/v$FRP_VERSION/frp_${FRP_VERSION}_windows_${fa}.zip"
    return $url
}

function Download-Frpc {
    if (Test-Path $FRPC_TARGET) { return $FRPC_TARGET }
    $existing = Get-Command "frpc.exe" -ErrorAction SilentlyContinue
    if ($existing) { return $existing.Source }

    $url = FrpcDownloadUrl
    Write-Host "  tai frpc: $url" -ForegroundColor Gray

    Ensure-Dirs
    $tmp = Join-Path $MINET_ROOT "_dl"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $archive = Join-Path $tmp "frp.zip"

    $ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    $lastErr = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers["User-Agent"] = $ua
            $wc.DownloadFile($url, $archive)
            if ((Get-Item $archive).Length -gt 100000) { $lastErr = $null; break }
            $lastErr = "file qua nho, co the redirect/error"
        } catch {
            $lastErr = $_
            Write-Host "  tai lan $attempt fail: $_" -ForegroundColor Yellow
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
        throw "Khong giai nen duoc: $_"
    }

    $found = Get-ChildItem -Path $tmp -Recurse -Filter "frpc.exe" | Select-Object -First 1
    if (-not $found) {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        throw "Khong tim thay frpc.exe trong archive."
    }

    $dest = $FRPC_TARGET
    try {
        Copy-Item $found.FullName $dest -Force
    } catch {
        # frpc dang chay -> stop truoc
        Kill-Named "frpc"
        Start-Sleep 1
        Copy-Item $found.FullName $dest -Force
    }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  frpc: $dest" -ForegroundColor Gray
    return $dest
}

# ---------- Config ----------

function Load-Config {
    if (-not (Test-Path $CONFIG_JSON)) { throw "Chua co config. Chay: .\minet.ps1 install" }
    $cfg = Get-Content $CONFIG_JSON -Raw | ConvertFrom-Json
    try { Configure-Proxy $cfg.proxy } catch { Write-Host "  proxy warn: $_" -ForegroundColor Yellow }
    return $cfg
}

function Save-Config([pscustomobject]$cfg) {
    $cfg | ConvertTo-Json -Depth 5 | Set-Content $CONFIG_JSON -Encoding UTF8
}

# ---------- Prompts ----------

function Prompt-Email([string]$current = "") {
    if ($current) { return $current }
    while ($true) {
        $v = (Read-Host "Email").Trim()
        if ($v) { return $v }
        Write-Host "  Email khong duoc de trong." -ForegroundColor Yellow
    }
}

function Prompt-Proxy([string]$default = "") {
    Write-Host ""
    Write-Host "Proxy (cho API calls: fetch/heartbeat/update-ip, KHONG anh huong tunnel):"
    Write-Host "  - URL: socks5://host:port, http://user:pass@host:port, ..."
    Write-Host "  - Path toi file danh sach (mot dong mot URL)"
    Write-Host "  - Enter de khong dung proxy, 'none' de xoa proxy hien tai"
    $v = (Read-Host "Proxy [$( if($default){'$default'}else{'none'} )]").Trim()
    if (-not $v) { return $default }
    if ($v -in @('none','no','n','off')) { return "" }
    return $v
}

# ---------- Background process ----------

function Start-Bg([string]$name, [string[]]$cmd, [string]$logPath) {
    $logDir = Split-Path $logPath
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $si = New-Object System.Diagnostics.ProcessStartInfo
    $si.FileName  = $cmd[0]
    if ($cmd.Count -gt 1) { $si.Arguments = ($cmd[1..($cmd.Count-1)] | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' ' }
    $si.UseShellExecute        = $false
    $si.RedirectStandardOutput = $true
    $si.RedirectStandardError  = $true
    $si.WindowStyle            = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $si.CreateNoWindow         = $true
    $proc = [System.Diagnostics.Process]::Start($si)
    Save-Pid $name $proc.Id

    # Pipe stdout+stderr -> log file asynchronously
    $log = $logPath
    $script:_bgStreams = @()
    foreach ($stream in @($proc.StandardOutput, $proc.StandardError)) {
        $s = $stream
        $t = [System.Threading.Thread]::new({
            param($reader, $lp)
            try {
                $sw = [System.IO.File]::AppendText($lp)
                while (-not $reader.EndOfStream) {
                    $line = $reader.ReadLine()
                    $sw.WriteLine($line)
                    $sw.Flush()
                }
                $sw.Close()
            } catch {}
        })
        $t.IsBackground = $true
        $t.Start($s, $log)
    }
    return $proc.Id
}

# ---------- Proxy server (builtin .NET) ----------

function Start-BuiltinProxy([int]$localPort) {
    # Chay trong background job (PowerShell job)
    $job = Start-Job -ScriptBlock {
        param($port)
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
        $listener.Start()
        Write-Host "builtin-proxy listening 127.0.0.1:$port"
        while ($true) {
            $client = $listener.AcceptTcpClient()
            $jb = [System.Threading.Thread]::new({
                param($c)
                try {
                    $c.ReceiveTimeout = 30000
                    $ns = $c.GetStream()
                    $buf = New-Object byte[] 16384
                    $sb  = New-Object System.Text.StringBuilder
                    $totalRead = 0
                    do {
                        $n = $ns.Read($buf, 0, $buf.Length)
                        if ($n -le 0) { return }
                        $sb.Append([System.Text.Encoding]::Latin1.GetString($buf, 0, $n)) | Out-Null
                        $totalRead += $n
                    } while (-not $sb.ToString().Contains("`r`n`r`n") -and $totalRead -lt 16384)

                    $raw      = $sb.ToString()
                    $firstLine = ($raw -split "`r`n")[0]
                    $parts    = $firstLine -split ' '
                    if ($parts.Count -lt 2) { return }
                    $method = $parts[0].ToUpper()
                    $target = $parts[1]

                    $upstream = $null
                    if ($method -eq "CONNECT") {
                        $hp   = $target -split ':'
                        $host = $hp[0]; $port = [int]($hp.Count -gt 1 ? $hp[1] : 443)
                        $upstream = New-Object System.Net.Sockets.TcpClient($host, $port)
                        $reply = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 Connection established`r`n`r`n")
                        $ns.Write($reply, 0, $reply.Length)
                    } else {
                        if ($raw -match '(?i)Host:\s*([^\r\n]+)') {
                            $hostHdr = $Matches[1].Trim()
                            if ($hostHdr -match ':') { $h,$p = $hostHdr -split ':'; $port = [int]$p } else { $h = $hostHdr; $p = 80 }
                            $upstream = New-Object System.Net.Sockets.TcpClient($h, [int]$p)
                            $usns = $upstream.GetStream()
                            $rawBytes = [System.Text.Encoding]::Latin1.GetBytes($raw)
                            $usns.Write($rawBytes, 0, $rawBytes.Length)
                        }
                    }

                    if ($null -ne $upstream) {
                        $usns = $upstream.GetStream()
                        $c.ReceiveTimeout = 0
                        # Bidirectional pipe
                        $done = [System.Threading.ManualResetEventSlim]::new($false)
                        $t1 = [System.Threading.Thread]::new({
                            param($a,$b,$ev)
                            try { $a.CopyTo($b) } catch {}
                            try { $ev.Set() } catch {}
                        })
                        $t1.IsBackground = $true
                        $t1.Start($usns, $ns, $done)
                        try { $ns.CopyTo($usns) } catch {}
                        $done.Wait(5000) | Out-Null
                        $t1.Join(1000) | Out-Null
                    }
                } catch {} finally {
                    try { $c.Close() } catch {}
                }
            })
            $jb.IsBackground = $true
            $jb.Start($client) | Out-Null
        }
    } -ArgumentList $localPort
    return $job.Id
}

function Start-TinyProxy([pscustomobject]$cfg) {
    $localPort = if ($cfg.local_port) { [int]$cfg.local_port } else { 8888 }
    Kill-Named "tinyproxy"
    $jobId = Start-BuiltinProxy $localPort
    # Luu job id vao pid file de tracking
    Save-Pid "tinyproxy" $jobId
    Write-Host "  builtin-proxy job=$jobId (port $localPort)" -ForegroundColor Gray
    return $jobId
}

function Start-Frpc {
    if (-not (Test-Path $TUN_TOML)) { throw "Thieu $TUN_TOML. Chay 'install' truoc." }
    $frpc = $FRPC_TARGET
    if (-not (Test-Path $frpc)) {
        $found = Get-Command "frpc.exe" -ErrorAction SilentlyContinue
        if ($found) { $frpc = $found.Source } else { throw "Chua co frpc. Chay 'install' truoc." }
    }

    Kill-Named "frpc"
    $tunLog = Join-Path $LOG_DIR "tun.log"
    Ensure-Dirs
    if (-not (Test-Path $tunLog)) { "" | Set-Content $tunLog -Encoding UTF8 }

    $pid = Start-Bg "frpc" @($frpc, "-c", $TUN_TOML) $tunLog
    Write-Host "  frpc pid=$pid" -ForegroundColor Gray

    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep 1
        try {
            $log = Get-Content $tunLog -Raw -ErrorAction SilentlyContinue
            if ($log -match "login to server success") {
                Write-Host "  frpc: login OK" -ForegroundColor Green
                return $pid
            }
        } catch {}
        if (-not (Pid-Alive $pid)) {
            Write-Host "  frpc: die - xem logs/tun.log" -ForegroundColor Yellow
            return $pid
        }
    }
    Write-Host "  frpc: chua thay 'login success' (xem logs/tun.log)" -ForegroundColor Yellow
    return $pid
}

# ---------- Worker loop ----------

function Worker-Loop([scriptblock]$stopFn = { $false }) {
    $cfg = Load-Config
    $email = $cfg.email
    if (-not $cfg.remote_port) { throw "Config thieu remote_port." }
    $portEnc  = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$cfg.remote_port))
    $emailEnc = Url-Encode $email

    # Update IP
    try {
        $ip = Public-Ip
        if ($ip) {
            Http-PostJson "$BASE_URL/api/minecoin/update-ip" @{ email=$email; port=$portEnc; ip=$ip } | Out-Null
            Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] update-ip $ip" -ForegroundColor Gray
        }
    } catch { Write-Host "update-ip err: $_" -ForegroundColor Yellow }

    $ok = 0; $err = 0; $firstErrBody = $false
    while (-not (& $stopFn)) {
        try {
            $ch = (Http-Get "$BASE_URL/api/minecoin/challenge?email=$emailEnc&port=$portEnc").Trim()
            if ($ch) {
                $tokenBytes = [Convert]::FromBase64String($ch)
                $resp = [Convert]::ToBase64String($tokenBytes)
                Http-PostJson "$BASE_URL/api/minecoin/verify" @{ email=$email; port=$portEnc; response=$resp } | Out-Null
                $ok++
                Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] ok (s=$ok e=$err)" -ForegroundColor Green
            }
        } catch {
            $err++
            Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] err: $($_.ToString().Substring(0, [Math]::Min(80,$_.ToString().Length))) (s=$ok e=$err)" -ForegroundColor Red
        }
        for ($s = 0; $s -lt $INTERVAL; $s++) {
            if (& $stopFn) { return }
            Start-Sleep 1
        }
    }
}

function Start-WorkerBg {
    $script = $PSCommandPath
    $py = "pwsh"
    $pid = Start-Bg "worker" @($py, "-NonInteractive", "-File", $script, "worker") (Join-Path $LOG_DIR "worker.log")
    return $pid
}

# ---------- Commands ----------

function Cmd-Install {
    Ensure-Dirs
    $email = Prompt-Email $Email
    $proxySrc = if ($Proxy) { $Proxy } else { Prompt-Proxy }
    try { Configure-Proxy $proxySrc } catch { Write-Host "  $_" -ForegroundColor Yellow; $proxySrc = "" }

    Write-Host "[1/4] Fetch cau hinh..." -ForegroundColor Cyan
    $result   = Fetch-SetupScript $email
    $script   = $result[0]; $ip = $result[1]
    $files    = Extract-Embedded $script

    if (-not $files -or $files.Count -eq 0) {
        $dbg = Join-Path $env:TEMP "minet_setup_debug.sh"
        Set-Content $dbg $script -Encoding UTF8
        throw "Khong trich duoc file. Xem $dbg"
    }

    Write-Host "[2/4] Ghi cau hinh (.toml / .conf)..." -ForegroundColor Cyan
    $localPaths = @{}
    foreach ($kv in $files.GetEnumerator()) {
        $path = $kv.Key; $data = $kv.Value
        if (-not ($path -match '\.(toml|conf)$')) { continue }
        $base = Split-Path $path -Leaf
        $target = Join-Path $MINET_ROOT $base
        $dir = Split-Path $target
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllBytes($target, $data)
        $localPaths[$base] = $target
        Write-Host "  $target ($($data.Length) bytes)" -ForegroundColor Gray
    }

    # Parse tun.toml
    $tunPath = if ($localPaths["tun.toml"]) { $localPaths["tun.toml"] } else { $TUN_TOML }
    $tun = if (Test-Path $tunPath) { Get-Content $tunPath -Raw } else { "" }
    $rp  = if ($tun -match 'remotePort\s*=\s*(\d+)')    { [int]$Matches[1] } else { $null }
    $sa  = if ($tun -match 'serverAddr\s*=\s*"([^"]+)"') { $Matches[1] }    else { $null }
    $sp  = if ($tun -match 'serverPort\s*=\s*(\d+)')    { [int]$Matches[1] } else { $null }
    $lp  = if ($tun -match 'localPort\s*=\s*(\d+)')     { [int]$Matches[1] } else { 8888 }

    $cfg = [pscustomobject]@{
        email       = $email
        ip          = $ip
        proxy       = $proxySrc
        remote_port = $rp
        server_addr = $sa
        server_port = $sp
        local_port  = $lp
    }
    Save-Config $cfg

    Write-Host "[3/4] Kiem tra binary..." -ForegroundColor Cyan
    $frpc = Download-Frpc
    Write-Host "  frpc: $frpc" -ForegroundColor Gray
    Write-Host "  HTTP proxy: builtin PowerShell proxy." -ForegroundColor Gray

    Write-Host "[4/4] Xong." -ForegroundColor Green
    Write-Host "  remote $sa`:$sp -> tunnel port $rp" -ForegroundColor Gray
}

function Cmd-Start {
    Ensure-Dirs
    $cfg = Load-Config
    Write-Host "Starting..." -ForegroundColor Cyan
    Start-TinyProxy $cfg | Out-Null
    Start-Frpc | Out-Null
    $pid = Start-WorkerBg
    Write-Host "  worker pid=$pid" -ForegroundColor Gray
    Write-Host "Done." -ForegroundColor Green
}

function Cmd-Stop {
    foreach ($n in @("worker","frpc","tinyproxy")) {
        Kill-Named $n
    }
    # Kill background jobs theo job id neu con
    Get-Job -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Running" } | Stop-Job -ErrorAction SilentlyContinue
    Write-Host "Stopped." -ForegroundColor Green
}

function Cmd-Status {
    foreach ($n in @("tinyproxy","frpc","worker")) {
        $pid   = Read-Pid $n
        $state = if (Pid-Alive $pid) { "running" } else { "stopped" }
        Write-Host ("  {0,-10} {1,-8} pid={2}" -f $n, $state, ($pid ?? "-"))
    }
}

function Cmd-DashboardStatus {
    $worker = Pid-Alive (Read-Pid "worker")
    $frpc   = Pid-Alive (Read-Pid "frpc")
    Write-Host "Mining: $(if($worker){'running'}else{'stopped'})"
    Write-Host "Tunnel: $(if($frpc){'running'}else{'stopped'})"
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

function Cmd-Logs([string]$target = "worker", [int]$lines = 50) {
    $map = @{ worker="worker.log"; tunnel="tun.log"; tp="tp.log" }
    if (-not $map.ContainsKey($target)) { Write-Host "Target phai la: worker, tunnel, tp"; return }
    $path = Join-Path $LOG_DIR $map[$target]
    if (-not (Test-Path $path)) { Write-Host "no log: $path"; return }
    Get-Content $path -Tail $lines
}

function Cmd-Run {
    Ensure-Dirs
    $cfg = Load-Config
    Write-Host "Foreground run. Ctrl+C de dung." -ForegroundColor Cyan
    Start-TinyProxy $cfg | Out-Null
    Start-Frpc | Out-Null
    $stopped = $false
    try {
        Worker-Loop { $script:stopped }
    } finally {
        $script:stopped = $true
        Cmd-Stop
    }
}

function Cmd-Worker {
    Worker-Loop
}

function Cmd-Proxy {
    if (-not (Test-Path $CONFIG_JSON)) { throw "Chua co config. Chay 'install' truoc." }
    $cfg     = Get-Content $CONFIG_JSON -Raw | ConvertFrom-Json
    $current = $cfg.proxy
    $new     = if ($Proxy) { $Proxy } else { Prompt-Proxy $current }
    try { Configure-Proxy $new } catch { Write-Host "Loi: $_" -ForegroundColor Red; return }
    $cfg | Add-Member -MemberType NoteProperty -Name proxy -Value $new -Force
    Save-Config $cfg
    Write-Host "Da luu proxy: $(if($new){$new}else{'none'})" -ForegroundColor Green
    Write-Host "Can 'stop' roi 'start' lai de worker ap dung proxy moi." -ForegroundColor Yellow
}

function Cmd-Link {
    Ensure-Dirs
    $script  = $PSCommandPath
    $launcher = Join-Path $MINET_ROOT "minet.cmd"
    @"
@echo off
pwsh -NonInteractive -File "$script" %*
"@ | Set-Content $launcher -Encoding UTF8
    Write-Host "Da tao: $launcher" -ForegroundColor Green

    # Bash wrapper (Git Bash / WSL)
    $bashLauncher = Join-Path $MINET_ROOT "minet"
    "#!/bin/sh`nexec pwsh -NonInteractive -File `"$script`" `"`$@`"`n" | Set-Content $bashLauncher -Encoding UTF8 -NoNewline
    Write-Host "Da tao (bash): $bashLauncher" -ForegroundColor Green
    return $launcher
}

function _Add-WindowsPath([string]$folder) {
    try {
        $regPath = "HKCU:\Environment"
        $current = (Get-ItemProperty -Path $regPath -Name PATH -ErrorAction SilentlyContinue).PATH ?? ""
        $parts   = @($current -split ';' | Where-Object { $_ })
        if ($parts | Where-Object { [System.IO.Path]::GetFullPath($_) -eq [System.IO.Path]::GetFullPath($folder) }) {
            return $false
        }
        $parts += $folder
        $newPath = $parts -join ';'
        Set-ItemProperty -Path $regPath -Name PATH -Value $newPath -Type ExpandString
        # Broadcast WM_SETTINGCHANGE
        Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class WinMsg{[DllImport("user32.dll",CharSet=CharSet.Unicode)]public static extern IntPtr SendMessageTimeout(IntPtr hWnd,uint Msg,UIntPtr wParam,string lParam,uint fuFlags,uint uTimeout,out UIntPtr lpdwResult);}' -ErrorAction SilentlyContinue
        try { $r = [UIntPtr]::Zero; [WinMsg]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$r) | Out-Null } catch {}
        return $true
    } catch { Write-Host "  khong ghi duoc PATH: $_" -ForegroundColor Yellow; return $false }
}

function Cmd-Setup {
    Write-Host "===== Minet Setup =====" -ForegroundColor Cyan
    Write-Host "  platform: Windows  root: $MINET_ROOT" -ForegroundColor Gray
    Write-Host ""

    # 1) Install
    $hasConfig  = Test-Path $CONFIG_JSON
    $doInstall  = $Force -or (-not $hasConfig)
    if ($hasConfig -and -not $Force) {
        Write-Host "Da co config tai $CONFIG_JSON." -ForegroundColor Gray
        $ans = (Read-Host "Fetch lai cau hinh? [y/N]").Trim().ToLower()
        $doInstall = ($ans -in @("y","yes"))
    }
    if ($doInstall) {
        try { Cmd-Install } catch { Write-Host "Install fail: $_" -ForegroundColor Red; return }
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
        if (_Add-WindowsPath $folder) {
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
    try { Cmd-Start } catch { Write-Host "Start fail: $_" -ForegroundColor Red; return }

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

function Interactive-Menu {
    $menu = @(
        @{ key="setup";     desc="Setup     - one-shot: install + link + PATH + start"; fn={ Cmd-Setup } }
        @{ key="install";   desc="Install   - fetch cau hinh (hoi email + proxy)";     fn={ Cmd-Install } }
        @{ key="start";     desc="Start     - chay tat ca o background";                fn={ Cmd-Start } }
        @{ key="stop";      desc="Stop      - dung tat ca";                             fn={ Cmd-Stop } }
        @{ key="status";    desc="Status    - xem trang thai tien trinh";               fn={ Cmd-Status } }
        @{ key="run";       desc="Run       - chay foreground (Ctrl+C de dung)";        fn={ Cmd-Run } }
        @{ key="logs";      desc="Logs      - xem log (worker/tunnel/tp)";              fn={ $null } }
        @{ key="proxy";     desc="Proxy     - xem/doi proxy";                           fn={ Cmd-Proxy } }
        @{ key="link";      desc="Link      - tao launcher 'minet' tren PATH";          fn={ Cmd-Link | Out-Null } }
        @{ key="uninstall"; desc="Uninstall - go sach";                                 fn={ Cmd-Uninstall } }
        @{ key="exit";      desc="Exit      - thoat";                                   fn={ $null } }
    )

    while ($true) {
        Write-Host ""
        Write-Host "===== Minet Manager =====" -ForegroundColor Cyan
        Write-Host "  (platform: Windows, root: $MINET_ROOT)" -ForegroundColor Gray
        for ($i = 0; $i -lt $menu.Count; $i++) {
            Write-Host "  $($i+1). $($menu[$i].desc)"
        }
        try { $choice = (Read-Host "Chon so (hoac ten)").Trim().ToLower() } catch { Write-Host ""; return }

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
            try { Cmd-Logs $t ([int]$ln) } catch { Write-Host "Loi: $_" -ForegroundColor Red }
            continue
        }

        try { & $selected.fn }
        catch { Write-Host "Loi: $_" -ForegroundColor Red }
    }
}

# ---------- Main ----------

switch ($Command.ToLower()) {
    ""           { Interactive-Menu }
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
        $target = if ($Arg1) { $Arg1 } else { "worker" }
        Cmd-Logs $target $Lines
    }
    "dashboard"  {
        $action = if ($Arg1) { $Arg1 } else { "status" }
        Cmd-Dashboard $action
    }
    default      { Write-Host "Unknown command: $Command. Bo tham so de vao menu." -ForegroundColor Red; exit 1 }
}
