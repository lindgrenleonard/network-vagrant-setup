# ACME Corp — Stockholm Site

KTH networks course project. Multi-site corporate network built with LXD containers inside a Multipass VM on macOS.

Stockholm runs 4 containers (VM1, VM2, VM3, VM6). London (VM4, VM5) runs on a teammate's machine, connected via IPsec VPN.

## Network Topology

```
                  Internet
                     │
              ┌──────┴──────┐
              │   VM1-GW    │  192.168.100.10 (WAN)
              │   Gateway   │
              └──┬───┬───┬──┘
                 │   │   │
     ┌───────────┘   │   └───────────┐
     │               │               │
  VLAN 10         VLAN 20         VLAN 30
  10.0.1.0/26     10.0.1.128/26   10.0.1.240/28
  (Server/CA)     (Client/London) (DMZ)
     │                                │
  ┌──┴───┐                        ┌───┴───┐
  │VM2   │  10.0.1.2              │VM6    │  10.0.1.242
  │Server│  Nginx, BIND9,         │DMZ    │  Docker, Nginx,
  │      │  Syncthing             │       │  Certbot
  ├──────┤                        └───────┘
  │VM3   │  10.0.1.3
  │CA    │  FreeRADIUS, EasyRSA
  │      │  (air-gapped)
  └──────┘
```

## Prerequisites

- macOS with [Multipass](https://multipass.run/) installed
- ~16 GB RAM and ~50 GB disk available for the VM

```bash
brew install multipass
```

## Quick Start

```bash
# 1. Create the Multipass VM with all LXD containers, bridges, and networking
bash setup-stockholm.sh

# 2. Enter the VM
multipass shell stockholm

# 3. Apply firewall rules (inside the VM)
bash /path/to/configure-ufw.sh

# 4. Verify firewall policies (inside the VM)
bash /path/to/test-firewall.sh
```

## Scripts

| Script               | Where to run        | Purpose                                                                   |
| -------------------- | ------------------- | ------------------------------------------------------------------------- |
| `setup-stockholm.sh` | macOS host          | Creates Multipass VM, LXD containers, bridges, netplan, installs packages |
| `configure-ufw.sh`   | Inside Multipass VM | Applies UFW firewall rules to all VMs. Safe to re-run.                    |
| `test-firewall.sh`   | Inside Multipass VM | Verifies firewall policies with connectivity tests                        |
| `reset-ufw.sh`       | Inside Multipass VM | Strips all UFW rules and disables firewalls on all VMs                    |

All scripts inside the VM use `sg lxd -c` to ensure LXD group permissions.

## Containers

| Container | Role           | IP                                   | VLAN | Key Services                                  |
| --------- | -------------- | ------------------------------------ | ---- | --------------------------------------------- |
| `vm1-gw`  | Gateway/Router | 10.0.1.1, .129, .241, 192.168.100.10 | All  | iptables NAT, UFW routing, StrongSwan IPsec   |
| `vm2-srv` | Server         | 10.0.1.2                             | 10   | Nginx, BIND9 DNS, Syncthing                   |
| `vm3-ca`  | CA Server      | 10.0.1.3                             | 10   | FreeRADIUS, EasyRSA (air-gapped, no internet) |
| `vm6-dmz` | DMZ            | 10.0.1.242                           | 30   | Docker, Nginx, Certbot                        |

### Accessing containers

```bash
# From inside the Multipass VM
lxc exec vm1-gw  -- bash
lxc exec vm2-srv -- bash
lxc exec vm3-ca  -- bash
lxc exec vm6-dmz -- bash
```

## Firewall Policy Summary

**VM1 (Gateway):**

- Default deny incoming, allow outgoing, deny routed
- NAT masquerade for 10.0.1.0/24 outbound on WAN
- DMZ (VLAN 30) blocked from reaching Server VLAN and Client VLAN
- VLAN 10, 20, 30 allowed outbound to internet
- Internet inbound to DMZ on ports 80/443 only
- VLAN 20 (London clients) can reach VLAN 10 on ports 443, 8384, 53 only (not VM3)
- ICMP echo-request forwarding disabled (pings controlled by route rules)

**VM2 (Server):** deny incoming except SSH, HTTP/S, DNS, Syncthing

**VM3 (CA):** deny incoming except SSH, RADIUS (1812-1813/udp). Air-gapped via netplan (no default route).

**VM6 (DMZ):** deny incoming except SSH, HTTP/S

## Snapshots

```bash
# Create a snapshot (VM must be stopped)
multipass stop stockholm
multipass snapshot stockholm --name <name>
multipass start stockholm

# Restore a snapshot
multipass stop stockholm
multipass restore stockholm.<name>
multipass start stockholm

# List snapshots
multipass info stockholm --snapshots
```

Current snapshots:

- `clean-ufw-baseline` — All containers running, UFW configured and tested, before any service configuration

## Multipass VM Management

```bash
# Check VM status and resource usage
multipass info stockholm

# Resize resources (VM must be stopped)
multipass stop stockholm
multipass set local.stockholm.cpus=8
multipass set local.stockholm.memory=16G
multipass set local.stockholm.disk=50G
multipass start stockholm
```

## Teardown (Nuclear Option)

Delete everything when the project is done. Run from macOS host:

```bash
# 1. Delete the Multipass VM and all its snapshots
multipass delete stockholm
multipass purge

# 2. (Optional) Uninstall Multipass entirely
brew uninstall multipass

# 3. Clean up Multipass residual data
sudo rm -rf /var/root/Library/Application\ Support/multipassd
rm -rf ~/Library/Application\ Support/multipass
rm -rf ~/Library/Caches/multipass
```

After this, nothing from the project remains on the system.

## Known Issues

**UFW FORWARD chain bug in LXD:** `ufw enable` inside LXD privileged containers doesn't populate the iptables FORWARD chain with jumps to UFW sub-chains. `configure-ufw.sh` handles this automatically with `fix_lxd_forward_chain()`. If you manually enable UFW inside a container, you may need to re-run `configure-ufw.sh`.

**UFW must be re-applied after VM reboot:** The LXD FORWARD chain fix is not persistent across Multipass VM restarts. After `multipass stop/start`, re-run `configure-ufw.sh` inside the VM.
