# n8n Updater

Automated script to update n8n installations on DigitalOcean Droplets with automatic backups. Designed for server-side execution and cronjob automation.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

## Features

- ✅ **Automatic backups** - Backs up workflows, volumes, configuration, and databases before updating
- ✅ **Server-side execution** - Runs directly on the server (no SSH required)
- ✅ **Cronjob ready** - Fully non-interactive, perfect for automated updates
- ✅ **Auto-detection** - Automatically finds n8n installation directory
- ✅ **Comprehensive logging** - All operations logged to `/var/log/n8nupdater.log`
- ✅ **Error handling** - Robust error checking with proper exit codes

## Quick Install

Install from GitHub with a single command:

```bash
sudo bash -c 'curl -fsSL https://raw.githubusercontent.com/drhdev/n8nupdater/main/n8nupdater.sh -o /usr/local/bin/n8nupdater && chmod +x /usr/local/bin/n8nupdater'
```

**After installation, verify it works:**
```bash
n8nupdater --help
```

## Usage

### Basic Usage

```bash
n8nupdater                    # Update with default directory (/opt/n8n-docker-caddy)
```

### Options

```bash
n8nupdater --skip-backup                     # Skip backup step (not recommended)
n8nupdater --install-dir=/custom/path       # Custom installation directory
n8nupdater --backup-dir=/custom/backup      # Custom backup directory
n8nupdater --log-file=/custom/log           # Custom log file location
n8nupdater --help                           # Show help message
```

### Environment Variables

You can also use environment variables:

```bash
export INSTALL_DIR=/custom/path
export BACKUP_DIR=/custom/backup
export LOG_FILE=/custom/log
export SKIP_BACKUP=true
n8nupdater
```

## Cronjob Setup

The script is designed to run automatically via cron. Example cronjob entries:

### Daily Update at 2 AM

```bash
0 2 * * * /usr/local/bin/n8nupdater >> /var/log/n8nupdater.log 2>&1
```

### Weekly Update (Sunday at 3 AM)

```bash
0 3 * * 0 /usr/local/bin/n8nupdater >> /var/log/n8nupdater.log 2>&1
```

### Monthly Update (1st of month at 4 AM)

```bash
0 4 1 * * /usr/local/bin/n8nupdater >> /var/log/n8nupdater.log 2>&1
```

To add a cronjob, run:

```bash
sudo crontab -e
```

Then add one of the lines above.

## Default Locations

The script uses these default locations (optimized for common n8n installations):

- **Installation Directory**: `/opt/n8n-docker-caddy`
- **Backup Directory**: `/root/n8n-backups`
- **Log File**: `/var/log/n8nupdater.log`

If the default installation directory doesn't exist, the script will automatically search for n8n installations in:
- `/opt/n8n-docker-caddy`
- `/opt/n8n`
- `/opt/docker/n8n`
- `/home/n8n`
- Any directory under `/opt` containing `docker-compose.yml` or `docker-compose.yaml`

## Backup Details

The script automatically creates backups before updating:

- **Workflows** - Exported via n8n API (if available and API key is configured)
- **Docker Volumes** - All mounted volumes are backed up as compressed archives
- **Configuration** - docker-compose.yml, docker-compose.yaml, and .env files
- **Databases** - SQLite database files (if present)

Backups are stored in `/root/n8n-backups/` by default, with timestamped directories:

```
/root/n8n-backups/n8n-backup-20240101_120000/
├── workflows.json
├── volume-n8n_data.tar.gz
├── config.tar.gz
├── database-n8n.db.tar.gz
└── backup-info.txt
```

Each backup includes a `backup-info.txt` file with metadata about the backup.

## Update Process

The script performs the following steps:

1. **Auto-detect** - Finds n8n installation directory if default doesn't exist
2. **Backup** - Creates a complete backup of n8n data (unless `--skip-backup` is used)
3. **Pull Images** - Downloads latest Docker images
4. **Stop Containers** - Gracefully stops running containers
5. **Start Containers** - Starts containers with new images
6. **Logging** - All operations are logged with timestamps

## Requirements

- **Root access** - **REQUIRED**: Script must be run as root user to ensure proper permissions for Docker operations, file system access, and log file creation. Running without root will cause the script to exit with an error.
- **Docker and Docker Compose** - Installed on the server (Docker Compose v2 recommended)
- **n8n installed via Docker Compose** - Standard n8n installation
- **Sufficient disk space** - For backups (check `/root/n8n-backups/` periodically)
- **Network connectivity** - Required to pull Docker images from registry

## Logging

All operations are logged to `/var/log/n8nupdater.log` by default. Log entries include:

- Timestamp for each operation
- INFO messages for normal operations
- WARNING messages for non-critical issues
- ERROR messages for failures

Example log output:

```
[2024-01-01 02:00:00] INFO: Starting n8n update process...
[2024-01-01 02:00:00] INFO: Installation directory: /opt/n8n-docker-caddy
[2024-01-01 02:00:01] INFO: Creating backup of n8n data...
[2024-01-01 02:00:05] INFO: Backup completed: /root/n8n-backups/n8n-backup-20240101_020000 (Size: 150M)
[2024-01-01 02:00:06] INFO: Step 1: Pulling latest Docker images...
[2024-01-01 02:01:30] INFO: Step 2: Stopping and removing current containers...
[2024-01-01 02:01:32] INFO: Step 3: Starting containers with new images...
[2024-01-01 02:01:35] INFO: Update process completed successfully!
```

## Troubleshooting

### Installation directory not found

The script will automatically search for n8n installations. If it can't find one, specify it manually:

```bash
n8nupdater --install-dir=/path/to/n8n
```

Or set the environment variable:

```bash
export INSTALL_DIR=/path/to/n8n
n8nupdater
```

### Backup fails

If backup fails, the script will log a warning but continue with the update. Check the log file for details:

```bash
tail -f /var/log/n8nupdater.log
```

### Check recent backups

List recent backups:

```bash
ls -lh /root/n8n-backups/
```

### View backup contents

```bash
tar -tzf /root/n8n-backups/n8n-backup-YYYYMMDD_HHMMSS/workflows.json
```

### Manual verification

After an update, verify the n8n version in the web UI (check the footer or About section).

## Safety Notes

⚠️ **Important Safety Considerations:**

- The script creates automatic backups, but it's recommended to also:
  - Export workflows manually from the n8n UI periodically
  - Create DigitalOcean snapshots before major updates
  - Keep multiple backup copies
  - Test backups by restoring them in a test environment

- **Disk Space**: Monitor disk usage in `/root/n8n-backups/`. Consider cleaning old backups periodically:

```bash
# Remove backups older than 30 days
find /root/n8n-backups/ -type d -name "n8n-backup-*" -mtime +30 -exec rm -rf {} \;
```

- **Cronjob Timing**: Schedule updates during low-traffic periods to minimize disruption.

## Exit Codes

The script uses standard exit codes for cronjob monitoring:

- `0` - Success
- `1` - Error (check log file for details)

You can monitor the script in cron with:

```bash
0 2 * * * /usr/local/bin/n8nupdater >> /var/log/n8nupdater.log 2>&1 || echo "n8nupdater failed" | mail -s "n8n Update Failed" admin@example.com
```

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

## Quality Assurance

This script has been thoroughly tested and validated for production use. The following checks and validations are implemented:

### Error Handling & Robustness
- ✅ Strict error handling with `set -o errexit`, `nounset`, and `pipefail`
- ✅ Comprehensive error checking at each critical step
- ✅ Graceful error handling with proper cleanup on failures
- ✅ Signal handling (INT, TERM, EXIT) for clean termination
- ✅ Lock file mechanism to prevent concurrent execution
- ✅ Stale lock file detection and cleanup

### Docker Compatibility
- ✅ Automatic detection of Docker Compose v1 (`docker-compose`) and v2 (`docker compose`)
- ✅ Docker daemon availability check before operations
- ✅ Docker Compose configuration file syntax validation
- ✅ Container health verification after startup
- ✅ Orphan container cleanup support

### Path & File System Validation
- ✅ Absolute path validation for all directories
- ✅ Path normalization (removes trailing slashes)
- ✅ Directory readability checks
- ✅ File existence verification before operations
- ✅ Log file directory creation and writability checks

### Resource Management
- ✅ Disk space checking before backup operations
- ✅ Timeout handling for long-running operations (default: 10 minutes)
- ✅ Network connectivity validation for Docker image pulls
- ✅ Required command availability checks (docker, curl, tar, gzip, timeout)

### Backup Functionality
- ✅ Multiple backup methods (API export + volume backup)
- ✅ Backup validation to ensure files were created
- ✅ Graceful fallback if API backup fails
- ✅ JSON validation (if jq is available)
- ✅ Proper handling of paths with spaces
- ✅ Database file detection and backup

### Security
- ✅ Root user requirement enforcement
- ✅ Proper quoting to prevent shell injection
- ✅ API key handling with timeout protection
- ✅ Path sanitization and validation

### Ubuntu Compatibility (22.04 & 24.04)
- ✅ Compatible with Ubuntu's default bash version (5.x)
- ✅ Works with both systemd and non-systemd environments
- ✅ Handles Ubuntu's `/run` vs `/var/run` directory structure
- ✅ Compatible with snap and apt Docker installations
- ✅ Works with AppArmor security policies
- ✅ Proper handling of Docker socket permissions

### Logging & Monitoring
- ✅ Comprehensive logging with timestamps
- ✅ Log file fallback to stderr if file write fails
- ✅ Proper exit codes for cronjob monitoring (0 = success, 1 = error)
- ✅ Container status verification and reporting

### Production Readiness
- ✅ Fully non-interactive (cronjob-ready)
- ✅ No user prompts or interactive input required
- ✅ Auto-detection of installation directory
- ✅ Environment variable support for configuration
- ✅ Command-line argument parsing
- ✅ Help documentation built-in

## Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/drhdev/n8nupdater/issues).
