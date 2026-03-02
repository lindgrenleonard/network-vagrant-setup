#!/bin/bash
# =============================================================================
# ACME Stockholm Site — LXD on macOS via Multipass
# =============================================================================
# Runs VM1 (Gateway), VM2 (Server), VM3 (CA), VM6 (DMZ).
# London (VM4, VM5) runs on a teammate's laptop.
#
# USAGE:
#   1.  brew install multipass
#   2.  bash setup-stockholm.sh
#   3.  multipass shell stockholm
# =============================================================================

set -euo pipefail

VMNAME="stockholm"
CPUS=8
MEM="16G"
DISK="50G"
BOOTSTRAP="/tmp/acme-bootstrap.sh"

# ─────────────────────────────────────────────
# Step 1: Write the bootstrap script to a local temp file
# ─────────────────────────────────────────────

cat > "$BOOTSTRAP" << 'BOOTEOF'
#!/bin/bash
set -euo pipefail

echo ">>> Installing LXD..."
sudo snap install lxd --channel=5.21/stable 2>/dev/null || true
sudo usermod -aG lxd ubuntu

# 'sg lxd' runs a single command with lxd group privileges
# — avoids the newgrp + heredoc nesting problem entirely
run_lxd() {
    sg lxd -c "$1"
}

echo ">>> Initializing LXD..."
cat > /tmp/lxd-preseed.yaml << 'YAML'
config: {}
networks: []
storage_pools:
  - name: default
    driver: dir
    config: {}
profiles:
  - name: default
    devices:
      root:
        path: /
        pool: default
        type: disk
YAML
run_lxd 'cat /tmp/lxd-preseed.yaml | lxd init --preseed'

# ══════════════════════════════════════════════
# Bridges
# ══════════════════════════════════════════════
echo ">>> Creating bridges..."

run_lxd 'lxc network create br-vlan10 ipv4.address=none ipv4.nat=false ipv4.dhcp=false ipv6.address=none'
run_lxd 'lxc network create br-vlan20 ipv4.address=none ipv4.nat=false ipv4.dhcp=false ipv6.address=none'
run_lxd 'lxc network create br-vlan30 ipv4.address=none ipv4.nat=false ipv4.dhcp=false ipv6.address=none'
run_lxd 'lxc network create br-wan    ipv4.address=192.168.100.1/24 ipv4.nat=true ipv4.dhcp=false ipv6.address=none'

# ══════════════════════════════════════════════
# Profiles — written as separate yaml files, piped into lxc profile edit
# ══════════════════════════════════════════════
echo ">>> Creating profiles..."

# --- VM1: Stockholm Gateway (WAN + 3 VLANs) ---
run_lxd 'lxc profile create acme-vm1 2>/dev/null || true'
cat > /tmp/profile-vm1.yaml << 'YAML'
config:
  security.privileged: "true"
  security.nesting: "true"
  linux.kernel_modules: ip_tables,iptable_filter,iptable_nat,iptable_mangle,nf_nat,nf_conntrack,br_netfilter,esp4,ah4,xfrm_user,xfrm_algo,tun,veth
devices:
  root:
    path: /
    pool: default
    type: disk
  eth0:
    name: eth0
    nictype: bridged
    parent: br-wan
    type: nic
  eth1:
    name: eth1
    nictype: bridged
    parent: br-vlan10
    type: nic
  eth2:
    name: eth2
    nictype: bridged
    parent: br-vlan20
    type: nic
  eth3:
    name: eth3
    nictype: bridged
    parent: br-vlan30
    type: nic
YAML
run_lxd 'cat /tmp/profile-vm1.yaml | lxc profile edit acme-vm1'

# --- VM2: Stockholm Server ---
run_lxd 'lxc profile create acme-vm2 2>/dev/null || true'
cat > /tmp/profile-vm2.yaml << 'YAML'
config:
  security.privileged: "true"
  security.nesting: "true"
devices:
  root:
    path: /
    pool: default
    type: disk
  eth0:
    name: eth0
    nictype: bridged
    parent: br-vlan10
    type: nic
YAML
run_lxd 'cat /tmp/profile-vm2.yaml | lxc profile edit acme-vm2'

# --- VM3: CA Server ---
run_lxd 'lxc profile create acme-vm3 2>/dev/null || true'
cat > /tmp/profile-vm3.yaml << 'YAML'
config:
  security.privileged: "true"
devices:
  root:
    path: /
    pool: default
    type: disk
  eth0:
    name: eth0
    nictype: bridged
    parent: br-vlan10
    type: nic
YAML
run_lxd 'cat /tmp/profile-vm3.yaml | lxc profile edit acme-vm3'

# --- VM6: DMZ ---
run_lxd 'lxc profile create acme-vm6 2>/dev/null || true'
cat > /tmp/profile-vm6.yaml << 'YAML'
config:
  security.privileged: "true"
  security.nesting: "true"
devices:
  root:
    path: /
    pool: default
    type: disk
  eth0:
    name: eth0
    nictype: bridged
    parent: br-vlan30
    type: nic
YAML
run_lxd 'cat /tmp/profile-vm6.yaml | lxc profile edit acme-vm6'

# ══════════════════════════════════════════════
# Launch containers
# ══════════════════════════════════════════════
echo ">>> Launching containers..."

run_lxd 'lxc launch ubuntu:22.04 vm1-gw  --profile default --profile acme-vm1'
run_lxd 'lxc launch ubuntu:22.04 vm2-srv --profile default --profile acme-vm2'
run_lxd 'lxc launch ubuntu:22.04 vm3-ca  --profile default --profile acme-vm3'
run_lxd 'lxc launch ubuntu:22.04 vm6-dmz --profile default --profile acme-vm6'

echo ">>> Waiting for containers to boot..."
sleep 10

# ══════════════════════════════════════════════
# Static IPs — write netplan files, push into containers
# ══════════════════════════════════════════════
echo ">>> Configuring initial bootstrap IPs..."

# VM1: multi-homed gateway
cat > /tmp/netplan-vm1.yaml << 'YAML'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [192.168.100.10/24]
      routes:
        - to: default
          via: 192.168.100.1
      nameservers:
        addresses: [8.8.8.8]
    eth1:
      dhcp4: false
      addresses: [10.0.1.1/26]
    eth2:
      dhcp4: false
      addresses: [10.0.1.129/26]
    eth3:
      dhcp4: false
      addresses: [10.0.1.241/28]
YAML
run_lxd 'lxc file push /tmp/netplan-vm1.yaml vm1-gw/etc/netplan/90-acme.yaml'
run_lxd 'lxc exec vm1-gw -- chmod 600 /etc/netplan/90-acme.yaml'
run_lxd 'lxc exec vm1-gw -- netplan apply' 2>/dev/null || true
run_lxd 'lxc exec vm1-gw -- sysctl -w net.ipv4.ip_forward=1'

# VM2: server VLAN, default route via VM1
cat > /tmp/netplan-vm2.yaml << 'YAML'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [10.0.1.2/26]
      routes:
        - to: default
          via: 10.0.1.1
      nameservers:
        addresses: [127.0.0.1, 8.8.8.8]
YAML
run_lxd 'lxc file push /tmp/netplan-vm2.yaml vm2-srv/etc/netplan/90-acme.yaml'
run_lxd 'lxc exec vm2-srv -- chmod 600 /etc/netplan/90-acme.yaml'
run_lxd 'lxc exec vm2-srv -- netplan apply' 2>/dev/null || true

# VM3: TEMPORARY BOOTSTRAP NETPLAN (Has internet access for apt-get)
cat > /tmp/netplan-vm3-temp.yaml << 'YAML'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [10.0.1.3/26]
      routes:
        - to: default
          via: 10.0.1.1
      nameservers:
        addresses: [8.8.8.8]
YAML
run_lxd 'lxc file push /tmp/netplan-vm3-temp.yaml vm3-ca/etc/netplan/90-acme.yaml'
run_lxd 'lxc exec vm3-ca -- chmod 600 /etc/netplan/90-acme.yaml'
run_lxd 'lxc exec vm3-ca -- netplan apply' 2>/dev/null || true

# VM6: TEMPORARY BOOTSTRAP NETPLAN (Public DNS instead of VM2)
cat > /tmp/netplan-vm6-temp.yaml << 'YAML'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [10.0.1.242/28]
      routes:
        - to: default
          via: 10.0.1.241
      nameservers:
        addresses: [8.8.8.8]
YAML
run_lxd 'lxc file push /tmp/netplan-vm6-temp.yaml vm6-dmz/etc/netplan/90-acme.yaml'
run_lxd 'lxc exec vm6-dmz -- chmod 600 /etc/netplan/90-acme.yaml'
run_lxd 'lxc exec vm6-dmz -- netplan apply' 2>/dev/null || true

# ══════════════════════════════════════════════
# NAT on VM1 so internal containers can apt-get
# ══════════════════════════════════════════════
echo ">>> Setting up NAT on VM1..."
run_lxd 'lxc exec vm1-gw -- iptables -t nat -A POSTROUTING -o eth0 -s 10.0.1.0/24 -j MASQUERADE'
run_lxd 'lxc exec vm1-gw -- iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT'
run_lxd 'lxc exec vm1-gw -- iptables -A FORWARD -i eth3 -o eth0 -j ACCEPT'
run_lxd 'lxc exec vm1-gw -- iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT'

# ══════════════════════════════════════════════
# Install packages in parallel
# ══════════════════════════════════════════════
echo ">>> Installing packages (parallel, ~2 min)..."

sg lxd -c 'lxc exec vm1-gw -- bash -c "
    apt-get update -qq &&
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        iptables iproute2 iputils-ping net-tools tcpdump curl \
        strongswan strongswan-pki libcharon-extra-plugins \
        suricata fail2ban \
        > /var/log/bootstrap.log 2>&1
"' &
PID1=$!

sg lxd -c 'lxc exec vm2-srv -- bash -c "
    apt-get update -qq &&
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        iptables iproute2 iputils-ping net-tools tcpdump curl \
        nginx bind9 bind9utils \
        docker.io python3-pip python3-venv \
        > /var/log/bootstrap.log 2>&1
"' &
PID2=$!

sg lxd -c 'lxc exec vm3-ca -- bash -c "
    apt-get update -qq &&
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        iptables iproute2 iputils-ping net-tools tcpdump curl \
        freeradius freeradius-utils \
        openssl easy-rsa \
        > /var/log/bootstrap.log 2>&1
"' &
PID3=$!

sg lxd -c 'lxc exec vm6-dmz -- bash -c "
    apt-get update -qq &&
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        iptables iproute2 iputils-ping net-tools tcpdump curl \
        docker.io certbot nginx \
        > /var/log/bootstrap.log 2>&1
"' &
PID4=$!

wait $PID1 $PID2 $PID3 $PID4
echo ">>> All packages installed."

# ══════════════════════════════════════════════
# Post-Install Network Lockdown
# ══════════════════════════════════════════════
echo ">>> Applying strict network policies (Air-gapping VM3, Internal DNS for VM6)..."

# VM3: Strict Air-gapped Netplan
cat > /tmp/netplan-vm3-strict.yaml << 'YAML'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [10.0.1.3/26]
      routes:
        - to: 10.0.0.0/8
          via: 10.0.1.1
YAML
run_lxd 'lxc file push /tmp/netplan-vm3-strict.yaml vm3-ca/etc/netplan/90-acme.yaml'
run_lxd 'lxc exec vm3-ca -- netplan apply' 2>/dev/null || true

# VM6: Strict Internal DNS Netplan
cat > /tmp/netplan-vm6-strict.yaml << 'YAML'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [10.0.1.242/28]
      routes:
        - to: default
          via: 10.0.1.241
      nameservers:
        addresses: [10.0.1.2]
YAML
run_lxd 'lxc file push /tmp/netplan-vm6-strict.yaml vm6-dmz/etc/netplan/90-acme.yaml'
run_lxd 'lxc exec vm6-dmz -- netplan apply' 2>/dev/null || true

# Give the network a second to settle
sleep 2

# ══════════════════════════════════════════════
# Connectivity checks
# ══════════════════════════════════════════════
echo ""
echo ">>> Connectivity checks..."

check() {
    local from="$1" to="$2" label="$3"
    printf "  %-40s" "$label"
    if sg lxd -c "lxc exec $from -- ping -c1 -W2 $to" > /dev/null 2>&1; then
        echo "✓"
    else
        echo "✗"
    fi
}

check vm2-srv 10.0.1.1   "vm2-srv → vm1-gw  (VLAN 10):"
check vm3-ca  10.0.1.1   "vm3-ca  → vm1-gw  (VLAN 10):"
check vm3-ca  10.0.1.2   "vm3-ca  → vm2-srv (VLAN 10):"
check vm6-dmz 10.0.1.241 "vm6-dmz → vm1-gw  (VLAN 30):"

printf "  %-40s" "vm2-srv → internet:"
if sg lxd -c "lxc exec vm2-srv -- ping -c1 -W3 8.8.8.8" > /dev/null 2>&1; then
    echo "✓"
else
    echo "✗ (check NAT on vm1-gw)"
fi

printf "  %-40s" "vm3-ca  → internet (should FAIL):"
if sg lxd -c "lxc exec vm3-ca -- ping -c1 -W2 8.8.8.8" > /dev/null 2>&1; then
    echo "✗ PROBLEM — vm3 reached internet!"
else
    echo "✓ blocked (air-gapped)"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Stockholm site is ready!"
echo "════════════════════════════════════════════════════════════"
echo ""
run_lxd 'lxc list -c n,s,4 --format=table'
echo ""
echo "  Shell into containers:"
echo "    lxc exec vm1-gw  -- bash"
echo "    lxc exec vm2-srv -- bash"
echo "    lxc exec vm3-ca  -- bash"
echo "    lxc exec vm6-dmz -- bash"
echo ""
echo "  Troubleshooting logs if anything failed:"
echo "    lxc exec vm1-gw -- cat /var/log/bootstrap.log"
echo ""
echo "  Take snapshots now:"
echo "    for c in vm1-gw vm2-srv vm3-ca vm6-dmz; do"
echo "      lxc snapshot \$c fresh-install"
echo "    done"
echo ""
echo "  VM1 WAN: 192.168.100.10"
echo "════════════════════════════════════════════════════════════"
BOOTEOF

# ─────────────────────────────────────────────
# Step 2: Create the Multipass VM
# ─────────────────────────────────────────────
echo "═══ Creating Multipass VM: $VMNAME ═══"

if multipass info "$VMNAME" &>/dev/null; then
    echo "VM '$VMNAME' already exists."
    echo "  multipass delete $VMNAME && multipass purge"
    exit 1
fi

multipass launch 22.04 \
    --name "$VMNAME" \
    --cpus "$CPUS" \
    --memory "$MEM" \
    --disk "$DISK"

# ─────────────────────────────────────────────
# Step 3: Transfer bootstrap script and run it
# ─────────────────────────────────────────────
echo "═══ Transferring bootstrap script... ═══"
multipass transfer "$BOOTSTRAP" "${VMNAME}:/tmp/acme-bootstrap.sh"

echo "═══ Running bootstrap (takes a few minutes)... ═══"
multipass exec "$VMNAME" -- bash /tmp/acme-bootstrap.sh

rm -f "$BOOTSTRAP"

echo ""
echo "═══ Done! Enter with:  multipass shell $VMNAME ═══"