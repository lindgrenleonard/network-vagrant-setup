# -*- mode: ruby -*-
# vi: set ft=ruby :
# =============================================================================
# ACME Stockholm Site — VirtualBox VMs via Vagrant
# =============================================================================
# Creates VM1 (Gateway), VM2 (Server), VM3 (CA), VM6 (DMZ).
# London (VM4, VM5) runs on a teammate's laptop.
#
# USAGE:
#   brew install --cask virtualbox vagrant
#   vagrant up
#   vagrant ssh vm1-gw
#
# NETWORKING:
#   Each VM gets a Vagrant NAT adapter (enp0s3) for management/provisioning.
#   VLAN interfaces use VirtualBox internal networks:
#     acme-vlan10  — Server VLAN (10.0.1.0/26)
#     acme-vlan20  — Client VLAN (10.0.1.128/26)
#     acme-vlan30  — DMZ VLAN   (10.0.1.240/28)
#
#   For IPsec to London on demo day, add a bridged adapter to VM1:
#     gw.vm.network "public_network", bridge: "en0: Wi-Fi"
# =============================================================================

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"

  # ──────────────────────────────────────────────
  # VM1: Stockholm Gateway
  # ──────────────────────────────────────────────
  config.vm.define "vm1-gw", primary: true do |gw|
    gw.vm.hostname = "vm1-gw"
    gw.vm.provider "virtualbox" do |vb|
      vb.name = "acme-vm1-gw"
      vb.memory = 2048
      vb.cpus = 2
    end
    # VLAN 10 — Server (enp0s8)
    gw.vm.network "private_network", ip: "10.0.1.1",
      netmask: "255.255.255.192",
      virtualbox__intnet: "acme-vlan10"
    # VLAN 20 — Client (enp0s9)
    gw.vm.network "private_network", ip: "10.0.1.129",
      netmask: "255.255.255.192",
      virtualbox__intnet: "acme-vlan20"
    # VLAN 30 — DMZ (enp0s10)
    gw.vm.network "private_network", ip: "10.0.1.241",
      netmask: "255.255.255.240",
      virtualbox__intnet: "acme-vlan30"
    gw.vm.provision "shell", path: "provision/vm1-gw.sh"
  end

  # ──────────────────────────────────────────────
  # VM2: Stockholm Server
  # ──────────────────────────────────────────────
  config.vm.define "vm2-srv" do |srv|
    srv.vm.hostname = "vm2-srv"
    srv.vm.provider "virtualbox" do |vb|
      vb.name = "acme-vm2-srv"
      vb.memory = 8192
      vb.cpus = 4
    end
    # VLAN 10 — Server (enp0s8)
    srv.vm.network "private_network", ip: "10.0.1.2",
      netmask: "255.255.255.192",
      virtualbox__intnet: "acme-vlan10"
    srv.vm.provision "shell", path: "provision/vm2-srv.sh"
  end

  # ──────────────────────────────────────────────
  # VM3: CA Server (air-gapped post-provision)
  # ──────────────────────────────────────────────
  config.vm.define "vm3-ca" do |ca|
    ca.vm.hostname = "vm3-ca"
    ca.vm.provider "virtualbox" do |vb|
      vb.name = "acme-vm3-ca"
      vb.memory = 2048
      vb.cpus = 1
    end
    # VLAN 10 — Server (enp0s8)
    ca.vm.network "private_network", ip: "10.0.1.3",
      netmask: "255.255.255.192",
      virtualbox__intnet: "acme-vlan10"
    ca.vm.provision "shell", path: "provision/vm3-ca.sh"
  end

  # ──────────────────────────────────────────────
  # VM6: DMZ
  # ──────────────────────────────────────────────
  config.vm.define "vm6-dmz" do |dmz|
    dmz.vm.hostname = "vm6-dmz"
    dmz.vm.provider "virtualbox" do |vb|
      vb.name = "acme-vm6-dmz"
      vb.memory = 2048
      vb.cpus = 1
    end
    # VLAN 30 — DMZ (enp0s8)
    dmz.vm.network "private_network", ip: "10.0.1.242",
      netmask: "255.255.255.240",
      virtualbox__intnet: "acme-vlan30"
    dmz.vm.provision "shell", path: "provision/vm6-dmz.sh"
  end
end
