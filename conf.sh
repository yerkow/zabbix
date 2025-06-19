#!/bin/bash
# Script to update Zabbix Proxy configuration
# Author: IMAS (based on request)
# Usage:
#   ./update_zabbix_proxy_conf.sh <ZABBIX_SERVER_IP> <PROXY_HOSTNAME> [DB_PASSWORD]

set -e

CONFIG_FILE="/etc/zabbix/zabbix_proxy.conf"
SQLITE_DB_PATH="/var/lib/zabbix/zabbix_proxy.db"

update_zabbix_proxy_conf() {
  local server_ip="$1"
  local hostname="$2"
  local db_password="${3:-zabbix}"

  if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: $CONFIG_FILE not found!"
    exit 1
  fi

  echo "Updating $CONFIG_FILE..."

  # Update or insert key parameters
  sed -i "s/^Server=.*/Server=$server_ip/" "$CONFIG_FILE" || echo "Server=$server_ip" >> "$CONFIG_FILE"
  sed -i "s/^Hostname=.*/Hostname=$hostname/" "$CONFIG_FILE" || echo "Hostname=$hostname" >> "$CONFIG_FILE"
  sed -i "s/^# DBHost=.*/DBHost=localhost/" "$CONFIG_FILE"
  sed -i "s/^# DBPassword=.*/DBPassword=$db_password/" "$CONFIG_FILE"

  # Ensure they exist
  grep -q "^DBHost=" "$CONFIG_FILE" || echo "DBHost=localhost" >> "$CONFIG_FILE"
  grep -q "^DBPassword=" "$CONFIG_FILE" || echo "DBPassword=$db_password" >> "$CONFIG_FILE"

  # Set DBName for SQLite
  if grep -q "^DBName=" "$CONFIG_FILE"; then
    sed -i "s|^DBName=.*|DBName=$SQLITE_DB_PATH|" "$CONFIG_FILE"
  else
    echo "DBName=$SQLITE_DB_PATH" >> "$CONFIG_FILE"
  fi

  # Set ProxyMode=1 (active proxy)
  if grep -q "^ProxyMode=" "$CONFIG_FILE"; then
    sed -i "s/^ProxyMode=.*/ProxyMode=1/" "$CONFIG_FILE"
  else
    echo "ProxyMode=1" >> "$CONFIG_FILE"
  fi

  echo "✅ Configuration updated successfully."
}

# Entry point
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <ZABBIX_SERVER_IP> <PROXY_HOSTNAME> [DB_PASSWORD]"
  exit 1
fi

update_zabbix_proxy_conf "$1" "$2" "$3"

