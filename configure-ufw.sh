#!/bin/bash
set -euo pipefail

echo "====================================================="
echo " Configuring UFW for ACME Stockholm LXD Environment"
echo "====================================================="

# ─────────────────────────────────────────────────────────
# 1. Configure VM1 (Gateway) - Core Routing Firewall
# ─────────────────────────────────────────────────────────
echo ">>> Setting up VM1 (Gateway) UFW rules..."

# Inject NAT (Masquerade) rules into UFW's before.rules so internal VMs can reach the internet
# UFW flushes raw iptables, so this is required for the gateway to NAT properly.
lxc exec vm1-gw -- bash -c '
if ! grep -q "*nat" /etc/ufw/before.rules; then
cat << EOF | sed -i "1i \\
*nat\\
:POSTROUTING ACCEPT [0:0]\\
-A POSTROUTING -s 10.0.1.0/24 -o eth0 -j MASQUERADE\\
COMMIT\\
" /etc/ufw/before.rules
fi
'

# Enable IP forwarding at the UFW level
lxc exec vm1-gw -- sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/default/ufw

# Baseline policies (Default Deny)
lxc exec vm1-gw -- ufw default deny incoming
lxc exec vm1-gw -- ufw default allow outgoing
lxc exec vm1-gw -- ufw default deny routed

# Host-level ingress (SSH rate limiting & IPsec)
lxc exec vm1-gw -- ufw limit ssh comment "Rate limit SSH (6/30s)"
lxc exec vm1-gw -- ufw allow 500,4500/udp comment "IKEv2/IPsec S2S tunnel"
lxc exec vm1-gw -- ufw allow proto esp comment "IPsec ESP traffic"

# Forwarding: Allow outbound internet from internal networks
lxc exec vm1-gw -- ufw route allow in on eth1 out on eth0 comment "VLAN 10 to Internet"
lxc exec vm1-gw -- ufw route allow in on eth2 out on eth0 comment "VLAN 20 to Internet"
lxc exec vm1-gw -- ufw route allow in on eth3 out on eth0 comment "VLAN 30 (DMZ) to Internet"

# Forwarding: DMZ Ingress (Internet to Spin-off Web Servers)
lxc exec vm1-gw -- ufw route allow in on eth0 out on eth3 to 10.0.1.242 port 80,443 proto tcp comment "HTTP/HTTPS to DMZ"

# Forwarding: Strict Inter-VLAN constraints (VLAN 20 to VLAN 10)
lxc exec vm1-gw -- ufw route deny in on eth2 out on eth1 to 10.0.1.3 comment "VLAN 20 to VM3 (CA) blocked"
lxc exec vm1-gw -- ufw route allow in on eth2 out on eth1 to 10.0.1.0/26 port 443,8384 proto tcp comment "VLAN 20 to VLAN 10 (HTTPS, Syncthing)"
lxc exec vm1-gw -- ufw route allow in on eth2 out on eth1 to 10.0.1.0/26 port 53 comment "VLAN 20 to VLAN 10 (DNS)"

# Forwarding: DMZ Isolation (Explicit Deny)
lxc exec vm1-gw -- ufw route deny in on eth3 out on eth1 comment "DMZ to VLAN 10 blocked"
lxc exec vm1-gw -- ufw route deny in on eth3 out on eth2 comment "DMZ to VLAN 20 blocked"

# Enable UFW on Gateway
lxc exec vm1-gw -- ufw --force enable


# ─────────────────────────────────────────────────────────
# 2. Configure VM2 (Server)
# ─────────────────────────────────────────────────────────
echo ">>> Setting up VM2 (Server) UFW rules..."
lxc exec vm2-srv -- ufw default deny incoming
lxc exec vm2-srv -- ufw default allow outgoing

lxc exec vm2-srv -- ufw limit ssh comment "Rate limit SSH"
lxc exec vm2-srv -- ufw allow 80,443/tcp comment "Nginx Web Services"
lxc exec vm2-srv -- ufw allow 53 comment "BIND9 DNS"
lxc exec vm2-srv -- ufw allow 8384/tcp comment "Syncthing GUI/API"
lxc exec vm2-srv -- ufw allow 22000/tcp comment "Syncthing Sync"

lxc exec vm2-srv -- ufw --force enable


# ─────────────────────────────────────────────────────────
# 3. Configure VM3 (CA Server)
# ─────────────────────────────────────────────────────────
echo ">>> Setting up VM3 (CA) UFW rules..."
lxc exec vm3-ca -- ufw default deny incoming
lxc exec vm3-ca -- ufw default allow outgoing

lxc exec vm3-ca -- ufw limit ssh comment "Rate limit SSH"
lxc exec vm3-ca -- ufw allow 1812,1813/udp comment "FreeRADIUS authentication/accounting"
# (HTTP/HTTPS for CRL/OCSP can be opened later when FreeIPA is configured)

lxc exec vm3-ca -- ufw --force enable


# ─────────────────────────────────────────────────────────
# 4. Configure VM6 (DMZ)
# ─────────────────────────────────────────────────────────
echo ">>> Setting up VM6 (DMZ) UFW rules..."
lxc exec vm6-dmz -- ufw default deny incoming
lxc exec vm6-dmz -- ufw default allow outgoing

lxc exec vm6-dmz -- ufw limit ssh comment "Rate limit SSH"
lxc exec vm6-dmz -- ufw allow 80,443/tcp comment "Spin-off Web (Docker) & Certbot"

lxc exec vm6-dmz -- ufw --force enable

echo "====================================================="
echo " UFW configuration complete!"
echo " Use 'lxc exec <vm-name> -- ufw status verbose' to verify."
echo "====================================================="