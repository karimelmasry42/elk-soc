# Network Setup

Three deployment options, in order of simplicity. Pick the one that matches your demo machine.

## Option A — All VMs on one host (recommended for the demo)

Run every VM on a single laptop using your hypervisor's **Internal Network** or **Host-only** mode so traffic stays between the VMs and never touches the corporate Wi-Fi.

### VirtualBox example

1. **File → Host Network Manager → Create** a host-only network, e.g. `192.168.56.0/24`.
2. For each VM (ELK, Ubuntu endpoint, Windows endpoint, Kali), **Settings → Network → Adapter 1 → Host-only Adapter**.
3. Set static IPs inside each VM:

   | VM | IP |
   | --- | --- |
   | ELK server | `192.168.56.10` |
   | Ubuntu endpoint | `192.168.56.20` |
   | Windows endpoint | `192.168.56.30` |
   | Kali attacker | `192.168.56.40` |

4. Pass `192.168.56.10` as `<ELK_IP>` everywhere.

### VMware Workstation / Fusion

Use **VMnet1 (Host-only)** and follow the same scheme.

### UTM (Apple Silicon)

Create a shared network (`Emulated VLAN` mode), then give each VM a static IP on that network via its OS settings.

## Option B — Multiple physical/virtual machines on the same LAN

If each teammate runs their VM on their own laptop and you all join the same Wi-Fi:

1. Give each VM a **static IP** via its OS (or DHCP reservation on the router).
2. Ensure the LAN doesn't have **client isolation** enabled — many campus/coffee-shop networks block peer traffic. Test with `ping` between any two machines before starting Beats.
3. Open Beat traffic on the host firewall of each laptop:
   - **macOS host:** System Settings → Network → Firewall → allow incoming for your VM manager.
   - **Windows host:** Windows Security → Firewall & network protection → Allow an app.
   - **Linux host:** `sudo ufw allow from <lan-subnet>`.

## Option C — Tailscale (any machines, anywhere)

[Tailscale](https://tailscale.com) gives every VM a private mesh VPN IP (`100.x.y.z`) that works across NATs and campus networks. Free for up to 100 devices.

### Setup

1. Create a free Tailscale account.
2. On **each** VM:
   ```bash
   # Linux
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   ```
   ```powershell
   # Windows — download installer from https://tailscale.com/download/windows
   # Log in via browser popup.
   ```
3. `tailscale ip -4` on each VM prints its Tailscale IP. Use the ELK server's Tailscale IP as `<ELK_IP>` everywhere.
4. Verify: from each endpoint, `ping <elk-tailscale-ip>`.

### Caveats

- Tailscale adds ~1 ms of latency — fine for this lab.
- MagicDNS optional: enable it in the admin console and you can use `elk-server` instead of the IP.
- If you enable the ACL **Shields Up** mode, open 5044 and 5601 inbound on the ELK node.

## Firewall rules

The only traffic this lab needs:

| From | To | Port | Proto | Purpose |
| --- | --- | --- | --- | --- |
| Any endpoint | ELK server | 5044 | TCP | Beats → Logstash |
| Analyst laptop | ELK server | 5601 | TCP | Kibana UI |
| Kali | Ubuntu endpoint | 22 | TCP | SSH (Hydra) |
| Kali | Ubuntu endpoint | 80 | TCP | DVWA |
| Kali | Ubuntu endpoint | 1-1000 | TCP | Nmap scan |
| Kali | Windows endpoint | 445 / 3389 | TCP | (optional) SMB / RDP |

### OS specifics

- **Ubuntu** (ELK host): `sudo ufw allow 5044/tcp && sudo ufw allow 5601/tcp`
- **Ubuntu** (endpoint): `sudo ufw allow 22/tcp && sudo ufw allow 80/tcp`
- **Windows** (endpoint): the setup script opens outbound 5044 automatically.

## Verifying connectivity before running setup

From each endpoint, **before** running its setup script:

```bash
# Linux
nc -vz <ELK_IP> 5044 || echo "❌ 5044 unreachable"
ping -c 3 <ELK_IP>
```

```powershell
# Windows
Test-NetConnection -ComputerName <ELK_IP> -Port 5044
```

If these fail, fix the network **before** proceeding — the Beat setup cannot succeed without reachability.
