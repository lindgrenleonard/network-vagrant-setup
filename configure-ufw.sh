#!/bin/bash
set -euo pipefail

echo "====================================================="
echo " Configuring UFW for ACME Stockholm LXD Environment"
echo "====================================================="

# Helper to run lxc with guaranteed group permissions
run_lxd() {
    sg lxd -c "$1"
}

# LXD privileged containers have a bug where `ufw enable` does not populate
# the iptables FORWARD chain with jumps to UFW's sub-chains. This function
# detects the missing jumps and adds them, making the script safe to re-run.
fix_lxd_forward_chain() {
    local vm="$1"
    run_lxd "lxc exec $vm -- bash -c '
        if ! iptables -L FORWARD -n 2>/dev/null | grep -q ufw-before-forward; then
            iptables -A FORWARD -j ufw-before-logging-forward
            iptables -A FORWARD -j ufw-before-forward
            iptables -A FORWARD -j ufw-after-forward
            iptables -A FORWARD -j ufw-after-logging-forward
            iptables -A FORWARD -j ufw-reject-forward
            iptables -A FORWARD -j ufw-track-forward
        fi
    '"
}

# ─────────────────────────────────────────────────────────
# 1. Configure VM1 (Gateway) - Core Routing Firewall
# ─────────────────────────────────────────────────────────
echo ">>> Setting up VM1 (Gateway) UFW rules..."

# Wipe all existing rules and reset to defaults
run_lxd 'lxc exec vm1-gw -- ufw --force reset'

# Ensure the default forward policy is set to DROP to enforce zero-trust routing
run_lxd 'lxc exec vm1-gw -- sed -i "s/DEFAULT_FORWARD_POLICY=\"ACCEPT\"/DEFAULT_FORWARD_POLICY=\"DROP\"/g" /etc/default/ufw'

# Patch before.rules:
# 1. Inject NAT (Masquerade) at the top. `ufw reset` restores the default
#    before.rules — we insert the *nat table before *filter so the rest of
#    the file (conntrack, icmp, chain definitions) stays intact. Using sed
#    avoids the fragile cat-pipe pattern that could truncate the file.
# 2. Remove the blanket ICMP echo-request ACCEPT from the FORWARD chain.
#    Without this, pings bypass all user deny rules (including DMZ isolation).
#    ICMP forwarding is then controlled by the ufw route rules instead.
run_lxd 'lxc exec vm1-gw -- bash -c "
    sed -i \"/^\\*nat/,/^COMMIT/d\" /etc/ufw/before.rules
    sed -i \"1i *nat\\n:POSTROUTING ACCEPT [0:0]\\n-A POSTROUTING -s 10.0.1.0/24 -o eth0 -j MASQUERADE\\nCOMMIT\\n\" /etc/ufw/before.rules
    sed -i \"/ufw-before-forward.*icmp.*echo-request/d\" /etc/ufw/before.rules
"'

# Baseline policies (Default Deny)
run_lxd 'lxc exec vm1-gw -- ufw default deny incoming'
run_lxd 'lxc exec vm1-gw -- ufw default allow outgoing'
run_lxd 'lxc exec vm1-gw -- ufw default deny routed'

# Host-level ingress (SSH rate limiting & IPsec)
run_lxd 'lxc exec vm1-gw -- ufw limit ssh comment "Rate limit SSH (6/30s)"'
run_lxd 'lxc exec vm1-gw -- ufw allow 500,4500/udp comment "IKEv2/IPsec S2S tunnel"'
run_lxd 'lxc exec vm1-gw -- ufw allow proto esp from any to any comment "IPsec ESP traffic"'

# ─── ROUTING POLICIES ───

# 1. Explicitly Deny DMZ -> Internal (Defense in Depth - Priority 1)
run_lxd 'lxc exec vm1-gw -- ufw route deny from 10.0.1.240/28 to 10.0.1.0/26 comment "Strict Block: DMZ to Server VLAN"'
run_lxd 'lxc exec vm1-gw -- ufw route deny from 10.0.1.240/28 to 10.0.1.128/25 comment "Strict Block: DMZ to Client VLAN"'

# 2. Forwarding: Allow outbound internet from internal networks
run_lxd 'lxc exec vm1-gw -- ufw route allow in on eth1 out on eth0 from 10.0.1.0/26 to any comment "VLAN 10 to Internet"'
run_lxd 'lxc exec vm1-gw -- ufw route allow in on eth2 out on eth0 from 10.0.1.128/25 to any comment "VLAN 20 to Internet"'
run_lxd 'lxc exec vm1-gw -- ufw route allow in on eth3 out on eth0 from 10.0.1.240/28 to any comment "VLAN 30 (DMZ) to Internet"'

# 3. Forwarding: DMZ Ingress (Internet to Spin-off Web Servers) [cite: 241, 253]
run_lxd 'lxc exec vm1-gw -- ufw route allow in on eth0 out on eth3 to 10.0.1.242 port 80,443 proto tcp comment "HTTP/HTTPS to DMZ"'

# 4. Forwarding: Strict Inter-VLAN constraints (VLAN 20 to VLAN 10) [cite: 224]
run_lxd 'lxc exec vm1-gw -- ufw route deny from 10.0.1.128/25 to 10.0.1.3 comment "VLAN 20 to VM3 (CA) blocked"'
run_lxd 'lxc exec vm1-gw -- ufw route allow from 10.0.1.128/25 to 10.0.1.0/26 port 443,8384 proto tcp comment "VLAN 20 to VLAN 10 (HTTPS, Syncthing)"'
run_lxd 'lxc exec vm1-gw -- ufw route allow from 10.0.1.128/25 to 10.0.1.0/26 port 53 comment "VLAN 20 to VLAN 10 (DNS)"'

# Enable UFW on Gateway and fix LXD FORWARD chain bug
run_lxd 'lxc exec vm1-gw -- ufw --force enable'
fix_lxd_forward_chain vm1-gw


# ─────────────────────────────────────────────────────────
# 2. Configure VM2 (Server)
# ─────────────────────────────────────────────────────────
echo ">>> Setting up VM2 (Server) UFW rules..."
run_lxd 'lxc exec vm2-srv -- ufw --force reset'
run_lxd 'lxc exec vm2-srv -- ufw default deny incoming'
run_lxd 'lxc exec vm2-srv -- ufw default allow outgoing'

run_lxd 'lxc exec vm2-srv -- ufw limit ssh comment "Rate limit SSH"'
run_lxd 'lxc exec vm2-srv -- ufw allow 80,443/tcp comment "Nginx Web Services"'
run_lxd 'lxc exec vm2-srv -- ufw allow 53 comment "BIND9 DNS"'
run_lxd 'lxc exec vm2-srv -- ufw allow 8384/tcp comment "Syncthing GUI/API"'
run_lxd 'lxc exec vm2-srv -- ufw allow 22000/tcp comment "Syncthing Sync"'
run_lxd 'lxc exec vm2-srv -- ufw --force enable'
fix_lxd_forward_chain vm2-srv


# ─────────────────────────────────────────────────────────
# 3. Configure VM3 (CA Server)
# ─────────────────────────────────────────────────────────
echo ">>> Setting up VM3 (CA) UFW rules..."
run_lxd 'lxc exec vm3-ca -- ufw --force reset'
run_lxd 'lxc exec vm3-ca -- ufw default deny incoming'
run_lxd 'lxc exec vm3-ca -- ufw default allow outgoing'

run_lxd 'lxc exec vm3-ca -- ufw limit ssh comment "Rate limit SSH"'
run_lxd 'lxc exec vm3-ca -- ufw allow 1812,1813/udp comment "FreeRADIUS auth"'
run_lxd 'lxc exec vm3-ca -- ufw --force enable'
fix_lxd_forward_chain vm3-ca


# ─────────────────────────────────────────────────────────
# 4. Configure VM6 (DMZ)
# ─────────────────────────────────────────────────────────
echo ">>> Setting up VM6 (DMZ) UFW rules..."
run_lxd 'lxc exec vm6-dmz -- ufw --force reset'
run_lxd 'lxc exec vm6-dmz -- ufw default deny incoming'
run_lxd 'lxc exec vm6-dmz -- ufw default allow outgoing'

run_lxd 'lxc exec vm6-dmz -- ufw limit ssh comment "Rate limit SSH"'
run_lxd 'lxc exec vm6-dmz -- ufw allow 80,443/tcp comment "Spin-off Web (Docker) & Certbot"'
run_lxd 'lxc exec vm6-dmz -- ufw --force enable'
fix_lxd_forward_chain vm6-dmz

echo "====================================================="
echo " UFW configuration complete!"
echo " Use 'lxc exec <vm-name> -- ufw status verbose' to verify."
echo "====================================================="