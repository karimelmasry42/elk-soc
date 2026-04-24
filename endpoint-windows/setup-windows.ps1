#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Mini SOC — Windows 11 endpoint setup.

.DESCRIPTION
    Installs Sysmon (with the repo's sysmonconfig.xml) and Winlogbeat 8.15,
    configures Winlogbeat to ship to the ELK server, and starts both services.
    Idempotent: safe to run multiple times.

.PARAMETER ElkIP
    The IP address (or DNS name) of the ELK server. Defaults to 10.10.10.10.

.EXAMPLE
    .\setup-windows.ps1 -ElkIP "10.10.10.10"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ElkIP = "10.10.10.10"
)

$ErrorActionPreference = "Stop"

$ElasticVersion  = "8.15.0"
$ScriptDir       = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallRoot     = "C:\Program Files\mini-soc"
$SysmonDir       = Join-Path $InstallRoot "Sysmon"
$WinlogbeatDir   = Join-Path $InstallRoot "Winlogbeat"

$SysmonZipUrl      = "https://download.sysinternals.com/files/Sysmon.zip"
$WinlogbeatZipUrl  = "https://artifacts.elastic.co/downloads/beats/winlogbeat/winlogbeat-$ElasticVersion-windows-x86_64.zip"

function Say  ($msg) { Write-Host "`n▶ $msg" -ForegroundColor Cyan }
function Ok   ($msg) { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Warn ($msg) { Write-Host "⚠ $msg"   -ForegroundColor Yellow }

# -----------------------------------------------------------------------------
# 0) Prep install dir + TLS
# -----------------------------------------------------------------------------
Say "Preparing install directory $InstallRoot"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -ItemType Directory -Force -Path $SysmonDir     | Out-Null
New-Item -ItemType Directory -Force -Path $WinlogbeatDir | Out-Null
Ok "Install dirs ready"

# -----------------------------------------------------------------------------
# 1) Sysmon
# -----------------------------------------------------------------------------
Say "Downloading and installing Sysmon (Sysinternals)"
$SysmonZip = Join-Path $env:TEMP "Sysmon.zip"
Invoke-WebRequest -Uri $SysmonZipUrl -OutFile $SysmonZip -UseBasicParsing
Expand-Archive -Path $SysmonZip -DestinationPath $SysmonDir -Force
Remove-Item $SysmonZip -Force

$SysmonExe    = Join-Path $SysmonDir "Sysmon64.exe"
$SysmonConfig = Join-Path $SysmonDir "sysmonconfig.xml"
Copy-Item (Join-Path $ScriptDir "configs\sysmonconfig.xml") $SysmonConfig -Force

# Install or reload config
$existing = Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue
if ($existing) {
    Ok "Sysmon already installed — reloading config"
    & $SysmonExe -c $SysmonConfig | Out-Null
} else {
    & $SysmonExe -accepteula -i $SysmonConfig | Out-Null
    Ok "Sysmon installed"
}

# -----------------------------------------------------------------------------
# 2) Winlogbeat
# -----------------------------------------------------------------------------
Say "Downloading Winlogbeat $ElasticVersion"
$WinlogbeatZip = Join-Path $env:TEMP "winlogbeat.zip"
Invoke-WebRequest -Uri $WinlogbeatZipUrl -OutFile $WinlogbeatZip -UseBasicParsing
Expand-Archive -Path $WinlogbeatZip -DestinationPath $WinlogbeatDir -Force
Remove-Item $WinlogbeatZip -Force

# Archive extracts to winlogbeat-<version>-windows-x86_64\ — move contents up for a stable path.
$extracted = Get-ChildItem -Path $WinlogbeatDir -Directory | Where-Object { $_.Name -like "winlogbeat-*" } | Select-Object -First 1
if ($extracted) {
    Get-ChildItem -Path $extracted.FullName | Move-Item -Destination $WinlogbeatDir -Force
    Remove-Item $extracted.FullName -Recurse -Force
}
Ok "Winlogbeat extracted to $WinlogbeatDir"

Say "Writing winlogbeat.yml (ELK_IP=$ElkIP)"
$cfgSrc  = Join-Path $ScriptDir    "configs\winlogbeat.yml"
$cfgDst  = Join-Path $WinlogbeatDir "winlogbeat.yml"
(Get-Content -Raw $cfgSrc) -replace "ELK_IP", $ElkIP | Set-Content -Path $cfgDst -Encoding UTF8
Ok "winlogbeat.yml in place"

# -----------------------------------------------------------------------------
# 3) Firewall — allow outbound 5044
# -----------------------------------------------------------------------------
Say "Opening outbound TCP 5044 in Windows Firewall"
$ruleName = "Mini SOC — Winlogbeat 5044 out"
if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $ruleName -Direction Outbound `
        -Protocol TCP -RemotePort 5044 -Action Allow | Out-Null
    Ok "Firewall rule created"
} else {
    Ok "Firewall rule already present"
}

# -----------------------------------------------------------------------------
# 4) Install / reinstall Winlogbeat as a Windows service
# -----------------------------------------------------------------------------
Say "Installing Winlogbeat service"
Push-Location $WinlogbeatDir
try {
    if (Get-Service -Name "winlogbeat" -ErrorAction SilentlyContinue) {
        Stop-Service winlogbeat -ErrorAction SilentlyContinue
        & .\uninstall-service-winlogbeat.ps1 | Out-Null
    }
    & .\install-service-winlogbeat.ps1 | Out-Null
} finally {
    Pop-Location
}
Ok "Service installed"

# -----------------------------------------------------------------------------
# 5) Test output
# -----------------------------------------------------------------------------
Say "Testing Winlogbeat → Logstash connectivity"
$winlogbeatExe = Join-Path $WinlogbeatDir "winlogbeat.exe"
Push-Location $WinlogbeatDir
try {
    & $winlogbeatExe test config  -c winlogbeat.yml
    & $winlogbeatExe test output  -c winlogbeat.yml
    Ok "Connectivity OK"
} catch {
    Warn "test output failed — check that $ElkIP`:5044 is reachable"
} finally {
    Pop-Location
}

# -----------------------------------------------------------------------------
# 6) Start the service
# -----------------------------------------------------------------------------
Say "Starting winlogbeat service"
Start-Service winlogbeat
Set-Service  winlogbeat -StartupType Automatic
Ok "winlogbeat running"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "────────────────────────────────────────────────────────────────────"
Write-Host "Windows endpoint configured."
Write-Host "  ELK server   : $ElkIP`:5044"
Write-Host "  Sysmon       : $SysmonDir (config: sysmonconfig.xml)"
Write-Host "  Winlogbeat   : $WinlogbeatDir"
Write-Host ""
Write-Host "Next:"
Write-Host "  1. Confirm Kibana shows events: filter fields.soc_endpoint = 'windows-endpoint'"
Write-Host "  2. From the red-team machine, run ..\red-team\04-windows-suspicious.ps1 here"
Write-Host "────────────────────────────────────────────────────────────────────"
