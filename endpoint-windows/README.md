# Windows 11 Endpoint

Monitored Windows host: **Sysmon** for deep telemetry and **Winlogbeat** to ship events to the ELK server.

## Prerequisites

- Windows **10** or **11** (PowerShell 5.1+, which ships with both)
- **Administrator** access
- Network reachability to the ELK server on TCP **5044**
- Internet access for the one-time download of Sysmon and Winlogbeat

Before running, verify connectivity:

```powershell
Test-NetConnection -ComputerName <ELK_IP> -Port 5044
# TcpTestSucceeded : True  ← required
```

## Usage

Open **PowerShell as Administrator** (right-click the Start menu → *Terminal (Admin)* on Win11, or *Windows PowerShell (Admin)* on Win10), then:

```powershell
cd endpoint-windows
.\setup-windows.ps1 -ElkIP "10.10.10.10"
```

If PowerShell blocks the script, allow it for this session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup-windows.ps1 -ElkIP "10.10.10.10"
```

The script is idempotent — re-run to re-apply configs or to update.

## What it does

1. Creates `C:\Program Files\mini-soc\{Sysmon,Winlogbeat}`.
2. Downloads **Sysmon** (Sysinternals) and installs it with [configs/sysmonconfig.xml](configs/sysmonconfig.xml).
3. Downloads **Winlogbeat 8.15**, writes `winlogbeat.yml` with `ELK_IP` substituted.
4. Opens an **outbound** firewall rule for TCP 5044.
5. Installs Winlogbeat as a Windows service (set to Automatic start).
6. Runs `winlogbeat.exe test config` + `test output` to confirm reachability.
7. Starts the service.

## Verify

```powershell
# Services
Get-Service winlogbeat, sysmon64

# Sysmon is logging
Get-WinEvent -LogName "Microsoft-Windows-Sysmon/Operational" -MaxEvents 5

# Winlogbeat's own log
Get-Content C:\ProgramData\winlogbeat\logs\winlogbeat -Tail 30 -Wait
```

Then in Kibana (`http://<elk-ip>:5601` → Discover → `soc-winlogbeat-*`):

```
fields.soc_endpoint: "windows-endpoint"
```

You should see Sysmon events (winlog.channel = `Microsoft-Windows-Sysmon/Operational`) and Security events (4624 logons, 4688 process creates).

## Uninstall

```powershell
# Stop & remove Winlogbeat
Stop-Service winlogbeat
cd "C:\Program Files\mini-soc\Winlogbeat"
.\uninstall-service-winlogbeat.ps1

# Remove Sysmon
& "C:\Program Files\mini-soc\Sysmon\Sysmon64.exe" -u force

# Delete firewall rule and install dir
Remove-NetFirewallRule -DisplayName "Mini SOC — Winlogbeat 5044 out"
Remove-Item "C:\Program Files\mini-soc" -Recurse -Force
```

## Files

| File | Purpose |
| --- | --- |
| [setup-windows.ps1](setup-windows.ps1) | Main setup script |
| [configs/winlogbeat.yml](configs/winlogbeat.yml) | Winlogbeat config (ships to Logstash) |
| [configs/sysmonconfig.xml](configs/sysmonconfig.xml) | Trimmed SwiftOnSecurity-style Sysmon config |
