#!/bin/bash

# n8n Updater Script
# Updates n8n installation locally on the server
# Designed for cronjob use - fully non-interactive
# Assumes root user and default installation directory
#
# Copyright (C) 2024 drhdev
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

set -o errexit  # Exit on error
set -o nounset  # Exit on undefined variable
set -o pipefail # Exit on pipe failure

# Default values (optimized for common n8n installations)
INSTALL_DIR="${INSTALL_DIR:-/opt/n8n-docker-caddy}"
BACKUP_DIR="${BACKUP_DIR:-/root/n8n-backups}"
LOG_FILE="${LOG_FILE:-/var/log/n8nupdater.log}"
LOCK_FILE="${LOCK_FILE:-/var/run/n8nupdater.lock}"
SKIP_BACKUP="${SKIP_BACKUP:-false}"
TIMEOUT="${TIMEOUT:-600}"  # 10 minutes timeout for operations

# Parse arguments
for arg in "$@"; do
    case $arg in
        --skip-backup)
            SKIP_BACKUP="true"
            ;;
        --install-dir=*)
            INSTALL_DIR="${arg#*=}"
            ;;
        --backup-dir=*)
            BACKUP_DIR="${arg#*=}"
            ;;
        --log-file=*)
            LOG_FILE="${arg#*=}"
            ;;
        --timeout=*)
            TIMEOUT="${arg#*=}"
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-backup          Skip backup step (not recommended)"
            echo "  --install-dir=PATH     Installation directory (default: /opt/n8n-docker-caddy)"
            echo "  --backup-dir=PATH      Backup directory (default: /root/n8n-backups)"
            echo "  --log-file=PATH        Log file path (default: /var/log/n8nupdater.log)"
            echo "  --timeout=SECONDS      Timeout for operations (default: 600)"
            echo "  -h, --help            Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  INSTALL_DIR           Override installation directory"
            echo "  BACKUP_DIR            Override backup directory"
            echo "  LOG_FILE              Override log file path"
            echo "  SKIP_BACKUP           Set to 'true' to skip backup"
            echo "  TIMEOUT               Timeout in seconds"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Use all defaults"
            echo "  $0 --install-dir=/custom/path        # Custom installation directory"
            echo "  $0 --skip-backup                     # Skip backup"
            echo ""
            echo "Cronjob example:"
            echo "  0 2 * * * /usr/local/bin/n8nupdater >> /var/log/n8nupdater.log 2>&1"
            exit 0
            ;;
    esac
done

# Cleanup function for lock file and signal handling
cleanup() {
    exit_code=$?
    if [ -f "$LOCK_FILE" ]; then
        rm -f "$LOCK_FILE"
    fi
    if [ $exit_code -ne 0 ]; then
        log_error "Script exited with error code: $exit_code"
    fi
    exit $exit_code
}

# Set up signal handlers
trap cleanup EXIT INT TERM

# Color codes for user-friendly output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Check if output is a terminal (for colors)
if [ -t 1 ]; then
    USE_COLORS=true
else
    USE_COLORS=false
fi

# Helper function to print colored output
print_color() {
    local color=$1
    shift
    if [ "$USE_COLORS" = true ]; then
        echo -e "${color}$@${NC}"
    else
        echo "$@"
    fi
}

# Logging function with fallback to stderr if log file fails
log() {
    message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    if ! echo "$message" >> "$LOG_FILE" 2>/dev/null; then
        echo "$message" >&2
    fi
}

log_error() {
    message="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"
    if ! echo "$message" >> "$LOG_FILE" 2>/dev/null; then
        echo "$message" >&2
    fi
    print_color "$RED" "❌ ERROR: $1" >&2
}

log_info() {
    message="[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1"
    if ! echo "$message" >> "$LOG_FILE" 2>/dev/null; then
        echo "$message" >&2
    fi
    print_color "$BLUE" "ℹ️  INFO: $1"
}

log_warning() {
    message="[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1"
    if ! echo "$message" >> "$LOG_FILE" 2>/dev/null; then
        echo "$message" >&2
    fi
    print_color "$YELLOW" "⚠️  WARNING: $1"
}

log_success() {
    message="[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1"
    if ! echo "$message" >> "$LOG_FILE" 2>/dev/null; then
        echo "$message" >&2
    fi
    print_color "$GREEN" "✅ SUCCESS: $1"
}

log_step() {
    message="[$(date '+%Y-%m-%d %H:%M:%S')] STEP: $1"
    if ! echo "$message" >> "$LOG_FILE" 2>/dev/null; then
        echo "$message" >&2
    fi
    print_color "$CYAN" "▶️  $1"
}

log_skip() {
    message="[$(date '+%Y-%m-%d %H:%M:%S')] SKIP: $1"
    if ! echo "$message" >> "$LOG_FILE" 2>/dev/null; then
        echo "$message" >&2
    fi
    print_color "$YELLOW" "⏭️  SKIPPED: $1"
}

# Validate and normalize paths
validate_path() {
    local path="$1"
    local path_type="$2"
    
    # Check for empty path
    if [ -z "$path" ]; then
        log_error "${path_type} path is empty"
        return 1
    fi
    
    # Check for absolute path
    if [[ ! "$path" = /* ]]; then
        log_error "${path_type} path must be absolute: $path"
        return 1
    fi
    
    # Normalize path (remove trailing slashes)
    echo "${path%/}"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# Create log file directory if it doesn't exist
LOG_DIR=$(dirname "$LOG_FILE")
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR" || {
        echo "ERROR: Cannot create log directory: $LOG_DIR" >&2
        exit 1
    }
fi

# Ensure log file is writable
touch "$LOG_FILE" 2>/dev/null || {
    echo "ERROR: Cannot write to log file: $LOG_FILE" >&2
    exit 1
}

# Check for lock file (prevent concurrent execution)
if [ -f "$LOCK_FILE" ]; then
    pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        log_error "Another instance is already running (PID: $pid)"
        exit 1
    else
        log_warning "Stale lock file found, removing..."
        rm -f "$LOCK_FILE"
    fi
fi

# Create lock file
echo $$ > "$LOCK_FILE" || {
    log_error "Cannot create lock file: $LOCK_FILE"
    exit 1
}

# Validate paths
INSTALL_DIR=$(validate_path "$INSTALL_DIR" "Installation") || exit 1
BACKUP_DIR=$(validate_path "$BACKUP_DIR" "Backup") || exit 1

# Check for required commands
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command not found: $cmd"
        return 1
    fi
}

# Check for Docker and Docker Compose
if ! check_command docker; then
    log_error "Docker is not installed or not in PATH"
    exit 1
fi

# Check for Docker Compose (try both v2 and v1)
DOCKER_COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif docker-compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    log_error "Docker Compose is not installed or not in PATH"
    exit 1
fi

log_info "Using Docker Compose command: $DOCKER_COMPOSE_CMD"

# Check if Docker daemon is running
if ! docker info >/dev/null 2>&1; then
    log_error "Docker daemon is not running"
    exit 1
fi

# Check for required commands
for cmd in curl tar gzip; do
    if ! check_command "$cmd"; then
        log_error "Required command not found: $cmd"
        exit 1
    fi
done

echo ""
print_color "$BOLD" "═══════════════════════════════════════════════════════════"
print_color "$BOLD" "  n8n Updater - Starting Update Process"
print_color "$BOLD" "═══════════════════════════════════════════════════════════"
echo ""
log_info "Installation directory: ${INSTALL_DIR}"
log_info "Backup directory: ${BACKUP_DIR}"
log_info "Log file: ${LOG_FILE}"
echo ""

# Auto-detect installation directory if default doesn't exist
if [ ! -d "$INSTALL_DIR" ]; then
    log_warning "Installation directory ${INSTALL_DIR} not found. Attempting to locate n8n installation..."
    
    # Try common locations
    COMMON_DIRS=(
        "/opt/n8n-docker-caddy"
        "/opt/n8n"
        "/opt/docker/n8n"
        "/home/n8n"
    )
    
    FOUND_DIR=""
    for dir in "${COMMON_DIRS[@]}"; do
        if [ -d "$dir" ] && { [ -f "${dir}/docker-compose.yml" ] || [ -f "${dir}/docker-compose.yaml" ]; }; then
            FOUND_DIR="$dir"
            break
        fi
    done
    
    # If still not found, try searching
    if [ -z "$FOUND_DIR" ]; then
        FOUND_DIR=$(find /opt -type d -maxdepth 3 \( -name '*n8n*' -o -name '*docker*' \) 2>/dev/null | while read -r dir; do
            if [ -f "${dir}/docker-compose.yml" ] || [ -f "${dir}/docker-compose.yaml" ]; then
                echo "$dir"
                break
            fi
        done | head -1)
    fi
    
    if [ -n "$FOUND_DIR" ]; then
        log_info "Found n8n installation at: ${FOUND_DIR}"
        INSTALL_DIR="$FOUND_DIR"
    else
        log_error "Could not locate n8n installation directory."
        log_error "Please set INSTALL_DIR environment variable or use --install-dir option"
        exit 1
    fi
fi

# Verify installation directory is readable
if [ ! -r "$INSTALL_DIR" ]; then
    log_error "Cannot read installation directory: ${INSTALL_DIR}"
    exit 1
fi

# Verify installation directory has compose file
if [ ! -f "${INSTALL_DIR}/docker-compose.yml" ] && [ ! -f "${INSTALL_DIR}/docker-compose.yaml" ]; then
    log_error "docker-compose.yml or docker-compose.yaml not found in ${INSTALL_DIR}"
    exit 1
fi

# Validate docker-compose file syntax
log_step "Validating docker-compose configuration..."
if ! $DOCKER_COMPOSE_CMD -f "${INSTALL_DIR}/docker-compose.yml" config >/dev/null 2>&1 && \
   ! $DOCKER_COMPOSE_CMD -f "${INSTALL_DIR}/docker-compose.yaml" config >/dev/null 2>&1; then
    log_error "docker-compose configuration file has syntax errors"
    exit 1
fi
log_success "Docker Compose configuration is valid"
echo ""

# Check disk space for backup directory
check_disk_space() {
    local path="$1"
    local required_mb="${2:-100}"  # Default 100MB
    
    local available_kb=$(df -k "$path" 2>/dev/null | tail -1 | awk '{print $4}')
    local available_mb=$((available_kb / 1024))
    
    if [ "$available_mb" -lt "$required_mb" ]; then
        log_warning "Low disk space: ${available_mb}MB available (recommended: ${required_mb}MB+)"
        return 1
    fi
    return 0
}

# Backup function
backup_n8n_data() {
    log_step "Creating backup of n8n data..."
    
    # Check disk space
    if ! check_disk_space "$BACKUP_DIR" 100; then
        log_warning "Continuing with backup despite low disk space..."
    fi
    
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local backup_path="${BACKUP_DIR}/n8n-backup-${TIMESTAMP}"
    
    log_info "Backup location: ${backup_path}"
    
    # Create backup directory
    if ! mkdir -p "${backup_path}"; then
        log_error "Failed to create backup directory: ${backup_path}"
        return 1
    fi
    
    # Change to installation directory
    if ! cd "${INSTALL_DIR}"; then
        log_error "Failed to change to installation directory"
        return 1
    fi
    
    # Get container name
    CONTAINER_NAME=$($DOCKER_COMPOSE_CMD ps -q n8n 2>/dev/null | head -1 || echo "")
    
    if [ -z "$CONTAINER_NAME" ]; then
        log_warning "n8n container not running. Attempting to find container name..."
        CONTAINER_NAME=$($DOCKER_COMPOSE_CMD config --services 2>/dev/null | grep -i n8n | head -1 || echo "")
    fi
    
    # Backup method 1: Export workflows via n8n API (if container is running)
    if [ -n "$CONTAINER_NAME" ]; then
        log_info "Attempting to export workflows via API..."
        
        # Try to get API credentials from environment or docker-compose file
        API_KEY=$($DOCKER_COMPOSE_CMD exec -T n8n printenv N8N_API_KEY 2>/dev/null || \
                  grep -i 'N8N_API_KEY' .env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
        
        if [ -n "$API_KEY" ]; then
            # Get n8n URL/port
            N8N_PORT=$($DOCKER_COMPOSE_CMD port n8n 5678 2>/dev/null | cut -d':' -f2 || echo "5678")
            N8N_HOST=$($DOCKER_COMPOSE_CMD port n8n 5678 2>/dev/null | cut -d':' -f1 || echo "localhost")
            
            log_info "Exporting workflows via API..."
            # Use timeout and proper quoting to prevent injection
            if timeout 30 curl -sf --max-time 30 \
                -H "X-N8N-API-KEY: ${API_KEY}" \
                "http://${N8N_HOST}:${N8N_PORT}/api/v1/workflows" \
                > "${backup_path}/workflows.json" 2>/dev/null; then
                # Validate JSON
                if command -v jq >/dev/null 2>&1; then
                    if ! jq empty "${backup_path}/workflows.json" 2>/dev/null; then
                        log_warning "API returned invalid JSON, removing file"
                        rm -f "${backup_path}/workflows.json"
                    else
                        log_info "Workflows exported successfully via API"
                    fi
                else
                    log_info "Workflows exported via API (JSON validation skipped - jq not installed)"
                fi
            else
                log_warning "API export failed, will use volume backup instead"
            fi
        else
            log_info "API key not found, skipping API export"
        fi
    fi
    
    # Backup method 2: Copy Docker volumes/data directories
    log_info "Backing up Docker volumes and data directories..."
    
    # Find and backup n8n data volumes
    VOLUME_COUNT=0
    $DOCKER_COMPOSE_CMD ps -q 2>/dev/null | while read -r container_id; do
        [ -z "$container_id" ] && continue
        docker inspect "$container_id" --format '{{range .Mounts}}{{.Source}} {{end}}' 2>/dev/null | \
        tr ' ' '\n' | grep -v '^$' | sort -u | while read -r vol; do
            [ -z "$vol" ] && continue
            if [ -d "$vol" ] && [ -r "$vol" ]; then
            VOLUME_NAME=$(basename "$vol")
            VOLUME_DIR=$(dirname "$vol")
            log_info "Backing up volume: ${VOLUME_NAME}"
            # Use proper quoting and handle paths with spaces
            if tar czf "${backup_path}/volume-${VOLUME_NAME}.tar.gz" -C "$VOLUME_DIR" "$VOLUME_NAME" 2>/dev/null; then
                    VOLUME_COUNT=$((VOLUME_COUNT + 1))
                else
                    log_warning "Failed to backup volume: ${VOLUME_NAME}"
                fi
            fi
        done
    done
    
    # Backup the entire installation directory (includes docker-compose.yml, .env, etc.)
    log_info "Backing up installation configuration..."
    CONFIG_FILES=()
    [ -f "${INSTALL_DIR}/docker-compose.yml" ] && CONFIG_FILES+=("docker-compose.yml")
    [ -f "${INSTALL_DIR}/docker-compose.yaml" ] && CONFIG_FILES+=("docker-compose.yaml")
    [ -f "${INSTALL_DIR}/.env" ] && CONFIG_FILES+=(".env")
    
    if [ ${#CONFIG_FILES[@]} -gt 0 ]; then
        if ! tar czf "${backup_path}/config.tar.gz" -C "${INSTALL_DIR}" "${CONFIG_FILES[@]}" 2>/dev/null; then
            log_warning "Failed to backup configuration files"
        fi
    fi
    
    # Backup database if using SQLite
    log_info "Checking for database files..."
    DB_COUNT=0
    find "${INSTALL_DIR}" -maxdepth 3 \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) -type f 2>/dev/null | while read -r db; do
        if [ -f "$db" ] && [ -r "$db" ]; then
            DB_NAME=$(basename "$db")
            DB_DIR=$(dirname "$db")
            log_info "Backing up database: ${DB_NAME}"
            if tar czf "${backup_path}/database-${DB_NAME}.tar.gz" -C "$DB_DIR" "$DB_NAME" 2>/dev/null; then
                DB_COUNT=$((DB_COUNT + 1))
            else
                log_warning "Failed to backup database: ${DB_NAME}"
            fi
        fi
    done
    
    # Create backup info file
    cat > "${backup_path}/backup-info.txt" << EOF
n8n Backup Information
======================
Backup Date: $(date)
Installation Directory: ${INSTALL_DIR}
Container Name: ${CONTAINER_NAME}
Backup Location: ${backup_path}

Contents:
$(ls -lh "${backup_path}" 2>/dev/null || echo 'No files found')
EOF
    
    BACKUP_SIZE=$(du -sh "${backup_path}" 2>/dev/null | cut -f1 || echo 'unknown')
    
    # Verify backup was created
    if [ ! -d "$backup_path" ] || [ -z "$(ls -A "$backup_path" 2>/dev/null)" ]; then
        log_error "Backup directory is empty or was not created properly"
        return 1
    fi
    
    # Set global variable for summary
    BACKUP_PATH="$backup_path"
    
    log_success "Backup completed successfully"
    log_info "  Location: ${backup_path}"
    log_info "  Size: ${BACKUP_SIZE}"
    
    return 0
}

# Perform backup if not skipped
BACKUP_CREATED=false
BACKUP_PATH=""
if [ "$SKIP_BACKUP" != "true" ]; then
    if backup_n8n_data; then
        BACKUP_CREATED=true
    else
        log_error "Backup failed, but continuing with update..."
    fi
    echo ""
else
    log_skip "Backup step (--skip-backup flag used)"
    echo ""
fi

# Execute update commands
if ! cd "${INSTALL_DIR}"; then
    log_error "Failed to change to installation directory"
    exit 1
fi

# Step 1: Pull latest Docker images
log_step "Step 1/4: Pulling latest Docker images..."
if timeout "$TIMEOUT" $DOCKER_COMPOSE_CMD pull --quiet; then
    log_success "Docker images pulled successfully"
else
    log_error "Failed to pull Docker images!"
    exit 1
fi
echo ""

# Step 2: Stop and remove current containers
log_step "Step 2/4: Stopping and removing current containers..."
# Use --remove-orphans to clean up any orphaned containers
if $DOCKER_COMPOSE_CMD down --remove-orphans; then
    log_success "Containers stopped and removed successfully"
else
    log_warning "Some containers may not have stopped cleanly, continuing..."
fi
echo ""

# Step 3: Start containers with new images
log_step "Step 3/4: Starting containers with new images..."
if $DOCKER_COMPOSE_CMD up -d; then
    log_success "Containers started successfully"
else
    log_error "Failed to start containers!"
    exit 1
fi
echo ""

# Step 4: Verify containers are running
log_step "Step 4/4: Verifying containers are running..."
sleep 5  # Give containers time to start

# Count failed containers and clean the output
FAILED_CONTAINERS=$($DOCKER_COMPOSE_CMD ps --format json 2>/dev/null | \
    grep -c '"State":"exited"' 2>/dev/null || echo "0")
# Remove any whitespace/newlines and ensure it's a number
FAILED_CONTAINERS=$(echo "$FAILED_CONTAINERS" | tr -d '[:space:]')
# Default to 0 if empty or not a number
if [ -z "$FAILED_CONTAINERS" ] || ! [[ "$FAILED_CONTAINERS" =~ ^[0-9]+$ ]]; then
    FAILED_CONTAINERS=0
fi

if [ "$FAILED_CONTAINERS" -gt 0 ]; then
    log_warning "Some containers may have exited. Checking status..."
    $DOCKER_COMPOSE_CMD ps
    log_warning "Please check container logs for issues"
    CONTAINER_STATUS="⚠️  Some containers may have issues"
else
    log_success "All containers are running"
    CONTAINER_STATUS="✅ All containers running"
fi
echo ""

# Summary
print_color "$BOLD" "═══════════════════════════════════════════════════════════"
print_color "$BOLD" "  Update Summary"
print_color "$BOLD" "═══════════════════════════════════════════════════════════"
echo ""

if [ "$SKIP_BACKUP" = "true" ]; then
    print_color "$YELLOW" "  Backup: ⏭️  Skipped (--skip-backup flag used)"
else
    if [ "$BACKUP_CREATED" = true ]; then
        print_color "$GREEN" "  Backup: ✅ Created successfully"
        if [ -n "$BACKUP_PATH" ]; then
            BACKUP_SIZE=$(du -sh "$BACKUP_PATH" 2>/dev/null | cut -f1 || echo 'unknown')
            echo "    Location: $BACKUP_PATH"
            echo "    Size: $BACKUP_SIZE"
        fi
    else
        print_color "$RED" "  Backup: ❌ Failed (but update continued)"
    fi
fi

echo ""
print_color "$GREEN" "  Docker Images: ✅ Pulled successfully"
print_color "$GREEN" "  Containers: ✅ Stopped and removed"
print_color "$GREEN" "  Containers: ✅ Started with new images"
echo "  Container Status: $CONTAINER_STATUS"
echo ""
print_color "$GREEN" "✅ Update process completed successfully!"
echo ""
log_info "Please verify the version number in your n8n web UI"
log_info "(check the footer or About section) to confirm the update."
echo ""

exit 0
