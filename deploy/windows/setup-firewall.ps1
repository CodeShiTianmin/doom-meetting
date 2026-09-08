#Requires -RunAsAdministrator
<#
.SYNOPSIS
  放行 Windows 防火墙入站端口(幂等, 重复执行会先删除同名规则)。
  端口: Nginx HTTP/HTTPS(读 deploy/.env)、8080/tcp(后端)、
        7880/tcp(LiveKit 信令)、7881/tcp(ICE-TCP)、3478/udp(TURN)、50000-50200/udp(媒体)
#>
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "common.ps1")

$envFile = Join-Path $here "..\.env"
$cfg = if (Test-Path $envFile) { Read-DotEnv $envFile } else { @{} }
$httpPort = if ($cfg["NGINX_HTTP_PORT"]) { $cfg["NGINX_HTTP_PORT"] } else { "80" }
$httpsPort = if ($cfg["NGINX_HTTPS_PORT"]) { $cfg["NGINX_HTTPS_PORT"] } else { "443" }

$rules = @(
    @{ Name = "DoomMeeting Nginx HTTP";     Protocol = "TCP"; Port = $httpPort },
    @{ Name = "DoomMeeting Nginx HTTPS";    Protocol = "TCP"; Port = $httpsPort },
    @{ Name = "DoomMeeting Server 8080";    Protocol = "TCP"; Port = "8080" },
    @{ Name = "DoomMeeting LiveKit 7880";   Protocol = "TCP"; Port = "7880" },
    @{ Name = "DoomMeeting LiveKit 7881";   Protocol = "TCP"; Port = "7881" },
    @{ Name = "DoomMeeting LiveKit TURN";   Protocol = "UDP"; Port = "3478" },
    @{ Name = "DoomMeeting LiveKit Media";  Protocol = "UDP"; Port = "50000-50200" }
)

foreach ($r in $rules) {
    Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -Action Allow `
        -Protocol $r.Protocol -LocalPort $r.Port -Profile Any | Out-Null
    Write-Host ("  放行 {0,-4} {1,-12} ({2})" -f $r.Protocol, $r.Port, $r.Name)
}
Write-Host "==> 防火墙规则已更新"
