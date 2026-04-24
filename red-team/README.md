# Red Team

Attack scripts for the Mini SOC demo. Each one is safe, self-contained, and produces predictable telemetry in the ELK server.

## Prerequisites

- **Kali Linux** (or any Linux with `nmap`, `hydra`, `curl` installed) for scripts 01–03
- **The Windows endpoint itself** for script 04
- Network reachability from Kali to the Ubuntu endpoint (ports 22, 80)

## The scripts

| # | Script | Where to run | What it demonstrates |
| - | ------ | ------------ | -------------------- |
| 1 | [01-nmap-scan.sh](01-nmap-scan.sh) | Kali | Port-scan reconnaissance → Packetbeat flows |
| 2 | [02-hydra-bruteforce.sh](02-hydra-bruteforce.sh) | Kali | SSH password spray → `soc.auth.failed` events |
| 3 | [03-sqli-dvwa.sh](03-sqli-dvwa.sh) | Kali | SQLi + XSS payloads → `soc.attack.web` tag |
| 4 | [04-windows-suspicious.ps1](04-windows-suspicious.ps1) | Windows endpoint | Post-exploitation TTPs → Sysmon EIDs 1/11/13 |

Run them in order to match the narrative in [RUNBOOK.md](RUNBOOK.md).

## Usage

```bash
# Make bash scripts executable (once)
chmod +x *.sh

# From Kali, against the Ubuntu endpoint at 10.10.10.20:
bash 01-nmap-scan.sh       10.10.10.20
bash 02-hydra-bruteforce.sh 10.10.10.20
bash 03-sqli-dvwa.sh       10.10.10.20
```

```powershell
# On the Windows endpoint, PowerShell as Administrator:
.\04-windows-suspicious.ps1
```

## Safety

- **No real malware.** Attack 4 drops the EICAR test string, which every antivirus recognizes as a harmless test.
- **No real break-in.** Hydra tries `root` — disabled by default on Ubuntu — so every attempt fails cleanly.
- **No persistence.** The scheduled task in attack 4 is deleted within 2 seconds of creation.
- **No lateral movement, no C2 traffic, no data exfiltration.** Everything stays on the three lab machines.

Do not run any of these against hosts you don't own.

## Demo flow

See [RUNBOOK.md](RUNBOOK.md) for the full walkthrough including narration, timing, and what to click in Kibana for each attack.
