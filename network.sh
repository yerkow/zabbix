#!/bin/bash

# Настройка статической сети через Netplan
configure_network() {
  local interface="$1"
  local ip_address="$2"
  local netmask="$3"
  local gateway="$4"
  local dns="$5"
  local mtu="$6"

  local cidr

  # Конвертация netmask в CIDR
  IFS=. read -r i1 i2 i3 i4 <<< "$netmask"
  total_bits=$(printf "%08d%08d%08d%08d\n" "$(echo "obase=2;$i1" | bc)" "$(echo "obase=2;$i2" | bc)" "$(echo "obase=2;$i3" | bc)" "$(echo "obase=2;$i4" | bc)")
  cidr=$(grep -o "1" <<< "$total_bits" | wc -l)

  echo "Configuring static IP for interface: $interface"
  echo "  IP Address: $ip_address/$cidr"
  echo "  Gateway: $gateway"
  echo "  DNS: $dns"
  echo "  MTU: $mtu"

  # Проверка Netplan
  if command -v netplan >/dev/null 2>&1 && [ -d /etc/netplan ]; then
    cat > /etc/netplan/01-zabbix-network.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $interface:
      dhcp4: no
      addresses:
        - $ip_address/$cidr
      routes:
        - to: default
          via: $gateway
      nameservers:
        addresses: [$dns]
      mtu: $mtu
EOF

    netplan apply
    echo "✅ Network configuration applied via Netplan."
  else
    echo "⚠️ Netplan not found. Skipping network config."
  fi
}

