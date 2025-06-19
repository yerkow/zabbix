# Zabbix Proxy Installation Memory

## Installation Process Summary

### System Requirements
- Debian Bookworm OS
- Minimum 1GB RAM (tested with 1966MB)
- Minimum 5GB disk space (tested with 28GB free)
- MariaDB >= 10.5

### Installation Steps
1. System Time Synchronization
   - Uses ntpdate with pool.ntp.org
   - Verifies time synchronization success

2. Repository Configuration
   - Validates Zabbix repository (https://repo.zabbix.com/zabbix/)
   - Updates package lists
   - Available Zabbix versions: 7.4, 7.2, 7.0, 6.5, 6.4, 6.3, 6.2, 6.1, 6.0, 5.5, 5.4, 5.3, 5.2, 5.1, 5.0, 4.5, 4.4, 4.2, 4.0, 3.4, 3.2, 3.0, 2.4, 2.2, 2.0, 1.8

3. Dependencies Installation
   - Core libraries: libcurl4, libevent, libodbc2, libopenipmi0, libsnmp40, libssh-4, fping
   - MariaDB server and client
   - Zabbix Proxy packages: zabbix-proxy-mysql, zabbix-sql-scripts

4. Database Setup
   - Creates MySQL user 'zabbix' with password 'zabbix'
   - Creates database 'zabbix_proxy'
   - Imports schema from /usr/share/zabbix-sql-scripts/mysql/proxy.sql

5. Directory Structure
   - /run/zabbix - Runtime files
   - /var/log/zabbix - Log files
   - /var/lib/zabbix - Data files
   - /var/log/snmptrap - SNMP trap logs
   - All directories owned by zabbix:zabbix with 755 permissions

6. Service Configuration
   - Configuration file: /etc/zabbix/zabbix_proxy.conf
   - Service name: zabbix-proxy
   - Default port: 10051 (TCP)
   - Runs as user 'zabbix'

### Configuration Parameters
- Server: 172.16.2.104
- Hostname: zabbix-proxy
- Database: zabbix_proxy
- Database User: zabbix
- Database Password: zabbix

### Verification Steps
1. Service Status
   - Check systemctl status zabbix-proxy
   - Verify service is active and running

2. Port Verification
   - netstat -tulpn | grep zabbix
   - Should show port 10051 listening

3. Database Connection
   - Test MySQL connection with zabbix user
   - Verify proxy_history table exists

### Troubleshooting
1. Check logs:
   - /var/log/zabbix/zabbix_proxy.log
   - journalctl -u zabbix-proxy

2. Common issues:
   - Time synchronization problems
   - Database connection failures
   - Permission issues in /run/zabbix
   - Port conflicts on 10051

### Maintenance
1. Backup:
   - Database: mysqldump -uzabbix -pzabbix zabbix_proxy
   - Configuration: /etc/zabbix/zabbix_proxy.conf

2. Updates:
   - apt-get update
   - apt-get upgrade zabbix-proxy-mysql

3. Restart procedure:
   - systemctl stop zabbix-proxy
   - systemctl start zabbix-proxy
   - systemctl status zabbix-proxy 