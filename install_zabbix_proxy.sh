#!/bin/bash
# Zabbix Proxy Installation Script
# Version: 1.0.0
# Author: Your Name
# Description: Automated installation and configuration of Zabbix Proxy
# License: MIT

# Exit on error
set -e

# Default debug mode is off
DEBUG_MODE=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG_MODE=1
            shift
            ;;
        --zabbix-version)
            ZABBIX_VERSION="$2"
            shift 2
            ;;
        --zabbix-server)
            ZABBIX_SERVER="$2"
            shift 2
            ;;
        --proxy-hostname)
            PROXY_HOSTNAME="$2"
            shift 2
            ;;
        --db-name)
            DB_NAME="$2"
            shift 2
            ;;
        --db-password)
            DB_PASSWORD="$2"
            shift 2
            ;;
        --interface)
            INTERFACE="$2"
            shift 2
            ;;
        --non-interactive)
            NON_INTERACTIVE=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--debug] [--non-interactive] [--zabbix-version ver] [--zabbix-server addr] [--proxy-hostname name] [--db-name name] [--db-password pwd] [--interface iface]"
            exit 1
            ;;
    esac
done

# Set default values if in non-interactive mode
if [ "$NON_INTERACTIVE" = "1" ]; then
    ZABBIX_VERSION=${ZABBIX_VERSION:-"7.0"}
    ZABBIX_SERVER=${ZABBIX_SERVER:-"192.168.1.1"}
    PROXY_HOSTNAME=${PROXY_HOSTNAME:-"zabbix-proxy"}
    DB_NAME=${DB_NAME:-"zabbix_proxy"}
    DB_PASSWORD=${DB_PASSWORD:-"zabbix"}
    INTERFACE=${INTERFACE:-"ens18"}
fi

# Enable debug mode if requested
if [ "$DEBUG_MODE" -eq 1 ]; then
    set -x
fi

# Function to show interfaces with IP addresses
show_interface() {
    echo -e "\n\033[1;34mAvailable network interfaces and their IP addresses:\033[0m"
    echo -e "\033[1;34m------------------------------------------------\033[0m"
    ip -o addr show | awk '/inet / {print $1, $2, $4}'
    echo -e "\033[1;34m------------------------------------------------\033[0m"
}

# Function to get available interfaces
get_available_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo'
}

# Function to validate interface
validate_interface() {
    local interface="$1"
    if ip link show "$interface" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/zabbix_proxy_install.log
}

# Function to check command status
check_status() {
    if [ $? -eq 0 ]; then
        log_message "SUCCESS: $1"
    else
        log_message "ERROR: $1"
        exit 1
    fi
}

# Function to get user input with clear prompt
get_input() {
    local prompt="$1"
    local default="$2"
    local validation="$3"
    local input
    
    while true; do
        if [ -n "$default" ]; then
            echo -e "\n\033[1;32m$prompt\033[0m [\033[1;33m$default\033[0m]: "
            read -r input
            input=${input:-$default}
        else
            echo -e "\n\033[1;32m$prompt\033[0m: "
            read -r input
        fi
        
        # Clean up the input
        input=$(echo "$input" | tr -d '\r' | tr -d '\n' | tr -d '"' | tr -d "'" | tr -d ' ')
        
        if [ -n "$validation" ]; then
            if [[ $input =~ $validation ]]; then
                break
            else
                echo -e "\033[1;31mInvalid input. Please try again.\033[0m"
            fi
        else
            break
        fi
    done
    echo "$input"
}

# Function to configure hostname
configure_hostname() {
    local hostname="$1"
    log_message "Configuring system hostname..."
    
    # Set hostname using hostnamectl
    hostnamectl set-hostname "$hostname"
    check_status "Setting hostname with hostnamectl"
    
    # Update /etc/hosts
    log_message "Updating /etc/hosts file..."
    if ! grep -q "$hostname" /etc/hosts; then
        # Get current IP address
        local current_ip=$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
        
        # Create a backup of the original file
        cp /etc/hosts /etc/hosts.bak
        
        # Update hosts file
        cat > /etc/hosts << EOF
127.0.0.1       localhost
127.0.1.1       $hostname
$current_ip      $hostname

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
        check_status "Updating /etc/hosts"
    else
        log_message "Hostname already exists in /etc/hosts, skipping update"
    fi
}

# Function to get available versions
get_available_versions() {
    local base_url="https://repo.zabbix.com/zabbix"
    
    # First try curl
    if command -v curl >/dev/null 2>&1; then
        curl -s "$base_url/" | grep -oP 'href="\K[0-9]+\.[0-9]+(?=/")' | sort -Vr
    # Then try wget
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$base_url/" | grep -oP 'href="\K[0-9]+\.[0-9]+(?=/")' | sort -Vr
    else
        # If neither is available, install curl
        log_message "Installing curl..."
        apt-get update && apt-get install -y curl
        if [ $? -eq 0 ]; then
            curl -s "$base_url/" | grep -oP 'href="\K[0-9]+\.[0-9]+(?=/")' | sort -Vr
        else
            log_message "ERROR: Failed to install curl"
            # Fallback to known versions
            echo "7.0 6.0 5.0 4.0"
        fi
    fi
}

# Function to validate Zabbix version
validate_version() {
    local version="$1"
    local available_versions=($(get_available_versions))
    
    # Check if version exists in repository
    for v in "${available_versions[@]}"; do
        if [ "$version" == "$v" ]; then
            return 0
        fi
    done
    
    log_message "ERROR: Version $version is not available in the repository"
    log_message "Available versions are: ${available_versions[*]}"
    return 1
}

# Function to get version-specific requirements
get_version_requirements() {
    local version="$1"
    local major_version=$(echo "$version" | cut -d. -f1)
    
    # Define requirements based on major version
    case "$major_version" in
        "7"|"8")
            echo "mariadb-server>=10.5"
            ;;
        "6")
            echo "mariadb-server>=10.3"
            ;;
        "5"|"4")
            echo "mariadb-server>=10.1"
            ;;
        *)
            # For future versions, assume latest requirements
            echo "mariadb-server>=10.5"
            ;;
    esac
}

# Function to get repository URL
get_repository_url() {
    local version="$1"
    local os_version=$(lsb_release -cs)
    local arch=$(dpkg --print-architecture)
    local base_url="https://repo.zabbix.com/zabbix"
    
    # Get the latest patch version for the given major.minor version
    local latest_patch
    if command -v curl >/dev/null 2>&1; then
        latest_patch=$(curl -s "${base_url}/${version}/debian/pool/main/z/zabbix/" | 
            grep -oP "zabbix-proxy-mysql_${version}\.[0-9]+-[0-9]+\+debian[0-9]+_${arch}\.deb" | 
            sort -V | tail -n1)
    elif command -v wget >/dev/null 2>&1; then
        latest_patch=$(wget -qO- "${base_url}/${version}/debian/pool/main/z/zabbix/" | 
            grep -oP "zabbix-proxy-mysql_${version}\.[0-9]+-[0-9]+\+debian[0-9]+_${arch}\.deb" | 
            sort -V | tail -n1)
    else
        # If neither is available, install curl
        log_message "Installing curl..."
        apt-get update && apt-get install -y curl
        if [ $? -eq 0 ]; then
            latest_patch=$(curl -s "${base_url}/${version}/debian/pool/main/z/zabbix/" | 
                grep -oP "zabbix-proxy-mysql_${version}\.[0-9]+-[0-9]+\+debian[0-9]+_${arch}\.deb" | 
                sort -V | tail -n1)
        else
            log_message "ERROR: Failed to install curl"
            return 1
        fi
    fi
    
    if [ -z "$latest_patch" ]; then
        log_message "ERROR: Could not find package for Zabbix $version on $os_version"
        return 1
    fi
    
    # Construct the full URL
    echo "${base_url}/${version}/debian/pool/main/z/zabbix/${latest_patch}"
}

# Function to validate repository URL
validate_repository_url() {
    local version="$1"
    local os_version="$2"
    local url=$(get_repository_url "$version")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    log_message "Checking repository URL: $url"
    if wget --spider "$url" 2>/dev/null; then
        echo "$url"
        return 0
    fi
    
    log_message "ERROR: Could not find valid repository URL for Zabbix $version on $os_version"
    return 1
}

# Function to check version compatibility
check_version_compatibility() {
    local version="$1"
    local major_version=$(echo "$version" | cut -d. -f1)
    local os_version=$(lsb_release -cs)
    
    # Check if the version is too old (e.g., older than 4.0)
    if [ "$major_version" -lt 4 ]; then
        log_message "ERROR: Version $version is too old and not supported"
        return 1
    fi
    
    # Check if the version is too new (e.g., more than 2 major versions ahead)
    local current_year=$(date +%Y)
    local expected_max_version=$((current_year - 2010))  # Assuming Zabbix started around 2010
    
    if [ "$major_version" -gt "$expected_max_version" ]; then
        log_message "WARNING: Version $version seems to be from the future"
        read -p "Do you want to continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Validate repository URL before proceeding
    if ! validate_repository_url "$version" "$os_version"; then
        log_message "ERROR: No valid repository found for Zabbix $version on $os_version"
        return 1
    fi
    
    return 0
}

# Function to check system requirements
check_system_requirements() {
    local version="$1"
    local requirements=$(get_version_requirements "$version")
    
    echo "DEBUG: Starting system requirements check for Zabbix $version"
    echo "DEBUG: Required packages: $requirements"
    
    # Check OS version
    if ! command -v lsb_release >/dev/null 2>&1; then
        echo "DEBUG: lsb_release command not found"
        log_message "ERROR: lsb_release command not found"
        return 1
    fi
    
    local os_version=$(lsb_release -cs)
    echo "DEBUG: OS version: $os_version"
    if [ -z "$os_version" ]; then
        echo "DEBUG: Could not determine OS version"
        log_message "ERROR: Could not determine OS version"
        return 1
    fi
    
    # Check memory (improved detection)
    echo "DEBUG: Checking system memory..."
    local total_mem=0
    if [ -f /proc/meminfo ]; then
        total_mem=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
        echo "DEBUG: Memory from /proc/meminfo: $total_mem MB"
    elif command -v free >/dev/null 2>&1; then
        total_mem=$(free -m | awk '/^Mem:/{print $2}')
        echo "DEBUG: Memory from free command: $total_mem MB"
    fi

    if [ "$total_mem" -eq 0 ]; then
        echo "DEBUG: Could not determine total memory"
        log_message "WARNING: Could not determine total memory"
        if ! get_confirmation "Continue anyway?"; then
            return 1
        fi
    elif [ "$total_mem" -lt 1024 ]; then
        echo "DEBUG: Low memory detected: $total_mem MB"
        log_message "WARNING: System has less than 1GB of RAM ($total_mem MB)"
        if ! get_confirmation "Continue anyway?"; then
            return 1
        fi
    fi
    
    # Check disk space
    echo "DEBUG: Checking disk space..."
    local free_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    echo "DEBUG: Free disk space: $free_space GB"
    if [ "$free_space" -lt 5 ]; then
        echo "DEBUG: Low disk space detected: $free_space GB"
        log_message "WARNING: Less than 5GB of free disk space ($free_space GB)"
        if ! get_confirmation "Continue anyway?"; then
            return 1
        fi
    fi
    
    # Check required packages
    echo "DEBUG: Checking required packages..."
    for req in $requirements; do
        local pkg=$(echo "$req" | cut -d'>' -f1)
        local min_ver=$(echo "$req" | cut -d'>' -f2)
        echo "DEBUG: Checking package: $pkg (min version: $min_ver)"
        
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            echo "DEBUG: Package $pkg will be installed during the installation process"
            log_message "Package $pkg will be installed during the installation process"
        fi
    done
    
    echo "DEBUG: System requirements check completed successfully"
    return 0
}

# Function to get user confirmation
get_confirmation() {
    local prompt="$1"
    read -p "$prompt (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate IP address
validate_ip() {
    local ip="$1"
    local type="$2"
    
    # Clean up the input
    ip=$(echo "$ip" | tr -d '\r' | tr -d '\n' | tr -d '"' | tr -d "'" | tr -d ' ')
    
    # Basic format check
    if ! [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    
    # Check each octet
    local IFS='.'
    local -a octets=($ip)
    for octet in "${octets[@]}"; do
        if [[ $octet -lt 0 || $octet -gt 255 ]]; then
            return 1
        fi
    done
    
    return 0
}

# Function to validate netmask
validate_netmask() {
    local netmask="$1"
    
    # Check if netmask is in valid format
    if ! [[ $netmask =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "Invalid netmask format"
        return 1
    fi
    
    # Split netmask into octets
    local IFS='.'
    local -a octets=($netmask)
    
    # Check each octet
    for octet in "${octets[@]}"; do
        if [[ $octet -lt 0 || $octet -gt 255 ]]; then
            echo "Invalid netmask: octet must be between 0 and 255"
            return 1
        fi
    done
    
    # Check if it's a valid subnet mask
    local valid_masks=("0" "128" "192" "224" "240" "248" "252" "254" "255")
    local prev_octet=255
    
    for octet in "${octets[@]}"; do
        # Check if octet is a valid mask value
        local is_valid=0
        for mask in "${valid_masks[@]}"; do
            if [[ $octet -eq $mask ]]; then
                is_valid=1
                break
            fi
        done
        
        if [[ $is_valid -eq 0 ]]; then
            echo "Invalid netmask: $octet is not a valid mask value"
            return 1
        fi
        
        # Check if octets are in descending order
        if [[ $octet -gt $prev_octet ]]; then
            echo "Invalid netmask: octets must be in descending order"
            return 1
        fi
        prev_octet=$octet
    done
    
    return 0
}

# Function to validate hostname
validate_hostname() {
    local hostname="$1"
    
    # Check if hostname is empty
    if [ -z "$hostname" ]; then
        echo "Hostname cannot be empty"
        return 1
    fi
    
    # Check if hostname contains only valid characters
    if ! [[ $hostname =~ ^[a-zA-Z0-9.-]+$ ]]; then
        echo "Hostname can only contain letters, numbers, dots, and hyphens"
        return 1
    fi
    
    # Check if hostname starts or ends with a dot or hyphen
    if [[ $hostname =~ ^[.-] ]] || [[ $hostname =~ [.-]$ ]]; then
        echo "Hostname cannot start or end with a dot or hyphen"
        return 1
    fi
    
    return 0
}

# Function to validate Zabbix server
validate_zabbix_server() {
    local server="$1"
    
    # Check if server is empty
    if [ -z "$server" ]; then
        echo "Zabbix server cannot be empty"
        return 1
    fi
    
    # Check if server is a valid hostname or IP address
    if ! [[ $server =~ ^[a-zA-Z0-9.-]+$ ]]; then
        echo "Invalid Zabbix server format"
        return 1
    fi
    
    return 0
}

# Function to validate database connection
validate_database() {
    local host="$1"
    local user="$2"
    local password="$3"
    local database="$4"
    
    # Try to connect to the database
    if ! mysql -h"$host" -u"$user" -p"$password" -e "USE $database;" 2>/dev/null; then
        echo "Cannot connect to database $database on $host as user $user"
        return 1
    fi
    
    return 0
}

# Function to convert netmask to CIDR
netmask_to_cidr() {
    local netmask="$1"
    local cidr=0
    
    # Split netmask into octets
    local IFS='.'
    local -a octets=($netmask)
    
    # Count the 1s in each octet
    for octet in "${octets[@]}"; do
        case $octet in
            255) cidr=$((cidr + 8));;
            254) cidr=$((cidr + 7));;
            252) cidr=$((cidr + 6));;
            248) cidr=$((cidr + 5));;
            240) cidr=$((cidr + 4));;
            224) cidr=$((cidr + 3));;
            192) cidr=$((cidr + 2));;
            128) cidr=$((cidr + 1));;
            0) ;;
            *) echo "Invalid netmask value: $octet"; return 1;;
        esac
    done
    
    echo "$cidr"
    return 0
}

# Create log file
touch /var/log/zabbix_proxy_install.log
chmod 644 /var/log/zabbix_proxy_install.log

log_message "Starting Zabbix Proxy installation..."

# Get Zabbix version
echo "Please select the Zabbix version to install:"
echo "Checking available versions..."
AVAILABLE_VERSIONS=($(get_available_versions))
echo "Available versions: ${AVAILABLE_VERSIONS[*]}"

while true; do
    read -p "Enter Zabbix version: " ZABBIX_VERSION
    if validate_version "$ZABBIX_VERSION"; then
        break
    fi
done

# Check system requirements
if ! check_system_requirements "$ZABBIX_VERSION"; then
    log_message "ERROR: System does not meet requirements for Zabbix $ZABBIX_VERSION"
    exit 1
fi

echo "============================================="
echo "System requirements check completed successfully"
echo "Proceeding with network configuration..."
echo "============================================="

# Ask if network configuration is needed
echo -e "\nDo you want to configure the network? (y/n)"
read -p "Your choice: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Configuring network..."
    show_interface

    # Get network configuration with validation
    echo -e "\nPlease provide the following network configuration:"
    while true; do
        echo -e "\nAvailable interfaces:"
        ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo'
        read -r -p "Enter network interface name: " INTERFACE
        
        # Direct check if interface exists
        if [ -n "$INTERFACE" ] && ip link show "$INTERFACE" >/dev/null 2>&1; then
            echo "Interface $INTERFACE is valid"
            break
        else
            echo "Invalid interface. Please choose from the list above."
            show_interface
        fi
    done

    echo -e "\nPlease enter the network configuration for $INTERFACE:"
    
    # Get IP address
    while true; do
        read -r -p "IP Address (e.g., 172.16.2.105): " IP_ADDRESS
        if [[ $IP_ADDRESS =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            break
        else
            echo "Invalid IP format. Please try again."
        fi
    done

    # Get netmask
    while true; do
        read -r -p "Netmask (default: 255.255.255.0): " NETMASK
        NETMASK=${NETMASK:-"255.255.255.0"}
        if [[ $NETMASK =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            break
        else
            echo "Invalid netmask format. Please try again."
        fi
    done

    # Get gateway
    while true; do
        read -r -p "Gateway (e.g., 172.16.2.1): " GATEWAY
        if [[ $GATEWAY =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            break
        else
            echo "Invalid gateway format. Please try again."
        fi
    done

    # Get DNS
    while true; do
        read -r -p "DNS Server (default: 8.8.8.8): " DNS
        DNS=${DNS:-"8.8.8.8"}
        if [[ $DNS =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            break
        else
            echo "Invalid DNS format. Please try again."
        fi
    done

    # Get MTU
    MTU=$(get_input "MTU" "1500" "^[0-9]{1,4}$")

    # Show configuration summary
    echo -e "\n\033[1;32mNetwork Configuration Summary:\033[0m"
    echo -e "Interface: \033[1;33m$INTERFACE\033[0m"
    echo -e "IP Address: \033[1;33m$IP_ADDRESS\033[0m"
    echo -e "Netmask: \033[1;33m$NETMASK\033[0m"
    echo -e "Gateway: \033[1;33m$GATEWAY\033[0m"
    echo -e "DNS Server: \033[1;33m$DNS\033[0m"
    echo -e "MTU: \033[1;33m$MTU\033[0m"
    
    echo -e "\n\033[1;33mDo you want to apply this configuration? (y/n)\033[0m"
    read -p "> " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "\033[1;31mConfiguration cancelled.\033[0m"
        exit 1
    fi

    # Configure network interface
    log_message "Configuring network interface..."

    # Calculate CIDR from netmask
    CIDR=$(netmask_to_cidr "$NETMASK")
    if [ $? -ne 0 ]; then
        log_message "ERROR: Invalid netmask"
        exit 1
    fi

    # Check current network configuration method
    if [ -d "/etc/netplan" ] && command -v netplan >/dev/null 2>&1; then
        log_message "Using netplan for network configuration..."
        
        # Backup existing netplan configurations
        mkdir -p /etc/netplan/backup
        cp /etc/netplan/*.yaml /etc/netplan/backup/ 2>/dev/null || true
        
        # Create netplan configuration
        cat > /etc/netplan/01-netcfg.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: no
      addresses:
        - $IP_ADDRESS/$CIDR
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [$DNS]
      mtu: $MTU
EOF

        # Apply netplan configuration safely
        log_message "Applying network configuration..."
        if ! netplan try --timeout 60; then
            log_message "ERROR: Netplan configuration failed, rolling back..."
            cp /etc/netplan/backup/*.yaml /etc/netplan/ 2>/dev/null || true
            exit 1
        fi
        netplan apply

    else
        log_message "Using traditional networking configuration..."
        
        # Backup existing configuration
        cp /etc/network/interfaces /etc/network/interfaces.bak
        
        # Create new interfaces file
        cat > /etc/network/interfaces << EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto $INTERFACE
iface $INTERFACE inet static
    address $IP_ADDRESS
    netmask $NETMASK
    gateway $GATEWAY
    dns-nameservers $DNS
    mtu $MTU
EOF

        # Remove any existing interface configuration from interfaces.d
        rm -f /etc/network/interfaces.d/$INTERFACE

        # Configure network interface using ip commands
        log_message "Configuring network interface using ip commands..."
        ip addr flush dev $INTERFACE
        ip addr add $IP_ADDRESS/$CIDR dev $INTERFACE
        ip link set dev $INTERFACE mtu $MTU
        ip link set dev $INTERFACE up
        
        # Remove existing default route if exists
        ip route del default 2>/dev/null || true
        # Add new default route
        ip route add default via $GATEWAY

        # Update resolv.conf
        cp /etc/resolv.conf /etc/resolv.conf.bak
        cat > /etc/resolv.conf << EOF
nameserver $DNS
EOF
    fi

    # Wait for network to stabilize
    sleep 5

    # Verify network configuration
    log_message "Verifying network configuration..."
    if ! ip addr show $INTERFACE | grep -q "inet $IP_ADDRESS"; then
        log_message "ERROR: Network configuration verification failed"
        # Try to restore backup configuration
        if [ -f /etc/network/interfaces.bak ]; then
            cp /etc/network/interfaces.bak /etc/network/interfaces
        fi
        if [ -f /etc/resolv.conf.bak ]; then
            cp /etc/resolv.conf.bak /etc/resolv.conf
        fi
        exit 1
    fi

    # Test network connectivity
    log_message "Testing network connectivity..."
    if ! ping -c 1 -W 5 $GATEWAY >/dev/null 2>&1; then
        log_message "WARNING: Cannot ping gateway $GATEWAY"
        if ! get_confirmation "Continue anyway?"; then
            exit 1
        fi
    fi
else
    log_message "Skipping network configuration"
fi

# Ask if hostname configuration is needed
read -p "Do you want to configure the hostname? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    while true; do
        HOSTNAME=$(get_input "Enter system hostname" "zabbix-proxy" "^[a-zA-Z0-9.-]+$")
        if validate_hostname "$HOSTNAME"; then
            break
        fi
    done

    # Configure hostname
    configure_hostname "$HOSTNAME"
else
    log_message "Skipping hostname configuration"
fi

# Get Zabbix configuration with validation
echo "============================================="
echo "Zabbix Proxy Configuration"
echo "============================================="

# Get Zabbix server IP or hostname
while true; do
    read -r -p "Enter Zabbix Server IP or hostname: " ZABBIX_SERVER
    if [ -n "$ZABBIX_SERVER" ]; then
        break
    else
        echo "Zabbix server cannot be empty. Please try again."
    fi
done

# Get proxy configuration
read -r -p "Enter Proxy hostname (default: zabbix-proxy): " PROXY_HOSTNAME
PROXY_HOSTNAME=${PROXY_HOSTNAME:-"zabbix-proxy"}

read -r -p "Enter database name (default: zabbix_proxy): " DB_NAME
DB_NAME=${DB_NAME:-"zabbix_proxy"}

read -r -p "Enter database password (default: zabbix): " DB_PASSWORD
DB_PASSWORD=${DB_PASSWORD:-"zabbix"}

echo "============================================="
echo "Starting installation with the following configuration:"
echo "Zabbix Server: $ZABBIX_SERVER"
echo "Proxy Hostname: $PROXY_HOSTNAME"
echo "Database Name: $DB_NAME"
echo "============================================="

# Add Zabbix repository first
log_message "Adding Zabbix $ZABBIX_VERSION repository..."
wget https://repo.zabbix.com/zabbix/$ZABBIX_VERSION/debian/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VERSION}-1+debian12_all.deb
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to download repository package"
    exit 1
fi

dpkg -i zabbix-release_${ZABBIX_VERSION}-1+debian12_all.deb
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to install repository package"
    rm -f zabbix-release_${ZABBIX_VERSION}-1+debian12_all.deb
    exit 1
fi
rm -f zabbix-release_${ZABBIX_VERSION}-1+debian12_all.deb

# Update package lists
log_message "Updating package lists..."
apt-get update
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to update package lists"
    exit 1
fi

# Fix any broken packages first
log_message "Fixing broken packages..."
apt-get --fix-broken install -y
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to fix broken packages"
    exit 1
fi

# Install dependencies
log_message "Installing dependencies..."
apt-get install -y libcurl4 libevent-core-2.1-7 libevent-extra-2.1-7 libevent-pthreads-2.1-7 \
    libodbc2 libopenipmi0 libsnmp40 libssh-4 fping
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to install dependencies"
    exit 1
fi

# Install MariaDB
log_message "Installing MariaDB..."
apt-get install -y mariadb-server mariadb-client
check_status "MariaDB installation"

# Create MySQL user and database
log_message "Creating MySQL user and database..."
mysql -uroot << EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
EOF
check_status "MySQL user and database creation"

# Install Zabbix Proxy
log_message "Installing Zabbix Proxy $ZABBIX_VERSION..."
apt-get install -y zabbix-proxy-mysql zabbix-sql-scripts
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to install Zabbix Proxy packages"
    log_message "Attempting to install packages individually..."
    
    # Try installing packages one by one
    for pkg in zabbix-proxy-mysql zabbix-sql-scripts; do
        if ! apt-get install -y "$pkg"; then
            log_message "ERROR: Failed to install $pkg"
            exit 1
        fi
    done
fi
check_status "Zabbix Proxy installation"

# Verify SQL scripts installation
log_message "Verifying SQL scripts installation..."
if [ ! -d "/usr/share/zabbix-sql-scripts" ]; then
    log_message "ERROR: zabbix-sql-scripts directory not found"
    log_message "Attempting to reinstall zabbix-sql-scripts..."
    apt-get install --reinstall -y zabbix-sql-scripts
    check_status "Reinstalling zabbix-sql-scripts"
fi

# Import schema
log_message "Checking database schema..."
if mysql -uzabbix -p$DB_PASSWORD $DB_NAME -e "SHOW TABLES;" | grep -q 'proxy_history'; then
    log_message "Database schema already exists, skipping import"
    check_status "Database schema check"
else
    log_message "Importing database schema..."
    # Try different possible locations for the SQL schema file
    SQL_FILE=""
    for path in "/usr/share/zabbix-sql-scripts/mysql/proxy.sql" \
                "/usr/share/doc/zabbix-proxy-mysql/create.sql.gz" \
                "/usr/share/zabbix-proxy-mysql/create.sql.gz"; do
        if [ -f "$path" ] || [ -f "${path%.gz}" ]; then
            SQL_FILE="$path"
            break
        fi
    done

    if [ -n "$SQL_FILE" ]; then
        if [[ "$SQL_FILE" == *.gz ]]; then
            gunzip -c "$SQL_FILE" | mysql -uzabbix -p$DB_PASSWORD $DB_NAME
        else
            mysql -uzabbix -p$DB_PASSWORD $DB_NAME < "$SQL_FILE"
        fi
        check_status "Schema import from $SQL_FILE"
    else
        log_message "ERROR: Could not find SQL schema file"
        log_message "Please check if zabbix-sql-scripts package is installed correctly"
        exit 1
    fi
fi

# Create required directories
log_message "Creating required directories..."
mkdir -p /run/zabbix
mkdir -p /var/log/zabbix
mkdir -p /var/lib/zabbix
mkdir -p /var/log/snmptrap
chown zabbix:zabbix /run/zabbix /var/log/zabbix /var/lib/zabbix /var/log/snmptrap
chmod 755 /run/zabbix /var/log/zabbix /var/lib/zabbix /var/log/snmptrap
check_status "Directory creation"

# Set zabbix user home directory
log_message "Setting zabbix user home directory..."
usermod -d /var/lib/zabbix zabbix
check_status "Setting zabbix user home directory"

# Update Zabbix Proxy configuration
log_message "Updating Zabbix Proxy configuration..."
cat > /etc/zabbix/zabbix_proxy.conf << EOF
Server=$ZABBIX_SERVER
Hostname=$PROXY_HOSTNAME
LogType=file
LogFile=/var/log/zabbix/zabbix_proxy.log
LogFileSize=0
DebugLevel=4
DBHost=localhost
DBName=$DB_NAME
DBUser=zabbix
DBPassword=$DB_PASSWORD
ProxyMode=0
ProxyLocalBuffer=0
ProxyOfflineBuffer=1
ProxyConfigFrequency=3600
DataSenderFrequency=1
StartPollers=5
StartPollersUnreachable=1
StartPingers=1
StartDiscoverers=1
StartHTTPPollers=1
StartPreprocessors=3
StartDBSyncers=4
CacheSize=8M
HistoryCacheSize=16M
HistoryIndexCacheSize=4M
Timeout=4
PidFile=/run/zabbix/zabbix_proxy.pid
SocketDir=/run/zabbix
SNMPTrapperFile=/var/log/snmptrap/snmptrap.log
LogSlowQueries=3000
StatsAllowedIP=127.0.0.1
EOF
chown zabbix:zabbix /etc/zabbix/zabbix_proxy.conf
chmod 644 /etc/zabbix/zabbix_proxy.conf
check_status "Configuration file creation"

# Start and enable service
log_message "Starting Zabbix Proxy service..."
systemctl stop zabbix-proxy
sleep 2
systemctl start zabbix-proxy
systemctl enable zabbix-proxy
check_status "Service startup"

# Wait for service to start
sleep 5

# Check service status
log_message "Checking service status..."
if ! systemctl is-active --quiet zabbix-proxy; then
    log_message "ERROR: Zabbix Proxy service failed to start"
    journalctl -u zabbix-proxy --no-pager -n 50
    exit 1
fi

# Display logs
log_message "Recent logs from journalctl:"
journalctl -u zabbix-proxy --no-pager -n 50

# Check database connection
log_message "Testing database connection..."
mysql -uzabbix -p$DB_PASSWORD -e "SELECT COUNT(*) FROM $DB_NAME.proxy_history;" 2>&1
check_status "Database connection test"

# Final status check
if systemctl is-active --quiet zabbix-proxy; then
    log_message "Zabbix Proxy installation completed successfully"
else
    log_message "Zabbix Proxy installation failed - check logs for details"
    exit 1
fi

# Display important file permissions
log_message "File permissions check:"
ls -la /run/zabbix /var/log/zabbix /etc/zabbix/zabbix_proxy.conf

# Display listening ports
log_message "Installing net-tools for port checking..."
apt-get install -y net-tools
check_status "net-tools installation"

log_message "Listening ports:"
netstat -tulpn | grep zabbix

# End of script 
