#!/bin/bash
# =============================================================================
# VM3 (CA Server) — Provisioner
# Installs: freeradius, easy-rsa, openssl
# Configures: air-gap (removes default route to internet)
# =============================================================================
set -euo pipefail

echo ">>> Provisioning VM3 (CA)..."

# ── Packages (installed via Vagrant NAT before air-gap) ──
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    iptables iproute2 iputils-ping net-tools tcpdump curl \
    freeradius freeradius-utils \
    openssl easy-rsa

# ── Inter-VLAN routes via VM1 + Air-gap ──
# Remove default route from Vagrant NAT (DHCP) so VM3 cannot reach internet.
# Keep the link-local 10.0.2.0/24 route (connected) so vagrant ssh still works.
# Only route to internal networks via VM1.
cat > /etc/netplan/99-acme-airgap.yaml << 'YAML'
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: true
      dhcp4-overrides:
        use-routes: false
    enp0s8:
      routes:
        - to: 10.0.1.128/26
          via: 10.0.1.1
        - to: 10.0.1.240/28
          via: 10.0.1.1
YAML
netplan apply 2>/dev/null || true

echo ">>> VM3 (CA) provisioned. Air-gap active (no default route)."
