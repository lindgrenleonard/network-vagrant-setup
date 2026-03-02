#!/bin/bash
# =============================================================================
# VM6 (DMZ) — Provisioner
# Installs: docker, certbot, nginx
# Configures: inter-VLAN routes through VM1
# =============================================================================
set -euo pipefail

echo ">>> Provisioning VM6 (DMZ)..."

# ── Packages ──
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    iptables iproute2 iputils-ping net-tools tcpdump curl \
    docker.io certbot nginx

# ── Inter-VLAN routes via VM1 gateway ──
# VM6 is on VLAN 30 (10.0.1.240/28). Route to other VLANs through VM1
# so that firewall rules are enforced (DMZ isolation).
cat > /etc/netplan/99-acme-routes.yaml << 'YAML'
network:
  version: 2
  ethernets:
    enp0s8:
      routes:
        - to: 10.0.1.0/26
          via: 10.0.1.241
        - to: 10.0.1.128/26
          via: 10.0.1.241
YAML
netplan apply 2>/dev/null || true

echo ">>> VM6 (DMZ) provisioned."
