# Zabbix Proxy Installation Script

This script automates the installation and configuration of Zabbix Proxy on Debian-based systems.

## Features

- Interactive and non-interactive installation modes
- Support for multiple Zabbix versions (4.0 to 7.4)
- Network configuration (optional)
- Hostname configuration (optional)
- MariaDB database setup
- Automatic repository management
- Comprehensive error handling and logging
- System requirements validation
- Service management and verification

## Prerequisites

- Debian-based system (tested on Debian 12 Bookworm)
- Root access
- Internet connectivity
- Minimum 1GB RAM
- Minimum 5GB free disk space

## Usage

### Interactive Mode

```bash
sudo bash install_zabbix_proxy.sh
```

### Non-interactive Mode

```bash
sudo bash install_zabbix_proxy.sh --non-interactive --zabbix-version 7.0 --zabbix-server 192.168.1.1 --proxy-hostname zabbix-proxy --db-name zabbix_proxy --db-password zabbix --interface ens18
```

### Debug Mode

```bash
sudo bash install_zabbix_proxy.sh --debug
```

## Command Line Options

- `--debug`: Enable debug mode
- `--non-interactive`: Run in non-interactive mode
- `--zabbix-version`: Specify Zabbix version (e.g., 7.0)
- `--zabbix-server`: Specify Zabbix server IP/hostname
- `--proxy-hostname`: Specify proxy hostname
- `--db-name`: Specify database name
- `--db-password`: Specify database password
- `--interface`: Specify network interface

## Installation Process

1. System requirements check
2. Network configuration (optional)
3. Hostname configuration (optional)
4. Repository setup
5. Package installation
6. Database setup
7. Zabbix Proxy configuration
8. Service setup and verification

## Logging

The script creates a log file at `/var/log/zabbix_proxy_install.log` with detailed information about the installation process.

## Error Handling

The script includes comprehensive error handling for:
- Network configuration
- Package installation
- Database operations
- Service management
- File permissions

## Configuration Files

- `/etc/zabbix/zabbix_proxy.conf`: Main configuration file
- `/etc/network/interfaces` or `/etc/netplan/*.yaml`: Network configuration
- `/etc/hosts`: Hostname configuration

## Service Management

The script automatically:
- Starts the Zabbix Proxy service
- Enables it to start on boot
- Verifies the service status
- Tests database connectivity

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
