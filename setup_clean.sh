iconv: illegal input sequence at position 8192
#!/usr/bin/env bash
#===============================================================================
# Termux-Proot Setup - Enterprise-Grade Development Environment Setup
#===============================================================================
# Features:
#   - Interactive TUI setup
#   - Selective feature installation
#   - Backup & Restore
#   - Upgrade support
#   - Validation tests
#===============================================================================

set -euo pipefail

# Version
VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${REPO_DIR}/config"
BACKUP_DIR="${HOME}/.setup-backups"
LOG_FILE="${HOME}/.setup.log"

# Feature flags (can be overridden)
FEATURE_TMUX="${FEATURE_TMUX:-1}"
FEATURE_PICOCLAW="${FEATURE_PICOCLAW:-1}"
FEATURE_SHELL="${FEATURE_SHELL:-1}"
FEATURE_TERMUX_BOOT="${FEATURE_TERMUX_BOOT:-1}"

#===============================================================================
# Utility Functions
#===============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

info() { echo -e "${BLUE}${NC} $*"; }
success() { echo -e "${GREEN}${NC} $*"; }
warn() { echo -e "${YELLOW}${NC} $*"; }
error() { echo -e "${RED}${NC} $*"; }

confirm() {
    local prompt="$1"
    local response
    echo -en "${YELLOW}${prompt} [y/N]: ${NC}"
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

#===============================================================================
# Dependency Check & Installation
#===============================================================================

check_dependencies() {
    info "Checking dependencies..."
    
    local missing=()
    
    # Check for required commands
    for cmd in tmux zsh jq curl git; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        warn "Missing dependencies: ${missing[*]}"
        
        if confirm "Install missing dependencies?"; then
            pkg update -y
            pkg install -y "${missing[@]}"
            success "Dependencies installed"
        else
            error "Cannot proceed without dependencies"
            return 1
        fi
    fi
    
    success "All dependencies satisfied"
}

#===============================================================================
# Backup & Restore
#===============================================================================

backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${BACKUP_DIR}/backup_${timestamp}"
    
    info "Creating backup at: $backup_path"
    mkdir -p "$backup_path"
    
    # Backup existing configs
    [ -f "$HOME/.tmux.conf" ] && cp "$HOME/.tmux.conf" "$backup_path/"
    [ -d "$HOME/.tmux" ] && cp -r "$HOME/.tmux" "$backup_path/"
    [ -d "$HOME/.picoclaw" ] && cp -r "$HOME/.picoclaw" "$backup_path/"
    [ -f "$HOME/.zshrc" ] && cp "$HOME/.zshrc" "$backup_path/"
    [ -f "$HOME/.zshenv" ] && cp "$HOME/.zshenv" "$backup_path/"
    [ -f "$HOME/.profile" ] && cp "$HOME/.profile" "$backup_path/"
    [ -d "$HOME/.termux/boot" ] && cp -r "$HOME/.termux/boot" "$backup_path/"
    
    # Create backup info
    cat > "$backup_path/backup_info.txt" << EOF
Backup Date: $(date)
Version: $VERSION
Features Backed Up:
$(declare -p FEATURE_TMUX FEATURE_PICOCLAW FEATURE_SHELL FEATURE_TERMUX_BOOT 2>/dev/null || echo "N/A")
EOF
    
    # Create archive
    local archive="${BACKUP_DIR}/backup_${timestamp}.tar.gz"
    tar -czf "$archive" -C "$(dirname "$backup_path)" "$(basename "$backup_path")"
    rm -rf "$backup_path"
    
    success "Backup created: $archive"
    echo "$archive"
}

restore() {
    local archive="$1"
    
    if [ ! -f "$archive" ]; then
        error "Backup not found: $archive"
        return 1
    fi
    
    info "Restoring from: $archive"
    
    # Extract to temp
    local temp_dir=$(mktemp -d)
    tar -xzf "$archive" -C "$temp_dir"
    local backup_path=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
    
    if [ -z "$backup_path" ]; then
        error "Invalid backup archive"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Restore configs
    [ -f "$backup_path/.tmux.conf" ] && cp "$backup_path/.tmux.conf" "$HOME/"
    [ -d "$backup_path/.tmux" ] && cp -r "$backup_path/.tmux" "$HOME/"
    [ -d "$backup_path/.picoclaw" ] && cp -r "$backup_path/.picoclaw" "$HOME/"
    [ -f "$backup_path/.zshrc" ] && cp "$backup_path/.zshrc" "$HOME/"
    [ -f "$backup_path/.zshenv" ] && cp "$backup_path/.zshenv" "$HOME/"
    [ -f "$backup_path/.profile" ] && cp "$backup_path/.profile" "$HOME/"
    [ -d "$backup_path/boot" ] && cp -r "$backup_path/boot" "$HOME/.termux/"
    
    rm -rf "$temp_dir"
    
    success "Backup restored successfully"
}

list_backups() {
    info "Available backups:"
    ls -lh "${BACKUP_DIR}"/backup_*.tar.gz 2>/dev/null || echo "No backups found"
}

#===============================================================================
# Feature Installation
#===============================================================================

install_tmux() {
    info "Installing TMUX configuration..."
    
    # Install tmux plugins
    mkdir -p "$HOME/.tmux/plugins"
    
    # TPM
    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
        git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
    fi
    
    # Resurrect
    if [ ! -d "$HOME/.tmux/plugins/tmux-resurrect" ]; then
        git clone --depth 1 https://github.com/tmux-plugins/tmux-resurrect "$HOME/.tmux/plugins/tmux-resurrect"
    fi
    
    # Continuum
    if [ ! -d "$HOME/.tmux/plugins/tmux-continuum" ]; then
        git clone --depth 1 https://github.com/tmux-plugins/tmux-continuum "$HOME/.tmux/plugins/tmux-continuum"
    fi
    
    # Install tmux.conf
    cp "${CONFIG_DIR}/tmux/tmux.conf" "$HOME/.tmux.conf"
    
    # Install session launcher
    mkdir -p "$HOME/.tmux"
    cp "${CONFIG_DIR}/tmux/session-launcher.sh" "$HOME/.tmux/session-launcher.sh"
    chmod +x "$HOME/.tmux/session-launcher.sh"
    
    success "TMUX installed"
}

install_picoclaw() {
    info "Installing Picoclaw configuration..."
    
    mkdir -p "$HOME/.picoclaw/scripts"
    mkdir -p "$HOME/.picoclaw/logs"
    mkdir -p "$HOME/.picoclaw/workspace"
    
    # Copy config template
    cp "${CONFIG_DIR}/picoclaw/config.json.template" "$HOME/.picoclaw/config.json"
    
    # Copy scripts
    for script in "${CONFIG_DIR}"/picoclaw/scripts/*.sh; do
        [ -f "$script" ] || continue
        cp "$script" "$HOME/.picoclaw/scripts/"
        chmod +x "$HOME/.picoclaw/scripts/$(basename "$script")"
    done
    
    success "Picoclaw installed"
}

install_shell() {
    info "Installing shell configuration..."
    
    # Install zshenv (with user customization prompt)
    if [ ! -f "$HOME/.zshenv" ]; then
        cp "${CONFIG_DIR}/shell/zshenv.template" "$HOME/.zshenv"
    else
        warn " ~/.zshenv exists - skipping (backup first to replace)"
    fi
    
    # Install zshrc aliases (append, don't replace)
    if grep -q "TMUX Session Launcher" "$HOME/.zshrc" 2>/dev/null; then
        info "Shell aliases already present in .zshrc"
    else
        cat >> "$HOME/.zshrc" << 'EOF'

# 
# TMUX Session Launcher (setup-install)
# 
LAUNCHER="$HOME/.tmux/session-launcher.sh"
alias tmux-launch='$LAUNCHER'
alias tmux-all='$LAUNCHER all'
alias tmux-status='$LAUNCHER status'

# Quick session shortcuts
alias t-main='tmux attach -t main 2>/dev/null || ($LAUNCHER main && tmux attach -t m