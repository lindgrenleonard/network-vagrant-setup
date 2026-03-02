#!/bin/bash
# =============================================================================
# VM2 (Stockholm Server) — Provisioner
# Installs: nginx, bind9, docker, python3
# Configures: inter-VLAN routes through VM1
# =============================================================================
set -euo pipefail

echo ">>> Provisioning VM2 (Server)..."

# ── Packages ──
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    iptables iproute2 iputils-ping net-tools tcpdump curl \
    nginx bind9 bind9utils \
    docker.io python3-pip python3-venv

# ── Inter-VLAN routes via VM1 gateway ──
# Without these, traffic to other VLANs would go via the Vagrant NAT
# (bypassing VM1's firewall). These routes ensure inter-VLAN traffic
# is routed through VM1 where firewall rules are enforced.
cat > /etc/netplan/99-acme-routes.yaml << 'YAML'
network:
  version: 2
  ethernets:
    enp0s8:
      routes:
        - to: 10.0.1.128/26
          via: 10.0.1.1
        - to: 10.0.1.240/28
          via: 10.0.1.1
YAML
netplan apply 2>/dev/null || true

echo ">>> VM2 (Server) provisioned."
