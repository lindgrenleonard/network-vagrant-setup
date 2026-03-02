#!/bin/bash
# test-firewall.sh - Verifies ACME Stockholm LXD UFW configuration

echo "=========================================================="
echo " Running Firewall Policy Tests for ACME Stockholm"
echo "=========================================================="

# Helper function to test ping connectivity and evaluate against expected results
check_ping() {
    local from_vm=$1
    local target_ip=$2
    local expected=$3
    local description=$4

    printf "  %-55s" "$description"
    
    # Run ping with 1 packet (-c 1) and a 1-second timeout (-W 1)
    if lxc exec "$from_vm" -- ping -c 1 -W 1 "$target_ip" > /dev/null 2>&1; then
        if [ "$expected" = "SUCCESS" ]; then
            echo "✅ PASS"
        else
            echo "❌ FAIL (Succeeded, but was expected to FAIL)"
        fi
    else
        if [ "$expected" = "FAIL" ]; then
            echo "✅ PASS (Blocked as expected)"
        else
            echo "❌ FAIL (Blocked, but was expected to SUCCEED)"
        fi
    fi
}

echo ""
echo "--- 1. Testing Outbound Internet Access ---"
check_ping vm2-srv 8.8.8.8 SUCCESS "VM2 (Server) can reach the Internet"
check_ping vm6-dmz 8.8.8.8 SUCCESS "VM6 (DMZ) can reach the Internet"

echo ""
echo "--- 2. Testing CA Server Air-Gap (R12/Security) ---"
check_ping vm3-ca 8.8.8.8 FAIL "VM3 (CA) cannot reach the Internet"

echo ""
echo "--- 3. Testing DMZ Isolation (R13/Security) ---"
check_ping vm6-dmz 10.0.1.2 FAIL "VM6 (DMZ) cannot reach VM2 (Server VLAN)"
check_ping vm6-dmz 10.0.1.3 FAIL "VM6 (DMZ) cannot reach VM3 (CA Server)"

echo ""
echo "--- 4. Testing Internal Base Connectivity ---"
check_ping vm2-srv 10.0.1.1 SUCCESS "VM2 (Server) can reach Gateway"
check_ping vm3-ca 10.0.1.1 SUCCESS "VM3 (CA) can reach Gateway"

echo ""
echo "=========================================================="
echo " Testing Complete."
echo " Note: Port-specific tests (VLAN 20 to VLAN 10 on port 443/53)"
echo " will require client endpoints to be deployed first."
echo "=========================================================="
