<#
.SYNOPSIS
    Mini SOC — Red team attack #4: Windows post-exploitation simulation.

.DESCRIPTION
    Runs ON the Windows endpoint to generate the kind of telemetry a real
    attacker would produce *after* gaining a foothold. All actions are safe —
    no real malware is written, and the scheduled task is deleted at the end.

    Expected to light up in Kibana (soc-winlogbeat-*):
      • Sysmon Event 1  (ProcessCreate)    — for whoami, net.exe, powershell.exe -enc
      • Sysmon Event 11 (FileCreate)       — dropping the EICAR test file
      • Sysmon Event 13 (RegistryEvent)    — scheduled task registers under Services\Schedule
      • Security Event 4688 (process audit) — every child process
      • Security Event 4698 (task created) and 4699 (task deleted)

.EXAMPLE
    PS C:\> .\04-windows-suspicious.ps1
#>

$ErrorActionPreference = "Continue"

function Step ($msg) { Write-Host "`n▶ $msg" -ForegroundColor Cyan }
function Note ($msg) { Write-Host "   ↳ $msg" -ForegroundColor DarkGray }

$TempDir = Join-Path $env:TEMP "mini-soc-redteam"
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

# ---------------------------------------------------------------------
# 1) Drop the EICAR test string (safe antivirus-test file)
#    → Sysmon EID 11 FileCreate
# ---------------------------------------------------------------------
Step "Dropping EICAR test file"
$Eicar = 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*'
$EicarPath = Join-Path $TempDir "eicar.txt"
Set-Content -Path $EicarPath -Value $Eicar -Encoding ASCII
Note "→ $EicarPath"
Note "Expect Sysmon EID 11 (FileCreate). Your AV may quarantine — that's fine."

# ---------------------------------------------------------------------
# 2) Reconnaissance commands
#    → Sysmon EID 1 ProcessCreate + Security EID 4688
# ---------------------------------------------------------------------
Step "Running reconnaissance commands"
Note "whoami /all"
whoami /all | Out-Null

Note "net user"
net user | Out-Null

Note "net localgroup administrators"
net localgroup administrators | Out-Null

Note "Get-Process (PowerShell cmdlet, shows via PowerShell/Operational channel)"
Get-Process | Out-Null

# ---------------------------------------------------------------------
# 3) Scheduled task — create, then delete (simulated persistence)
#    → Security EID 4698 (created), 4699 (deleted)
#    → Sysmon EID 13 (registry value set under Schedule\TaskCache)
# ---------------------------------------------------------------------
Step "Creating a fake persistence task, then deleting it"
$TaskName = "MiniSocDemoPersistence"
$Action   = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c echo demo"
$Trigger  = New-ScheduledTaskTrigger -AtStartup
try {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger `
        -RunLevel Highest -Force | Out-Null
    Note "registered $TaskName"
    Start-Sleep -Seconds 2
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Note "deleted $TaskName"
} catch {
    Write-Host "   (scheduled task step failed: $_)" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------
# 4) Base64-encoded PowerShell command (classic attacker TTP)
#    → Sysmon EID 1 with CommandLine containing -enc / -EncodedCommand
# ---------------------------------------------------------------------
Step "Running a base64-encoded PowerShell command"
$Benign = 'Write-Host ("Mini-SOC demo — encoded exec at " + (Get-Date))'
$Bytes  = [System.Text.Encoding]::Unicode.GetBytes($Benign)
$B64    = [Convert]::ToBase64String($Bytes)
Note "powershell.exe -NoProfile -EncodedCommand <base64>"
powershell.exe -NoProfile -EncodedCommand $B64 | Out-Null

# ---------------------------------------------------------------------
# 5) Cleanup
# ---------------------------------------------------------------------
Step "Cleanup"
Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
Note "removed $TempDir"

Write-Host ""
Write-Host "────────────────────────────────────────────────────────────────────"
Write-Host "Attack 4 complete. In Kibana (soc-winlogbeat-*):"
Write-Host "  • Filter: winlog.channel = 'Microsoft-Windows-Sysmon/Operational'"
Write-Host "    Expect: EID 1 (whoami.exe, net.exe, powershell.exe with -EncodedCommand)"
Write-Host "            EID 11 (eicar.txt)"
Write-Host "            EID 13 (Schedule\TaskCache registry change)"
Write-Host "  • Filter: winlog.channel = 'Security' AND winlog.event_id = '4688'"
Write-Host "    Expect: process_creation entries for each recon command"
Write-Host "────────────────────────────────────────────────────────────────────"
