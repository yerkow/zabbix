#!/bin/bash

# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to log messages
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Function to log errors
error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Function to log warnings
warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Please run as root"
        exit 1
    fi
}

# Function to update system
update_system() {
    log "Updating system packages..."
    apt update && apt upgrade -y
}

# Function to install dependencies
install_dependencies() {
    log "Installing required dependencies..."
    apt install -y wget curl gnupg2 lsb-release software-properties-common
}

# Function to get user input
get_user_input() {
    read -p "Enter Zabbix Server IP address: " ZABBIX_SERVER_IP
    read -p "Enter Hostname for this proxy: " PROXY_HOSTNAME
    read -p "Enter Proxy mode (active/passive): " PROXY_MODE
    read -p "Enter Interface to configure (e.g., eth0): " INTERFACE
    read -p "Enter Static IP address: " STATIC_IP
    read -p "Enter Netmask: " NETMASK
    read -p "Enter Gateway (optional, press Enter to skip): " GATEWAY
    read -p "Enter DNS server (optional, press Enter to skip): " DNS_SERVER
    read -p "Enter MTU (optional, press Enter to skip): " MTU
}

# Function to configure network
configure_network() {
    log "Configuring network interface $INTERFACE..."
    
    # Create network configuration file
    cat > /etc/network/interfaces.d/$INTERFACE << EOF
auto $INTERFACE
iface $INTERFACE inet static
    address $STATIC_IP
    netmask $NETMASK
EOF

    # Add optional parameters if provided
    if [ ! -z "$GATEWAY" ]; then
        echo "    gateway $GATEWAY" >> /etc/network/interfaces.d/$INTERFACE
    fi
    
    if [ ! -z "$DNS_SERVER" ]; then
        echo "    dns-nameservers $DNS_SERVER" >> /etc/network/interfaces.d/$INTERFACE
    fi
    
    if [ ! -z "$MTU" ]; then
        echo "    mtu $MTU" >> /etc/network/interfaces.d/$INTERFACE
    fi

    # Reload network configuration
    systemctl restart networking
}

# Function to configure SSH
configure_ssh() {
    log "Configuring SSH..."
    
    # Regenerate SSH host keys
    rm -f /etc/ssh/ssh_host_*
    dpkg-reconfigure openssh-server
    
    # Add authorized key
    mkdir -p ~/.ssh
    echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDY1wSu33I9O3qvCtjc7KfNHpe/Wuq7buZVwdbL8AC3/u5ZBS+bCZbuBXtGLWlH3/KoTmGbVYmT6Ye9mfgedTbLr5gfkbcyM9pmyg4IAt8DV3V3wBiCb6kPJrdjc1+SgqKSADHX0KwrQKVhe2eAVCp5G5lb9XrxCdudmWBoZb6uPoUQPirWZaqpnnbK5Kh8lRDMp7gSmiPi+6gvPvHyHEJBbvvcm4k8FXxhphXAhBG2W3oHqRcDo84Mz+vtg2Fl2KlV8uoBegjMsLQg078E6xEozniLyiq5dW08WN1w0Q6hb+oNpsmtyKxYam9/tHV62Na9+QfWMxbTYav1EdiCYrJ4qjXLwgKBOHFZy54MDO1fc5wN/NxxNNAjxSZYZU5h9Hfn6h4gACNeIf/tkvOkfF/rzjsjRPxhxqyEl8lIIEHXxxS6pDeqHghXrHTYrAoTypyDfw/lVrjEY07i5re3SLt3wVjkl2XJr/UD/daTpoAXHeDSRKnppUPkQbVfGu6iRwvwjaA71qbdkAvgqcTgI95F6NlVnRoxV0gvFdnt3BVOOOuT8niUZlIwDodrz8/XSzcO7FnvesRPFl1HUyuiUnulfDYOWklGeuDrMf8F1PdJC0QEbkjgXJ2uqT8qctsGbjMG61OFYThz7gGGMr9B5S27pxrb2QYqY19UF0A7lgM9iQ== nesirat@MacBook-Air-von-Yosef.local" > ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    
    # Configure SSH to allow root login
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
    systemctl restart sshd
}

# Function to install Zabbix Proxy
install_zabbix_proxy() {
    log "Installing Zabbix Proxy..."
    
    # Download and install Zabbix repository
    wget https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_7.0-1+debian12_all.deb
    dpkg -i zabbix-release_7.0-1+debian12_all.deb
    apt update
    
    # Install Zabbix Proxy with MySQL support
    apt install -y zabbix-proxy-mysql zabbix-sql-scripts
    
    # Configure Zabbix Proxy
    cat > /etc/zabbix/zabbix_proxy.conf << EOF
Server=$ZABBIX_SERVER_IP
Hostname=$PROXY_HOSTNAME
DBName=zabbix_proxy
DBUser=zabbix
DBPassword=zabbix
ProxyMode=$PROXY_MODE
EOF
    
    # Start and enable Zabbix Proxy service
    systemctl enable zabbix-proxy
    systemctl start zabbix-proxy
}

# Function to save configuration to memory.json
save_configuration() {
    log "Saving configuration to memory.json..."
    cat > memory.json << EOF
{
    "zabbix_server_ip": "$ZABBIX_SERVER_IP",
    "proxy_hostname": "$PROXY_HOSTNAME",
    "proxy_mode": "$PROXY_MODE",
    "network_interface": "$INTERFACE",
    "static_ip": "$STATIC_IP",
    "netmask": "$NETMASK",
    "gateway": "$GATEWAY",
    "dns_server": "$DNS_SERVER",
    "mtu": "$MTU",
    "installation_date": "$(date '+%Y-%m-%d %H:%M:%S')",
    "status": "completed"
}
EOF
}

# Function to create rules.json
create_rules() {
    log "Creating rules.json..."
    cat > rules.json << EOF
{
    "memory_management": {
        "max_file_size": "1MB",
        "cleanup_interval": "24h",
        "retention_period": "7d"
    },
    "action_triggers": {
        "network_change": {
            "restart_services": ["networking", "zabbix-proxy"],
            "notify": true
        },
        "proxy_config_change": {
            "restart_services": ["zabbix-proxy"],
            "notify": true
        }
    }
}
EOF
}

# Function to commit and push changes
commit_changes() {
    log "Committing and pushing changes to GitHub..."
    git add .
    git commit -m "Zabbix Proxy installation and configuration completed"
    git push origin main
}

# Function to verify installation
verify_installation() {
    log "Verifying Zabbix Proxy installation..."
    
    # Check if Zabbix Proxy is running
    if systemctl is-active --quiet zabbix-proxy; then
        log "Zabbix Proxy is running"
    else
        error "Zabbix Proxy is not running"
        exit 1
    fi
    
    # Test connection to Zabbix Server
    if nc -zv $ZABBIX_SERVER_IP 10051; then
        log "Connection to Zabbix Server successful"
    else
        error "Cannot connect to Zabbix Server"
        exit 1
    fi
}

# Main execution
main() {
    check_root
    update_system
    install_dependencies
    get_user_input
    configure_network
    configure_ssh
    install_zabbix_proxy
    save_configuration
    create_rules
    commit_changes
    verify_installation
    
    log "Zabbix Proxy installation and configuration completed successfully!"
}

# Execute main function
main 