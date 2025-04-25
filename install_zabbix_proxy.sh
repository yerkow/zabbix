#!/bin/bash

# Default debug mode is off
DEBUG_MODE=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG_MODE=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--debug]"
            exit 1
            ;;
    esac
done

# Enable debug mode if requested
if [ "$DEBUG_MODE" -eq 1 ]; then
    set -x
fi

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/zabbix_proxy_install.log
}

show_interface() {
	ip addr ls
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

# Function to get user input with validation
get_input() {
    local prompt="$1"
    local default="$2"
    local validation="$3"
    local input
    
    while true; do
        if [ -n "$default" ]; then
            read -p "$prompt [$default]: " input
            input=${input:-$default}
        else
            read -p "$prompt: " input
        fi
        
        if [ -n "$validation" ]; then
            if [[ $input =~ $validation ]]; then
                break
            else
                echo "Invalid input. Please try again."
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

# Function to get available Zabbix versions from repository
get_available_versions() {
    local os_version=$(lsb_release -cs)
    local repo_url="https://repo.zabbix.com/zabbix/"
    
    # Try to get available versions from repository
    if command -v curl &> /dev/null; then
        curl -s "$repo_url" | grep -oP 'href="\K[0-9]+\.[0-9]+(?=/")' | sort -Vr
    elif command -v wget &> /dev/null; then
        wget -qO- "$repo_url" | grep -oP 'href="\K[0-9]+\.[0-9]+(?=/")' | sort -Vr
    else
        # Fallback to known versions if we can't check repository
        echo "7.0 6.0 5.0 4.0"
    fi
}

# Function to validate Zabbix version
validate_version() {
    local version="$1"
    local available_versions=($(get_available_versions))
    
    # Basic version format check
    if ! [[ $version =~ ^[0-9]+\.[0-9]+$ ]]; then
        log_message "ERROR: Invalid version format. Please use format X.Y (e.g., 7.0)"
        return 1
    fi
    
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

# Function to get version-specific repository URL
get_repository_url() {
    local version="$1"
    local os_version=$(lsb_release -cs)
    local major_version=$(echo "$version" | cut -d. -f1)
    
    # For versions 7.0 and above, use the new repository structure
    if [ "$major_version" -ge 7 ]; then
        echo "https://repo.zabbix.com/zabbix/$version/debian/pool/main/z/zabbix-release/zabbix-release_${version}-1+debian${os_version}_all.deb"
    else
        # For older versions, use the legacy repository structure
        echo "https://repo.zabbix.com/zabbix/$version/debian/pool/main/z/zabbix-release/zabbix-release_${version}-1+debian${os_version}_all.deb"
    fi
}

# Function to check version compatibility
check_version_compatibility() {
    local version="$1"
    local major_version=$(echo "$version" | cut -d. -f1)
    
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
    
    return 0
}

# Function to check system requirements
check_system_requirements() {
    local version="$1"
    local requirements=$(get_version_requirements "$version")
    
    log_message "Checking system requirements for Zabbix $version..."
    
    # Check OS version
    if ! command -v lsb_release &> /dev/null; then
        apt-get install -y lsb-release
    fi
    
    local os_version=$(lsb_release -cs)
    if [ -z "$os_version" ]; then
        log_message "ERROR: Could not determine OS version"
        return 1
    fi
    
    # Check available memory
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_mem" -lt 1024 ]; then
        log_message "WARNING: System has less than 1GB RAM ($total_mem MB)"
        read -p "Do you want to continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Check disk space
    local free_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$free_space" -lt 5 ]; then
        log_message "WARNING: Less than 5GB free disk space available ($free_space GB)"
        read -p "Do you want to continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Check required packages
    for req in $requirements; do
        local pkg=$(echo "$req" | cut -d'>' -f1)
        local min_ver=$(echo "$req" | cut -d'>' -f2)
        
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            log_message "ERROR: Required package $pkg is not installed"
            return 1
        fi
        
        if [ -n "$min_ver" ]; then
            local installed_ver=$(dpkg-query -W -f='${Version}' "$pkg")
            if ! dpkg --compare-versions "$installed_ver" "ge" "$min_ver"; then
                log_message "ERROR: $pkg version $installed_ver is lower than required $min_ver"
                return 1
            fi
        fi
    done
    
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
    ZABBIX_VERSION=$(get_input "Enter Zabbix version" "${AVAILABLE_VERSIONS[0]}" "^[0-9]+\.[0-9]+$")
    if validate_version "$ZABBIX_VERSION" && check_version_compatibility "$ZABBIX_VERSION"; then
        break
    fi
done

# Check system requirements
if ! check_system_requirements "$ZABBIX_VERSION"; then
    log_message "ERROR: System does not meet requirements for Zabbix $ZABBIX_VERSION"
    exit 1
fi

show_interface

# Function to validate IP address format and reachability
validate_ip() {
    local ip="$1"
    local type="$2"  # "address", "gateway", or "dns"
    
    # Validate IP format
    if ! [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_message "ERROR: Invalid IP address format for $type: $ip"
        return 1
    fi
    
    # Validate each octet
    local IFS='.'
    local -a octets=($ip)
    for octet in "${octets[@]}"; do
        if [[ $octet -lt 0 || $octet -gt 255 ]]; then
            log_message "ERROR: Invalid octet in $type IP: $ip"
            return 1
        fi
    done
    
    # Test reachability for gateway and DNS
    if [[ "$type" == "gateway" || "$type" == "dns" ]]; then
        if ! ping -c 1 -W 1 "$ip" &> /dev/null; then
            log_message "WARNING: $type IP $ip is not reachable"
            read -p "Do you want to continue anyway? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                return 1
            fi
        fi
    fi
    
    return 0
}

# Function to validate network interface
validate_interface() {
    local interface="$1"
    
    if ! ip link show "$interface" &> /dev/null; then
        log_message "ERROR: Network interface $interface does not exist"
        return 1
    fi
    
    return 0
}

# Function to validate hostname uniqueness
validate_hostname() {
    local hostname="$1"
    
    # Check if hostname is already in use on the network
    if ping -c 1 "$hostname" &> /dev/null; then
        log_message "WARNING: Hostname $hostname is already in use on the network"
        read -p "Do you want to continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    return 0
}

# Function to validate database connectivity
validate_database() {
    local host="$1"
    local user="$2"
    local pass="$3"
    local db="$4"
    
    if ! mysql -h "$host" -u "$user" -p"$pass" -e "SELECT 1" &> /dev/null; then
        log_message "ERROR: Cannot connect to database server"
        return 1
    fi
    
    if mysql -h "$host" -u "$user" -p"$pass" -e "SHOW DATABASES LIKE '$db'" | grep -q "$db"; then
        log_message "WARNING: Database $db already exists"
        read -p "Do you want to continue and use the existing database? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    return 0
}

# Function to validate Zabbix server connectivity
validate_zabbix_server() {
    local server="$1"
    
    if ! ping -c 1 "$server" &> /dev/null; then
        log_message "WARNING: Zabbix server $server is not reachable"
        read -p "Do you want to continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Try to connect to Zabbix server port (default 10051)
    if ! nc -z -w 1 "$server" 10051 &> /dev/null; then
        log_message "WARNING: Cannot connect to Zabbix server port 10051"
        read -p "Do you want to continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    return 0
}

# Get network configuration with validation
echo "Please provide the following network configuration:"
while true; do
    INTERFACE=$(get_input "Enter network interface name" "eth0" "^[a-zA-Z0-9]+$")
    if validate_interface "$INTERFACE"; then
        break
    fi
done

while true; do
    IP_ADDRESS=$(get_input "Enter IP address" "" "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$")
    if validate_ip "$IP_ADDRESS" "address"; then
        break
    fi
done

while true; do
    NETMASK=$(get_input "Enter netmask" "255.255.255.0" "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$")
    if validate_ip "$NETMASK" "netmask"; then
        break
    fi
done

while true; do
    GATEWAY=$(get_input "Enter gateway" "" "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$")
    if validate_ip "$GATEWAY" "gateway"; then
        break
    fi
done

while true; do
    DNS=$(get_input "Enter DNS server" "8.8.8.8" "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$")
    if validate_ip "$DNS" "dns"; then
        break
    fi
done

MTU=$(get_input "Enter MTU" "1500" "^[0-9]{1,4}$")

while true; do
    HOSTNAME=$(get_input "Enter system hostname" "zabbix-proxy" "^[a-zA-Z0-9.-]+$")
    if validate_hostname "$HOSTNAME"; then
        break
    fi
done

# Configure network interface
log_message "Configuring network interface..."

# Create a new interfaces file with loopback and the new interface
cat > /etc/network/interfaces << EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

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

# Restart networking
log_message "Restarting network interface..."
systemctl restart networking
check_status "Network configuration"

# Configure hostname
configure_hostname "$HOSTNAME"

# Get Zabbix configuration with validation
echo "Please provide the following information for Zabbix Proxy configuration:"
while true; do
    ZABBIX_SERVER=$(get_input "Enter Zabbix Server IP or hostname" "" "^[a-zA-Z0-9.-]+$")
    if validate_zabbix_server "$ZABBIX_SERVER"; then
        break
    fi
done

PROXY_HOSTNAME=$(get_input "Enter Proxy hostname" "zabbix-proxy" "^[a-zA-Z0-9.-]+$")

while true; do
    DB_PASSWORD=$(get_input "Enter database password" "zabbix" "^[a-zA-Z0-9]+$")
    if validate_database "localhost" "zabbix" "$DB_PASSWORD" "$DB_NAME"; then
        break
    fi
done

DB_NAME=$(get_input "Enter database name" "zabbix_proxy" "^[a-zA-Z0-9_]+$")

# Install MariaDB and Zabbix repository
log_message "Installing MariaDB and Zabbix repository..."
apt-get update
apt-get install -y mariadb-server mariadb-client
check_status "MariaDB installation"

# Ensure MariaDB is running
systemctl start mariadb
systemctl enable mariadb
check_status "MariaDB service activation"

# Add Zabbix repository
log_message "Adding Zabbix $ZABBIX_VERSION repository..."
REPO_URL=$(get_repository_url "$ZABBIX_VERSION")
wget "$REPO_URL" -O /tmp/zabbix-release.deb
dpkg -i /tmp/zabbix-release.deb
rm /tmp/zabbix-release.deb
# Ignore the update error and continue
apt-get update || true
check_status "Zabbix repository setup"

# Install Zabbix Proxy
log_message "Installing Zabbix Proxy $ZABBIX_VERSION..."
apt-get install -y zabbix-proxy-mysql zabbix-sql-scripts
check_status "Zabbix Proxy installation"

# Create database and user
log_message "Creating database and user..."
mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"
mysql -e "CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO 'zabbix'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"
check_status "Database creation"

# Import schema
log_message "Checking database schema..."
if mysql -uzabbix -p$DB_PASSWORD $DB_NAME -e "SHOW TABLES;" | grep -q 'proxy_history'; then
    log_message "Database schema already exists, skipping import"
    check_status "Database schema check"
else
    log_message "Importing database schema..."
    if [ -f /usr/share/zabbix-sql-scripts/mysql/proxy.sql ]; then
        mysql -uzabbix -p$DB_PASSWORD $DB_NAME < /usr/share/zabbix-sql-scripts/mysql/proxy.sql
        check_status "Schema import from proxy.sql"
    else
        log_message "ERROR: Could not find SQL schema file at /usr/share/zabbix-sql-scripts/mysql/proxy.sql"
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
