# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KTH networks course project: ACME Corp multi-site network infrastructure using Vagrant/VirtualBox VMs on macOS. The Stockholm site runs VM1 (Gateway), VM2 (Server), VM3 (CA), VM6 (DMZ). London (VM4, VM5) runs on a teammate's machine.

## Architecture

### Network Topology
- **VM1 (vm1-gw)**: Multi-homed gateway with 4 NICs — Vagrant NAT (enp0s3, internet) + three internal VLANs (enp0s8/9/10)
- **VM2 (vm2-srv)**: Server VLAN 10 (10.0.1.2/26) — runs Nginx, BIND9 DNS, Syncthing
- **VM3 (vm3-ca)**: VLAN 10 (10.0.1.3/26) — air-gapped CA server with FreeRADIUS, no internet route
- **VM6 (vm6-dmz)**: VLAN 30 / DMZ (10.0.1.242/28) — Docker, Nginx, Certbot for spin-off web

### VLAN Subnets (VirtualBox Internal Networks)
- VLAN 10 (acme-vlan10): 10.0.1.0/26 — Server/CA
- VLAN 20 (acme-vlan20): 10.0.1.128/26 — Client (London)
- VLAN 30 (acme-vlan30): 10.0.1.240/28 — DMZ

### Interface Mapping
- enp0s3: Vagrant NAT (management/internet, present on all VMs)
- enp0s8: First VLAN interface
- enp0s9: Second VLAN interface (VM1 only: VLAN 20)
- enp0s10: Third VLAN interface (VM1 only: VLAN 30)

### Key Security Policies
- VM3 is air-gapped (DHCP route override removes default route)
- DMZ is isolated from internal VLANs (deny rules before allow)
- VM1 uses DEFAULT_FORWARD_POLICY=DROP with explicit allow rules
- IPsec (IKEv2) for site-to-site VPN between Stockholm and London

## Scripts

All scripts run from the host in the project directory (where Vagrantfile lives).

| Script | Purpose |
|---|---|
| `Vagrantfile` | Defines all 4 VMs with VirtualBox networking |
| `provision/vm1-gw.sh` | Gateway provisioner: packages, IP forwarding, NAT |
| `provision/vm2-srv.sh` | Server provisioner: packages, inter-VLAN routes |
| `provision/vm3-ca.sh` | CA provisioner: packages, air-gap netplan |
| `provision/vm6-dmz.sh` | DMZ provisioner: packages, inter-VLAN routes |
| `configure-ufw.sh` | Applies UFW firewall rules to all VMs via `vagrant ssh` |
| `test-firewall.sh` | Verifies firewall policies with ping-based tests |
| `reset-ufw.sh` | Strips all UFW rules and disables firewalls |

### Running

```bash
# Initial setup (from project directory)
brew install --cask virtualbox vagrant
vagrant up

# Configure firewalls and test
bash configure-ufw.sh
bash test-firewall.sh
```

### Accessing VMs
```bash
vagrant ssh vm1-gw
vagrant ssh vm2-srv
vagrant ssh vm3-ca
vagrant ssh vm6-dmz
```
