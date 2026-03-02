# ACME Corp — Stockholm Site

KTH networks course project. Multi-site corporate network built with Vagrant/VirtualBox VMs.

Stockholm runs 4 VMs (VM1, VM2, VM3, VM6). London (VM4, VM5) runs on a teammate's machine, connected via IPsec VPN.

## Network Topology

```
             Internet
                │
          ┌─────┴──────┐
          │   VM1-GW   │  enp0s3: Vagrant NAT (internet)
          │   Gateway   │  enp0s8: 10.0.1.1/26   (VLAN 10)
          │            │  enp0s9: 10.0.1.129/26 (VLAN 20)
          │            │  enp0s10: 10.0.1.241/28 (VLAN 30)
          └──┬───┬──┬──┘
             │   │  │
    ┌────────┘   │  └────────┐
    │            │           │
 VLAN 10     VLAN 20     VLAN 30
10.0.1.0/26  10.0.1.128/26  10.0.1.240/28
(Server/CA)  (Client/London) (DMZ)
    │                        │
 ┌──┴───┐               ┌───┴───┐
 │VM2   │ 10.0.1.2      │VM6    │ 10.0.1.242
 │Server│ Nginx, BIND9,  │DMZ    │ Docker, Nginx,
 │      │ Syncthing      │       │ Certbot
 ├──────┤               └───────┘
 │VM3   │ 10.0.1.3
 │CA    │ FreeRADIUS, EasyRSA
 │      │ (air-gapped)
 └──────┘
```

## Prerequisites

- macOS (or Linux/Windows with VirtualBox support)
- [VirtualBox](https://www.virtualbox.org/) 7.x
- [Vagrant](https://www.vagrantup.com/) 2.4+
- ~16 GB RAM and ~50 GB disk available

```bash
brew install --cask virtualbox vagrant
```

## Quick Start

```bash
# 1. Create and provision all VMs (~5 min)
vagrant up

# 2. Apply firewall rules (from project directory)
bash configure-ufw.sh

# 3. Verify firewall policies
bash test-firewall.sh
```

## Scripts

| Script | Run From | Purpose |
|---|---|---|
| `vagrant up` | Host (project dir) | Create and provision all VMs |
| `configure-ufw.sh` | Host (project dir) | Apply UFW firewall rules to all VMs |
| `test-firewall.sh` | Host (project dir) | Verify firewall policies with connectivity tests |
| `reset-ufw.sh` | Host (project dir) | Disable all UFW rules on all VMs |

## VMs

| VM | Hostname | VLAN | IP | Key Services |
|---|---|---|---|---|
| VM1 | vm1-gw | 10, 20, 30 | 10.0.1.1, .129, .241 | StrongSwan IPsec, Suricata IDS, Fail2ban, NAT |
| VM2 | vm2-srv | 10 | 10.0.1.2 | Nginx, BIND9, Docker, Syncthing |
| VM3 | vm3-ca | 10 | 10.0.1.3 | FreeRADIUS, Easy-RSA (air-gapped) |
| VM6 | vm6-dmz | 30 | 10.0.1.242 | Docker, Nginx, Certbot |

## SSH Access

```bash
vagrant ssh vm1-gw
vagrant ssh vm2-srv
vagrant ssh vm3-ca
vagrant ssh vm6-dmz
```

## Interface Mapping (VirtualBox)

All VMs have a Vagrant NAT adapter (`enp0s3`) for management. VLAN interfaces:

| VM | enp0s8 | enp0s9 | enp0s10 |
|---|---|---|---|
| VM1 | VLAN 10 (10.0.1.1) | VLAN 20 (10.0.1.129) | VLAN 30 (10.0.1.241) |
| VM2 | VLAN 10 (10.0.1.2) | — | — |
| VM3 | VLAN 10 (10.0.1.3) | — | — |
| VM6 | VLAN 30 (10.0.1.242) | — | — |

## Firewall Policy Summary

**VM1 (Gateway):**
- Default deny incoming/routed, allow outgoing
- NAT masquerade for 10.0.1.0/24 outbound on enp0s3
- DMZ blocked from Server and Client VLANs (deny before allow)
- VLANs 10/20/30 allowed outbound to internet
- Internet inbound to DMZ on ports 80/443 only
- VLAN 20 → VLAN 10 restricted to ports 443, 8384, 53 (not VM3)

**VM2 (Server):** deny incoming except SSH, HTTP/S, DNS, Syncthing (8384, 22000)

**VM3 (CA):** deny incoming except SSH, RADIUS (1812-1813/udp). Air-gapped (no default route).

**VM6 (DMZ):** deny incoming except SSH, HTTP/S

## IPsec to London (Demo Day)

For the S2S tunnel between laptops on demo day, add a bridged adapter to VM1 in the Vagrantfile:

```ruby
gw.vm.network "public_network", bridge: "en0: Wi-Fi"
```

Then `vagrant reload vm1-gw` to apply. Update StrongSwan config with the new WAN IP.

## Vagrant Tips

```bash
vagrant status              # VM states
vagrant halt                # Stop all VMs (preserves disk)
vagrant up                  # Start stopped VMs
vagrant provision vm2-srv   # Re-run provisioner on one VM
vagrant destroy -f          # Delete everything

# Snapshots
vagrant snapshot save vm1-gw clean-baseline
vagrant snapshot restore vm1-gw clean-baseline
vagrant snapshot list
```

## Known Issues

**Air-gap uses DHCP override:** VM3's air-gap is implemented by disabling DHCP-provided routes on enp0s3 (`dhcp4-overrides: use-routes: false`). The Vagrant NAT interface stays up for `vagrant ssh` but has no default route. To temporarily restore internet on VM3 for package installs:

```bash
vagrant ssh vm3-ca -c "sudo ip route add default via 10.0.2.2 dev enp0s3"
# ... install packages ...
vagrant ssh vm3-ca -c "sudo ip route del default via 10.0.2.2 dev enp0s3"
```
