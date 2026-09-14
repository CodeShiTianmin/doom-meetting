#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Windows 10/11 原生部署(不依赖 Docker): JDK + Maven + Node + MySQL 8 + Nginx + LiveKit, 全部注册为开机自启的 Windows 服务。

.DESCRIPTION
  适用于带公网 IP、无域名、运营商封 80/443 的 Windows PC 直接当服务器。
  依赖下载全部走国内可达的镜像(清华 TUNA / cdn.mysql.com / gh-proxy.com), 脚本可重复执行(幂等)。
  配置读取 deploy/.env(见 deploy/.env.example)。

  步骤(-Steps 可指定子集): download, extract, mysql, build-server, build-admin, nginx, livekit, server, firewall, power

.PARAMETER PublicIp
  本机公网 IP。不传则从 deploy/.env 的 LIVEKIT_WS_URL 解析。

.PARAMETER InstallDir
  安装目录, 默认 C:\doom-meeting

.EXAMPLE
  cd <repo>\deploy\windows
  .\install-native.ps1 -PublicIp 61.145.190.188
  .\install-native.ps1 -Steps build-server,server      # 只重新构建并重启后端
#>
param(
    [string]$PublicIp,
    [string]$InstallDir = "C:\doom-meeting",
    [string[]]$Steps = @("download", "extract", "mysql", "build-server", "build-admin", "nginx", "livekit", "server", "firewall", "power")
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$deployDir = (Resolve-Path (Join-Path $here "..")).Path
$repoRoot = (Resolve-Path (Join-Path $deployDir "..")).Path
. (Join-Path $here "common.ps1")

# ---------- 配置 ----------
$envFile = Join-Path $deployDir ".env"
if (-not (Test-Path $envFile)) {
    Copy-Item (Join-Path $deployDir ".env.example") $envFile
    Write-Warning "已从 .env.example 生成 deploy\.env, 请修改其中的公网 IP / 端口 / 密钥后重新执行。"
    exit 1
}
$cfg = Read-DotEnv $envFile
function Cfg($key, $default) { if ($cfg[$key]) { $cfg[$key] } else { $default } }

if (-not $PublicIp) {
    if ((Cfg "LIVEKIT_WS_URL" "") -match '^wss?://([^:/]+)') { $PublicIp = $Matches[1] }
}
if (-not $PublicIp) { throw "无法确定公网 IP, 请用 -PublicIp 指定或在 deploy\.env 设置 LIVEKIT_WS_URL" }

$httpPort = Cfg "NGINX_HTTP_PORT" "80"
$mysqlPassword = Cfg "MYSQL_ROOT_PASSWORD" "root"
$livekitKey = Cfg "LIVEKIT_API_KEY" "devkey"
$livekitSecret = Cfg "LIVEKIT_API_SECRET" "devsecret-devsecret-devsecret-32"
$livekitWsUrl = Cfg "LIVEKIT_WS_URL" "ws://${PublicIp}:7880"

# ---------- 版本与下载源 ----------
$versions = @{
    jdk     = "17.0.20.1_1"
    maven   = "3.9.16"
    node    = "20.18.0"
    mysql   = "8.0.45"
    nginx   = "1.26.3"
    livekit = "1.13.6"
    winsw   = "2.12.0"
}
$downloads = @{
    "jdk.zip"       = "https://mirrors.tuna.tsinghua.edu.cn/Adoptium/17/jdk/x64/windows/OpenJDK17U-jdk_x64_windows_hotspot_$($versions.jdk).zip"
    "maven.zip"     = "https://mirrors.tuna.tsinghua.edu.cn/apache/maven/maven-3/$($versions.maven)/binaries/apache-maven-$($versions.maven)-bin.zip"
    "node.zip"      = "https://mirrors.tuna.tsinghua.edu.cn/nodejs-release/v$($versions.node)/node-v$($versions.node)-win-x64.zip"
    "mysql.zip"     = "https://cdn.mysql.com/Downloads/MySQL-8.0/mysql-$($versions.mysql)-winx64.zip"
    "nginx.zip"     = "https://nginx.org/download/nginx-$($versions.nginx).zip"
    "livekit.zip"   = "https://gh-proxy.com/https://github.com/livekit/livekit/releases/download/v$($versions.livekit)/livekit_$($versions.livekit)_windows_amd64.zip"
    "WinSW-x64.exe" = "https://gh-proxy.com/https://github.com/winsw/winsw/releases/download/v$($versions.winsw)/WinSW-x64.exe"
    "vc_redist.x64.exe" = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
}

$dl = Join-Path $InstallDir "downloads"
$jdkDir = Join-Path $InstallDir "jdk"
$mavenDir = Join-Path $InstallDir "maven"
$nodeDir = Join-Path $InstallDir "node"
$mysqlDir = Join-Path $InstallDir "mysql"
$mysqlData = Join-Path $InstallDir "mysql-data"
$nginxDir = Join-Path $InstallDir "nginx"
$livekitDir = Join-Path $InstallDir "livekit"
$serverDir = Join-Path $InstallDir "server"
$winsw = Join-Path $dl "WinSW-x64.exe"

foreach ($d in @($InstallDir, $dl, $serverDir, $livekitDir)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

function Step($name) { $script:Steps -contains $name }
# 原生命令写 stderr 时不要被 ErrorActionPreference=Stop 当作终止错误
function Native([scriptblock]$sb) {
    $old = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { & $sb } finally { $ErrorActionPreference = $old }
}
function Banner($msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }

# 解压 zip 并把其中唯一的顶层目录"扁平化"到 $dest
function Expand-Flat($zip, $dest) {
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    $tmp = Join-Path $InstallDir ("_tmp_" + [IO.Path]::GetFileNameWithoutExtension($zip))
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $items = Get-ChildItem $tmp
    if ($items.Count -eq 1 -and $items[0].PSIsContainer) { Move-Item $items[0].FullName $dest } else { Move-Item $tmp $dest }
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
}

function Write-Utf8($path, $content) { [IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($false)) }

function Install-WinSwService($dir, $id, $xml) {
    $exe = Join-Path $dir "$id.exe"
    $svc = Get-Service $id -ErrorAction SilentlyContinue
    if ($svc) {
        Native {
            if ($svc.Status -ne "Stopped") { Stop-Service $id -Force -ErrorAction SilentlyContinue; (Get-Service $id).WaitForStatus("Stopped", [TimeSpan]::FromSeconds(60)) }
            if (Test-Path $exe) { & $exe uninstall 2>&1 | Out-Null } else { sc.exe delete $id 2>&1 | Out-Null }
        }
        # 等待 SCM 释放服务与 WinSW 进程释放 exe 文件
        for ($i = 0; $i -lt 30; $i++) { if (-not (Get-Service $id -ErrorAction SilentlyContinue)) { break }; Start-Sleep -Seconds 1 }
        Start-Sleep -Seconds 2
    }
    Copy-Item $winsw $exe -Force
    Write-Utf8 (Join-Path $dir "$id.xml") $xml
    Native {
        & $exe install 2>&1 | Out-Null
        & $exe start 2>&1 | Out-Null
    }
    Start-Sleep -Seconds 3
    Write-Host ("  服务 {0}: {1}" -f $id, (Get-Service $id).Status)
}

# ---------- 1. 下载 ----------
if (Step "download") {
    Banner "下载依赖 -> $dl"
    foreach ($name in $downloads.Keys) {
        $out = Join-Path $dl $name
        if ((Test-Path $out) -and (Get-Item $out).Length -gt 1MB) { Write-Host "  已存在 $name"; continue }
        Write-Host "  下载 $name"
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            Native { & curl.exe -sSL --retry 5 --retry-delay 3 -o "$out.part" $downloads[$name] 2>&1 }
            if ($LASTEXITCODE -ne 0) { throw "下载失败: $($downloads[$name])" }
            Move-Item -Force "$out.part" $out
        } else {
            Invoke-WebRequest -UseBasicParsing -Uri $downloads[$name] -OutFile $out -TimeoutSec 600
        }
    }
}

# ---------- 2. 解压 ----------
if (Step "extract") {
    Banner "解压运行时"
    if (-not (Test-Path (Join-Path $jdkDir "bin\java.exe")))   { Write-Host "  jdk";   Expand-Flat (Join-Path $dl "jdk.zip") $jdkDir }
    if (-not (Test-Path (Join-Path $mavenDir "bin\mvn.cmd")))  { Write-Host "  maven"; Expand-Flat (Join-Path $dl "maven.zip") $mavenDir }
    if (-not (Test-Path (Join-Path $nodeDir "node.exe")))      { Write-Host "  node";  Expand-Flat (Join-Path $dl "node.zip") $nodeDir }
    if (-not (Test-Path (Join-Path $mysqlDir "bin\mysqld.exe"))) { Write-Host "  mysql"; Expand-Flat (Join-Path $dl "mysql.zip") $mysqlDir }
    if (-not (Test-Path (Join-Path $nginxDir "nginx.exe")))    { Write-Host "  nginx"; Expand-Flat (Join-Path $dl "nginx.zip") $nginxDir }
    if (-not (Test-Path (Join-Path $livekitDir "livekit-server.exe"))) {
        Write-Host "  livekit"; Expand-Archive -Path (Join-Path $dl "livekit.zip") -DestinationPath $livekitDir -Force
    }
    # MySQL 8 zip 版依赖 VC++ 2019 运行库
    $vcInstalled = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue
    if (-not $vcInstalled) {
        Write-Host "  安装 VC++ 运行库"
        Start-Process -Wait -FilePath (Join-Path $dl "vc_redist.x64.exe") -ArgumentList "/install", "/quiet", "/norestart"
    }
}

$env:JAVA_HOME = $jdkDir
$env:PATH = "$jdkDir\bin;$mavenDir\bin;$nodeDir;$mysqlDir\bin;$env:PATH"

# ---------- 3. MySQL ----------
if (Step "mysql") {
    Banner "MySQL 8 (服务 DoomMeetingMySQL, 仅监听 127.0.0.1:3306)"
    $myIni = Join-Path $InstallDir "my.ini"
    Write-Utf8 $myIni @"
[mysqld]
basedir=$($mysqlDir -replace '\\','/')
datadir=$($mysqlData -replace '\\','/')
port=3306
bind-address=127.0.0.1
character-set-server=utf8mb4
collation-server=utf8mb4_general_ci
default-time-zone=+08:00
max_connections=200
innodb_buffer_pool_size=512M
log-error=$($InstallDir -replace '\\','/')/mysql-error.log
[client]
port=3306
default-character-set=utf8mb4
"@
    $freshInit = $false
    if (-not (Test-Path (Join-Path $mysqlData "mysql"))) {
        Write-Host "  初始化数据目录"
        $out = Native { & "$mysqlDir\bin\mysqld.exe" --defaults-file="$myIni" --initialize-insecure --console 2>&1 }
        if ($LASTEXITCODE -ne 0) { $out | Select -Last 20; throw "mysqld --initialize 失败" }
        $freshInit = $true
    }
    if (-not (Get-Service DoomMeetingMySQL -ErrorAction SilentlyContinue)) {
        & "$mysqlDir\bin\mysqld.exe" --install DoomMeetingMySQL --defaults-file="$myIni" | Out-Null
    }
    Start-Service DoomMeetingMySQL
    # 等待就绪
    $ok = $false
    for ($i = 0; $i -lt 30; $i++) {
        Native { & "$mysqlDir\bin\mysqladmin.exe" -uroot --skip-password ping 2>&1 | Out-Null }
        if ($LASTEXITCODE -eq 0) { $ok = $true; break }
        Native { & "$mysqlDir\bin\mysqladmin.exe" -uroot "-p$mysqlPassword" ping 2>&1 | Out-Null }
        if ($LASTEXITCODE -eq 0) { $ok = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ok) { throw "MySQL 未能启动, 查看 $InstallDir\mysql-error.log" }
    if ($freshInit) {
        Write-Host "  设置 root 密码并导入 deploy/mysql/init.sql"
        $initSql = (Join-Path $deployDir "mysql\init.sql") -replace '\\', '/'
        Native {
            & "$mysqlDir\bin\mysql.exe" -uroot --skip-password -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysqlPassword';" 2>&1
            & "$mysqlDir\bin\mysql.exe" -uroot "-p$mysqlPassword" --default-character-set=utf8mb4 -e "source $initSql" 2>&1 | ? { $_ -notmatch 'Using a password' }
        }
        if ($LASTEXITCODE -ne 0) { throw "导入 init.sql 失败" }
    }
    Write-Host ("  服务 DoomMeetingMySQL: {0}" -f (Get-Service DoomMeetingMySQL).Status)
}

# ---------- 4. 构建后端 ----------
if (Step "build-server") {
    Banner "构建 meeting-server (Maven, 阿里云镜像)"
    $settings = Join-Path $InstallDir "maven-settings.xml"
    Write-Utf8 $settings @"
<settings>
  <mirrors>
    <mirror><id>aliyun</id><mirrorOf>central</mirrorOf><url>https://maven.aliyun.com/repository/public</url></mirror>
  </mirrors>
</settings>
"@
    Push-Location (Join-Path $repoRoot "meeting-server")
    try {
        cmd /c "`"$mavenDir\bin\mvn.cmd`" -s `"$settings`" -q -DskipTests package 2>&1"
        if ($LASTEXITCODE -ne 0) { throw "Maven 构建失败" }
        $jar = Get-ChildItem target\meeting-server-*.jar | ? { $_.Name -notmatch 'original' } | Select -First 1
        if (Get-Service DoomMeetingServer -ErrorAction SilentlyContinue) { Stop-Service DoomMeetingServer -Force -ErrorAction SilentlyContinue }
        Copy-Item $jar.FullName (Join-Path $serverDir "app.jar") -Force
        Write-Host "  产物 -> $serverDir\app.jar"
    } finally { Pop-Location }
}

# ---------- 5. 构建管理后台 ----------
if (Step "build-admin") {
    Banner "构建 meeting-admin (npm, npmmirror 镜像)"
    Push-Location (Join-Path $repoRoot "meeting-admin")
    try {
        cmd /c "`"$nodeDir\npm.cmd`" ci --registry https://registry.npmmirror.com --no-audit --no-fund 2>&1"
        if ($LASTEXITCODE -ne 0) { throw "npm ci 失败" }
        cmd /c "`"$nodeDir\npm.cmd`" run build 2>&1"
        if ($LASTEXITCODE -ne 0) { throw "npm run build 失败" }
        $html = Join-Path $nginxDir "html"
        if (Test-Path $html) { Remove-Item -Recurse -Force $html }
        Copy-Item -Recurse dist $html
        Write-Host "  产物 -> $html"
    } finally { Pop-Location }
}

# ---------- 6. Nginx ----------
if (Step "nginx") {
    Banner "Nginx (服务 DoomMeetingNginx, 端口 $httpPort)"
    # 复用容器版 server 块: 端口 / 上游 / 静态目录 三处替换
    $serverBlock = (Get-Content (Join-Path $deployDir "nginx\nginx.conf") -Raw -Encoding UTF8) `
        -replace 'listen 80;', "listen $httpPort;" `
        -replace 'http://meeting-server:8080', 'http://127.0.0.1:8080' `
        -replace 'root /usr/share/nginx/html;', 'root html;'
    Write-Utf8 (Join-Path $nginxDir "conf\nginx.conf") @"
worker_processes  1;
error_log  logs/error.log;
pid        logs/nginx.pid;
events { worker_connections 1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    access_log    logs/access.log;
    sendfile      on;
    keepalive_timeout 65;
$serverBlock
}
"@
    Install-WinSwService $nginxDir "DoomMeetingNginx" @"
<service>
  <id>DoomMeetingNginx</id>
  <name>DoomMeeting Nginx</name>
  <description>管理后台静态资源 + API/WS 反向代理</description>
  <executable>$nginxDir\nginx.exe</executable>
  <arguments>-p "$nginxDir"</arguments>
  <stopexecutable>$nginxDir\nginx.exe</stopexecutable>
  <stoparguments>-p "$nginxDir" -s stop</stoparguments>
  <workingdirectory>$nginxDir</workingdirectory>
  <startmode>Automatic</startmode>
  <onfailure action="restart" delay="5 sec"/>
  <log mode="roll-by-size"><sizeThreshold>10240</sizeThreshold><keepFiles>3</keepFiles></log>
</service>
"@
}

# ---------- 7. LiveKit ----------
if (Step "livekit") {
    Banner "LiveKit (服务 DoomMeetingLiveKit, node_ip=$PublicIp)"
    Write-Utf8 (Join-Path $livekitDir "livekit.yaml") @"
# 由 install-native.ps1 生成(参见 deploy/livekit/livekit.yaml); 修改后重启服务 DoomMeetingLiveKit
port: 7880
rtc:
  tcp_port: 7881
  port_range_start: 50000
  port_range_end: 50200
  use_external_ip: false
  node_ip: $PublicIp
  # 下行带宽估算保底 6Mbps: 避免同房某台手机因估算偏低被长时间切到低档层(说明见 deploy/livekit/livekit.yaml)
  congestion_control:
    enabled: true
    allow_pause: false
    stream_allocator:
      min_channel_capacity: 6000000
turn:
  enabled: true
  udp_port: 3478
keys:
  ${livekitKey}: ${livekitSecret}
logging:
  level: info
"@
    Install-WinSwService $livekitDir "DoomMeetingLiveKit" @"
<service>
  <id>DoomMeetingLiveKit</id>
  <name>DoomMeeting LiveKit</name>
  <description>LiveKit SFU (WebRTC 媒体服务器, 内置 TURN)</description>
  <executable>$livekitDir\livekit-server.exe</executable>
  <arguments>--config "$livekitDir\livekit.yaml"</arguments>
  <workingdirectory>$livekitDir</workingdirectory>
  <startmode>Automatic</startmode>
  <onfailure action="restart" delay="5 sec"/>
  <log mode="roll-by-size"><sizeThreshold>10240</sizeThreshold><keepFiles>5</keepFiles></log>
</service>
"@
}

# ---------- 8. 后端服务 ----------
if (Step "server") {
    Banner "meeting-server (服务 DoomMeetingServer, 端口 8080)"
    $envKeys = @(
        @{ n = "MYSQL_HOST"; v = "127.0.0.1" },
        @{ n = "MYSQL_PORT"; v = "3306" },
        @{ n = "MYSQL_DATABASE"; v = "doom_meeting" },
        @{ n = "MYSQL_USERNAME"; v = "root" },
        @{ n = "MYSQL_PASSWORD"; v = $mysqlPassword },
        @{ n = "LIVEKIT_API_KEY"; v = $livekitKey },
        @{ n = "LIVEKIT_API_SECRET"; v = $livekitSecret },
        @{ n = "LIVEKIT_WS_URL"; v = $livekitWsUrl },
        @{ n = "LIVEKIT_API_URL"; v = "http://127.0.0.1:7880" },
        @{ n = "APP_JWT_SECRET"; v = (Cfg "APP_JWT_SECRET" "") },
        @{ n = "DEFAULT_ADMIN_USERNAME"; v = (Cfg "DEFAULT_ADMIN_USERNAME" "jxys1") },
        @{ n = "DEFAULT_ADMIN_PASSWORD"; v = (Cfg "DEFAULT_ADMIN_PASSWORD" "admin123") },
        @{ n = "APP_REJECT_DEFAULT_SECRETS"; v = (Cfg "APP_REJECT_DEFAULT_SECRETS" "false") },
        @{ n = "APP_CORS_ALLOWED_ORIGINS"; v = (Cfg "APP_CORS_ALLOWED_ORIGINS" "*") }
    )
    $envXml = ($envKeys | ? { $_.v -ne "" } | % { "  <env name=`"$($_.n)`" value=`"$([Security.SecurityElement]::Escape($_.v))`"/>" }) -join "`n"
    Install-WinSwService $serverDir "DoomMeetingServer" @"
<service>
  <id>DoomMeetingServer</id>
  <name>DoomMeeting Server</name>
  <description>多房并发投屏会议 后端(Spring Boot)</description>
  <executable>$jdkDir\bin\java.exe</executable>
  <arguments>-Xms512m -Xmx2g -Dfile.encoding=UTF-8 -jar "$serverDir\app.jar"</arguments>
  <workingdirectory>$serverDir</workingdirectory>
$envXml
  <depend>DoomMeetingMySQL</depend>
  <startmode>Automatic</startmode>
  <onfailure action="restart" delay="10 sec"/>
  <log mode="roll-by-size"><sizeThreshold>20480</sizeThreshold><keepFiles>5</keepFiles></log>
</service>
"@
}

# ---------- 9. 防火墙 ----------
if (Step "firewall") {
    & (Join-Path $here "setup-firewall.ps1")
}

# ---------- 10. 电源: 不睡眠 ----------
if (Step "power") {
    Banner "电源策略: 禁止睡眠/休眠"
    powercfg /change standby-timeout-ac 0 | Out-Null
    powercfg /change hibernate-timeout-ac 0 | Out-Null
    powercfg /hibernate off | Out-Null
}

Write-Host ""
Write-Host "==> 完成" -ForegroundColor Green
Get-Service DoomMeeting* | % { Write-Host ("  {0,-22} {1,-8} {2}" -f $_.Name, $_.Status, $_.StartType) }
Write-Host "  管理后台:  http://${PublicIp}:${httpPort}   (账号 $(Cfg 'DEFAULT_ADMIN_USERNAME' 'jxys1'))"
Write-Host "  后端 API:  http://${PublicIp}:8080"
Write-Host "  LiveKit:   $livekitWsUrl"
Write-Host "  客户端打包参数:"
Write-Host "    --dart-define=API_BASE_URL=http://${PublicIp}:${httpPort} --dart-define=WS_URL=ws://${PublicIp}:${httpPort}/ws"
