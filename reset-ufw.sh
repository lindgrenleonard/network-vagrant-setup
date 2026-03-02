#!/bin/bash
# reset-ufw.sh - Resets UFW on all VMs to a clean disabled state.
# Run this inside the Multipass VM, then run test-firewall.sh to verify failures.
set -euo pipefail

echo "====================================================="
echo " Resetting UFW on all ACME Stockholm VMs"
echo "====================================================="

run_lxd() {
    sg lxd -c "$1"
}

for vm in vm1-gw vm2-srv vm3-ca vm6-dmz; do
    echo ">>> Resetting $vm..."
    run_lxd "lxc exec $vm -- ufw --force reset"
    run_lxd "lxc exec $vm -- ufw --force disable"
done

# Flush iptables FORWARD chain on gateway so no stale rules remain
run_lxd 'lxc exec vm1-gw -- iptables -F FORWARD'
run_lxd 'lxc exec vm1-gw -- iptables -P FORWARD ACCEPT'

echo "====================================================="
echo " All UFW rules reset. Firewalls are disabled."
echo " Run test-firewall.sh now — all tests should FAIL."
echo "====================================================="
