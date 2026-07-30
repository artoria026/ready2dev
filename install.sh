#!/usr/bin/env bash
set -euo pipefail

# ===============================================
# Ready2Dev - Development Environment Setup
# ===============================================
# Description: Single entry point for Ready2Dev. Presents a menu to
#              either run the full environment setup (clean OS), install
#              aliases & tool scripts for the first time, or update
#              aliases & tool scripts on an already-installed machine.
# Author: Ready2Dev Team
# Version: 6.0 - Ubuntu 24.04
# Usage: ./install.sh
# ===============================================

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/lib/common.sh
source "$CURRENT_DIR/tools/lib/common.sh"

# ===== Configuration =====
GIT_USERNAME="achavira"
GIT_EMAIL="achavira@mscdirect.com.mx"

# ===== UTILITY FUNCTIONS =====

# Clears the screen before a section box, so the scrollback from the
# previous section (apt/pip output, etc.) doesn't linger as you move through
# the flow. Only used in install.sh - the deployed git_*.sh tool scripts
# intentionally don't clear, so a one-off command doesn't wipe out whatever
# was already on the user's terminal.
section_header() {
    clear
    print_header "$1"
}

# Display script header
show_header() {
    section_header "🚀 Ready2Dev Environment Setup"
}

# Section separator
section_separator() {
    echo
}

# SECTION 0: Mode Selection
# Decides which flow main() runs: a full clean-OS install, a first-time
# install of just the aliases/tools, or an update of an existing install.
select_mode() {
    echo -e "${MAGENTA}📋 SECTION 0: What do you want to do?${RESET}"
    echo
    echo -e "  ${DIM}── Instalación ──────────────────────────────────────────${RESET}"
    echo -e "   ${CYAN}1)${RESET} Instalación completa ${GREEN}(SO limpio — recomendado la primera vez)${RESET}"
    echo -e "   ${CYAN}2)${RESET} Instalar solo aliases y tools ${YELLOW}(el SO ya está listo)${RESET}"
    echo
    echo -e "  ${DIM}── Mantenimiento ─────────────────────────────────────────${RESET}"
    echo -e "   ${CYAN}3)${RESET} Actualizar aliases y tools ${YELLOW}(ya instalado, solo refrescar)${RESET}"
    echo
    echo -e "   ${CYAN}4)${RESET} Salir"
    echo

    read -rp "$(echo -e "${YELLOW}👉 Elige una opción [1-4]: ${RESET}")" MODE_CHOICE

    case "$MODE_CHOICE" in
        1) INSTALL_MODE="full" ;;
        2) INSTALL_MODE="install_tools" ;;
        3) INSTALL_MODE="update_tools" ;;
        4) echo -e "${BLUE}👋 Saliendo.${RESET}"; exit 0 ;;
        *) echo -e "${RED}⛔ Opción inválida.${RESET}"; exit 1 ;;
    esac
    echo
}

# ===== MAIN SETUP FUNCTIONS =====

# SECTION 1: System Update & Package Installation
system_update() {
    section_header "📦 SECTION 1: System Update & Package Installation"

    run_step "Updating package list" sudo apt update -y
    run_step "Upgrading system packages" sudo apt full-upgrade -y
    run_step "Cleaning unnecessary packages" sudo apt autoremove -y
    run_step "Installing neofetch" sudo apt install neofetch -y
    echo

    echo -e "${GREEN}✅ System update completed.${RESET}"
    echo
}

# SECTION 2: Git Global Configuration
git_configuration() {
    section_header "⚙️  SECTION 2: Git Global Configuration"

    echo -e "${YELLOW}🔧 Configuring Git global settings...${RESET}"
    git config --global user.name "$GIT_USERNAME"
    git config --global user.email "$GIT_EMAIL"
    git config --global pull.rebase false
    echo

    echo -e "${GREEN}✅ Git configuration completed.${RESET}"
    echo
}

# NOTE: user selection, tool script deployment, db_restore credentials and
# the ~/.bashrc alias block are shared across install modes and live in
# tools/lib/common.sh as user_selection(), deploy_tool_scripts(),
# configure_db_restore_credentials() and write_alias_block().

# SECTION 3: Xentro Environment Setup
xentro_environment_setup() {
    section_header "🐍 SECTION 3: Xentro Environment Setup"

    if confirm "❓ Do you want to install the Xentro development environment?"; then
        echo
        install_xentro_environment
    else
        echo
        echo -e "${BLUE}ℹ️  Skipping Xentro environment setup.${RESET}"
        echo
    fi
}

# Install MySQL dependencies for Xentro
install_mysql_dependencies() {
    echo -e "${YELLOW}🗄️  Installing MySQL dependencies for Xentro...${RESET}"
    run_step "Installing mysql-server" sudo apt install mysql-server -y
    run_step "Installing libmysqlclient-dev" sudo apt-get install libmysqlclient-dev -y
    run_step "Refreshing package list" sudo apt-get update
    run_step "Installing Python 3 dev packages" sudo apt-get install python3-dev default-libmysqlclient-dev libssl-dev -y
    run_step "Installing build-essential" sudo apt-get install build-essential -y
    run_step "Installing mysql-client" sudo apt-get install mysql-client -y
    run_step "Installing libmysqlclient-dev" sudo apt-get install libmysqlclient-dev -y
    run_step "Finishing MySQL dependencies configuration" sudo apt-get install mysql-server mysql-common -y

    sudo mkdir -p /usr/include/mysql
    sudo touch /usr/include/mysql/my_config.h
    echo "#define HAVE_WCSCOLL 1" | sudo tee /usr/include/mysql/my_config.h
    echo
}

# Install Xentro environment
install_xentro_environment() {
    echo -e "${MAGENTA}🔧 Setting up Xentro environment...${RESET}"
    echo

    # Update dependencies and repositories
    run_step "Updating all dependencies and repositories" bash -c "sudo apt update && sudo apt upgrade -y"
    echo

    # Install development libraries
    install_development_libraries

    # Install Python 3.12 from source
    install_python3_12_from_source

    # Install MySQL dependencies
    install_mysql_dependencies

    # Create virtual environment with Python 3.12
    create_virtual_environment
}

# Install development libraries
install_development_libraries() {
    run_step "Installing development libraries" sudo apt install -y \
        build-essential \
        libssl-dev \
        zlib1g-dev \
        libncurses5-dev \
        libncursesw5-dev \
        libreadline-dev \
        libsqlite3-dev \
        libgdbm-dev \
        libdb5.3-dev \
        libbz2-dev \
        libexpat1-dev \
        liblzma-dev \
        tk-dev \
        libffi-dev \
        wget \
        curl \
        xz-utils \
        git

    run_step "Installing imaging libraries" sudo apt install -y \
        libjpeg-dev \
        zlib1g-dev \
        libtiff-dev \
        libfreetype6-dev \
        liblcms2-dev \
        libwebp-dev \
        tcl8.6-dev \
        tk8.6-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libopenjp2-7-dev \
        libcairo2-dev \
        cmake

    run_step "Installing Python development tools" sudo apt install -y \
        python3-dev \
        python3-pip \
        python3.12-venv \
        default-libmysqlclient-dev \
        pkg-config

    echo -e "${GREEN}✅ Development libraries installed successfully.${RESET}"
    echo
}

# Install Python 3.12 from source
install_python3_12_from_source() {

    # Check if Python 3.12 is already installed
    if command -v python3.12 &>/dev/null; then
        echo -e "${BLUE}ℹ️  Python 3.12 is already installed${RESET}"
        python3.12 --version
        echo
        return 0
    fi

    # Download Python 3.12
    cd /tmp
    run_step "Downloading Python 3.12.0" sudo wget https://www.python.org/ftp/python/3.12.0/Python-3.12.0.tgz

    run_step "Extracting Python 3.12.0" sudo tar xzf Python-3.12.0.tgz
    cd Python-3.12.0

    run_step "Configuring Python 3.12 with optimizations (this may take a while)" sudo ./configure --enable-optimizations

    run_step "Compiling Python 3.12 (this will take several minutes)" sudo make altinstall
    echo

    # Verify installation
    echo -e "${GREEN}✅ Python 3.12 installation completed:${RESET}"
    python3.12 --version
    pip3.12 --version
    echo

    # Cleanup
    cd /tmp
    sudo rm -rf Python-3.12.0 Python-3.12.0.tgz
    echo -e "${GREEN}✅ Cleanup completed${RESET}"
    echo
}

# Create virtual environment with Python 3.12
create_virtual_environment() {
    # Create projects directory if it doesn't exist
    echo -e "${YELLOW}📁 Creating projects directory...${RESET}"
    sudo mkdir -p "${TARGET_HOME}/projects/msc"
    sudo chown "$TARGET_USER":"$TARGET_USER" "${TARGET_HOME}/projects/msc"
    echo

    # Create Xentro virtual environment with Python 3.12
    echo -e "${YELLOW}🐍 Creating Xentro virtual environment with Python 3.12...${RESET}"
    cd "${TARGET_HOME}/projects/msc"
    sudo -u "$TARGET_USER" python3.12 -m venv entornoXentro
    echo

    run_step "Upgrading pip and installing essential packages" sudo -u "$TARGET_USER" bash -c "
        source entornoXentro/bin/activate
        pip install --upgrade pip
        python3.12 -m ensurepip --upgrade
        python3.12 -m pip install --upgrade pip setuptools wheel
        deactivate
    "

    run_step "Installing pre-requirements (numpy, pandas, pyzmq, requests)" sudo -u "$TARGET_USER" bash -c "
        source entornoXentro/bin/activate
        pip install 'numpy>=1.26.4' 'pandas>=2.2.2'
        pip install requests
        pip install 'pyzmq>=25.1.0'
        deactivate
    "

    run_step "Installing gunicorn, django, and flask" sudo -u "$TARGET_USER" bash -c "
        source entornoXentro/bin/activate
        pip install gunicorn django flask
        deactivate
    "
    echo

    echo -e "${GREEN}✅ Xentro environment setup completed!${RESET}"
    echo -e "${CYAN}💡 To activate the environment, use: source ${TARGET_HOME}/projects/msc/entornoXentro/bin/activate${RESET}"
    echo
}

# Clone Xentro repositories
clone_xentro_repositories() {
    section_header "📦 SECTION 4: Clone Xentro Repositories"

    echo -e "${YELLOW}📦 Cloning Xentro repository...${RESET}"
    cd "${TARGET_HOME}/projects/msc"

    # Attempt to clone the repository
    if clone_xentro_repo; then
        setup_xentro_projects
    else
        echo -e "${BLUE}ℹ️  Repository clone skipped. You can clone manually later using:${RESET}"
        echo -e "${CYAN}   git clone git@bitbucket.org:Information_technologies/buri.git${RESET}"
    fi
    echo
}

# Function to clone repository with SSH key handling
clone_xentro_repo() {
    echo -e "${BLUE}🔑 Attempting to clone Xentro repository via SSH...${RESET}"
    REPO_URL="git@bitbucket.org:Information_technologies/buri.git"

    # Try to clone the repository
    if sudo -u "$TARGET_USER" git clone "$REPO_URL" xentro_temp 2>/dev/null; then
        echo -e "${GREEN}✅ Repository cloned successfully!${RESET}"
        return 0
    else
        handle_ssh_key_authentication
        return $?
    fi
}

# Handle SSH key authentication for git clone
handle_ssh_key_authentication() {
    echo -e "${RED}❌ Failed to clone repository. SSH key authentication required.${RESET}"
    echo

    # Check if SSH key exists
    if [ -f "${TARGET_HOME}/.ssh/id_ed25519.pub" ]; then
        show_existing_ssh_key
    else
        generate_new_ssh_key
    fi

    provide_bitbucket_instructions

    if confirm "❓ Have you added the SSH key to Bitbucket?"; then
        retry_git_clone
        return $?
    else
        echo -e "${YELLOW}⚠️ Skipping repository clone. You can clone manually later.${RESET}"
        return 1
    fi
}

# Copy text to clipboard (supports native Ubuntu and WSL)
copy_to_clipboard() {
    local text_to_copy="$1"

    # Detect if running in WSL
    if grep -qEi "(Microsoft|WSL)" /proc/version &>/dev/null; then
        # WSL detected - use clip.exe
        echo "$text_to_copy" | clip.exe
        echo -e "${GREEN}✅ SSH key copied to clipboard (via WSL clip.exe)${RESET}"
        return 0
    fi

    # Native Linux - try different clipboard utilities
    # Try wl-copy (Wayland)
    if command -v wl-copy &>/dev/null; then
        echo "$text_to_copy" | wl-copy
        echo -e "${GREEN}✅ SSH key copied to clipboard (via wl-copy)${RESET}"
        return 0
    fi

    # Try xclip (X11)
    if command -v xclip &>/dev/null; then
        echo "$text_to_copy" | xclip -selection clipboard
        echo -e "${GREEN}✅ SSH key copied to clipboard (via xclip)${RESET}"
        return 0
    fi

    # Try xsel (X11)
    if command -v xsel &>/dev/null; then
        echo "$text_to_copy" | xsel --clipboard --input
        echo -e "${GREEN}✅ SSH key copied to clipboard (via xsel)${RESET}"
        return 0
    fi

    # No clipboard utility found - try to install one
    echo -e "${YELLOW}⚠️ No clipboard utility found. Installing xclip...${RESET}"
    if sudo apt install -y xclip &>/dev/null; then
        echo "$text_to_copy" | xclip -selection clipboard
        echo -e "${GREEN}✅ SSH key copied to clipboard (via xclip)${RESET}"
        return 0
    else
        echo -e "${RED}❌ Could not install clipboard utility. Please copy the key manually.${RESET}"
        return 1
    fi
}

# Show existing SSH key
show_existing_ssh_key() {
    echo -e "${YELLOW}📋 Your SSH public key:${RESET}"
    cat "${TARGET_HOME}/.ssh/id_ed25519.pub"
    echo

    # Copy to clipboard
    SSH_KEY_CONTENT=$(cat "${TARGET_HOME}/.ssh/id_ed25519.pub")
    copy_to_clipboard "$SSH_KEY_CONTENT"
    echo
}

# Generate new SSH key
generate_new_ssh_key() {
    echo -e "${YELLOW}⚠️ SSH key not found. Generating new SSH key...${RESET}"
    sudo -u "$TARGET_USER" ssh-keygen -t ed25519 -C "achavira@mscdirect.com.mx" -f "${TARGET_HOME}/.ssh/id_ed25519" -N ""
    echo
    echo -e "${YELLOW}📋 Your new SSH public key:${RESET}"
    cat "${TARGET_HOME}/.ssh/id_ed25519.pub"
    echo

    # Copy to clipboard
    SSH_KEY_CONTENT=$(cat "${TARGET_HOME}/.ssh/id_ed25519.pub")
    copy_to_clipboard "$SSH_KEY_CONTENT"
    echo
}

# Provide Bitbucket setup instructions
provide_bitbucket_instructions() {
    echo -e "${CYAN}🔗 Please follow these steps:${RESET}"
    echo -e "   1. Go to Bitbucket.org and log in"
    echo -e "   2. Go to Personal Settings > SSH keys"
    echo -e "   3. Click 'Add key' and paste the SSH key"
    echo -e "   4. Save the key"
    echo
}

# Retry git clone after SSH key setup
retry_git_clone() {
    echo -e "${BLUE}🔄 Retrying repository clone...${RESET}"

    REPO_URL="git@bitbucket.org:Information_technologies/buri.git"

    if sudo -u "$TARGET_USER" git clone "$REPO_URL" xentro_temp; then
        echo -e "${GREEN}✅ Repository cloned successfully!${RESET}"
        return 0
    else
        echo -e "${RED}❌ Clone failed again. Please check your SSH key configuration.${RESET}"
        return 1
    fi
}

# Setup Xentro project directories and configurations
setup_xentro_projects() {
    echo
    echo -e "${YELLOW}📂 Creating Xentro project directories...${RESET}"

    # Create xentro_nac directory
    if [ -d "xentro_temp" ]; then
        create_project_directories
        configure_git_settings
        create_configuration_files
        create_django_migration
        install_xentro_dependencies
        set_project_permissions
        show_project_summary
    fi
}

# Create project directories
create_project_directories() {
    sudo -u "$TARGET_USER" cp -r xentro_temp xentro_nac
    echo -e "${GREEN}✅ Created xentro_nac directory${RESET}"

    # Create xentro_llc directory
    sudo -u "$TARGET_USER" cp -r xentro_temp xentro_llc
    echo -e "${GREEN}✅ Created xentro_llc directory${RESET}"

    # Remove temporary directory
    sudo -u "$TARGET_USER" rm -rf xentro_temp

    # Create media directories
    sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/projects/msc/xentro_nac/media"
    echo -e "${GREEN}✅ Created media directory for xentro_nac${RESET}"

    sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/projects/msc/xentro_llc/media"
    echo -e "${GREEN}✅ Created media directory for xentro_llc${RESET}"
    echo
}

# Configure git settings for both repositories
configure_git_settings() {
    echo -e "${YELLOW}⚙️  Configuring Git settings for Xentro repositories...${RESET}"

    # Configure xentro_nac
    cd "${TARGET_HOME}/projects/msc/xentro_nac"
    sudo -u "$TARGET_USER" git config core.filemode false
    echo -e "${GREEN}✅ Git filemode disabled for xentro_nac${RESET}"

    # Configure xentro_llc
    cd "${TARGET_HOME}/projects/msc/xentro_llc"
    sudo -u "$TARGET_USER" git config core.filemode false
    echo -e "${GREEN}✅ Git filemode disabled for xentro_llc${RESET}"
    echo
}

# Create configuration files
create_configuration_files() {
    echo -e "${YELLOW}📝 Creating local_settings.py files...${RESET}"

    # Create local_settings.py for xentro_nac
    sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/projects/msc/xentro_nac/talleres"
    sudo -u "$TARGET_USER" touch "${TARGET_HOME}/projects/msc/xentro_nac/talleres/local_settings.py"
    echo -e "${GREEN}✅ Created local_settings.py for xentro_nac${RESET}"

    # Create local_settings.py for xentro_llc
    sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/projects/msc/xentro_llc/talleres"
    sudo -u "$TARGET_USER" touch "${TARGET_HOME}/projects/msc/xentro_llc/talleres/local_settings.py"
    echo -e "${GREEN}✅ Created local_settings.py for xentro_llc${RESET}"
    echo
}

# Create Django migration file
create_django_migration() {
    echo -e "${YELLOW}📦 Creating Django UserExtendido migration...${RESET}"

    MIGRATION_DIR="${TARGET_HOME}/projects/msc/entornoXentro/lib/python3.12/site-packages/django/contrib/auth/migrations"
    sudo -u "$TARGET_USER" mkdir -p "$MIGRATION_DIR"

    # Create the migration file with proper content
    sudo -u "$TARGET_USER" cat << 'EOF' > "$MIGRATION_DIR/0009_userextendido.py"
# -*- coding: utf-8 -*-
from __future__ import unicode_literals

import django.contrib.auth.models
from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('auth', '0008_alter_user_username_max_length'),
    ]

    operations = [
        migrations.CreateModel(
            name='UserExtendido',
            fields=[
            ],
            options={
                'verbose_name': 'Usuario',
                'proxy': True,
                'verbose_name_plural': 'Usuarios',
            },
            bases=('auth.user',),
            managers=[
                ('objects', django.contrib.auth.models.UserManager()),
            ],
        ),
    ]
EOF

    echo -e "${GREEN}✅ Created Django UserExtendido migration${RESET}"
    echo
}

# Install Xentro project dependencies
install_xentro_dependencies() {
    echo -e "${YELLOW}📦 Installing Xentro project dependencies...${RESET}"

    # Check if virtual environment exists
    if [ ! -d "${TARGET_HOME}/projects/msc/entornoXentro" ]; then
        echo -e "${RED}❌ Virtual environment not found. Skipping dependency installation.${RESET}"
        return 1
    fi

    # Install dependencies for xentro_nac
    if [ -f "${TARGET_HOME}/projects/msc/xentro_nac/requirements.txt" ]; then
        cd "${TARGET_HOME}/projects/msc/xentro_nac"

        run_step "Installing dependencies for xentro_nac" sudo -u "$TARGET_USER" bash -c "
            source ../entornoXentro/bin/activate
            python3.12 -m pip install --upgrade-strategy eager -r requirements.txt
            deactivate
        "
    else
        echo -e "${YELLOW}⚠️ requirements.txt not found in xentro_nac, skipping...${RESET}"
    fi

    # Install dependencies for xentro_llc
    if [ -f "${TARGET_HOME}/projects/msc/xentro_llc/requirements.txt" ]; then
        cd "${TARGET_HOME}/projects/msc/xentro_llc"

        run_step "Installing dependencies for xentro_llc" sudo -u "$TARGET_USER" bash -c "
            source ../entornoXentro/bin/activate
            python3.12 -m pip install --upgrade-strategy eager -r requirements.txt
            deactivate
        "
    else
        echo -e "${YELLOW}⚠️ requirements.txt not found in xentro_llc, skipping...${RESET}"
    fi

    echo -e "${GREEN}✅ Xentro dependencies installation completed${RESET}"
    echo
}

# Set full permissions for project directories
set_project_permissions() {
    echo -e "${YELLOW}🔐 Setting full permissions (777) to project directories...${RESET}"

    # Set permissions for xentro_nac
    sudo chmod -R 777 "${TARGET_HOME}/projects/msc/xentro_nac"
    echo -e "${GREEN}✅ Full permissions set for xentro_nac${RESET}"

    # Set permissions for xentro_llc
    sudo chmod -R 777 "${TARGET_HOME}/projects/msc/xentro_llc"
    echo -e "${GREEN}✅ Full permissions set for xentro_llc${RESET}"

    # Set permissions for entornoXentro
    sudo chmod -R 777 "${TARGET_HOME}/projects/msc/entornoXentro"
    echo -e "${GREEN}✅ Full permissions set for entornoXentro${RESET}"
    echo
}

# Show project setup summary
show_project_summary() {
    echo -e "${GREEN}✅ Xentro repositories cloned and configured successfully!${RESET}"
    echo -e "${CYAN}📂 Available projects:${RESET}"
    echo -e "   🔹 ${TARGET_HOME}/projects/msc/xentro_nac"
    echo -e "   🔹 ${TARGET_HOME}/projects/msc/xentro_llc"
    echo -e "   🔹 ${TARGET_HOME}/projects/msc/entornoXentro"
    echo -e "${CYAN}📝 Configuration files created:${RESET}"
    echo -e "   🔹 xentro_nac/talleres/local_settings.py"
    echo -e "   🔹 xentro_llc/talleres/local_settings.py"
    echo -e "   🔹 Django UserExtendido migration"
    echo -e "${CYAN}💡 Use aliases: x_env_nac, x_env_llc, x_run_nac, x_run_llc${RESET}"
}

# MySQL Configuration
mysql_configuration() {
    section_header "🗄️  SECTION 5: MySQL Configuration"

    if confirm "❓ Do you want to configure MySQL server?"; then
        install_mysql_server
        configure_mysql_for_remote_access
        setup_mysql_firewall
        show_mysql_summary
    else
        echo
        echo -e "${BLUE}ℹ️  Skipping MySQL configuration.${RESET}"
        echo
    fi
}

# Install MySQL server
install_mysql_server() {
    echo
    echo -e "${BLUE}🔧 Setting up MySQL server...${RESET}"

    # Install MySQL server and run secure installation
    run_step "Installing MySQL server" sudo apt install mysql-server -y

    echo -e "${YELLOW}🔒 Running MySQL secure installation...${RESET}"
    echo -e "${CYAN}💡 Follow the prompts to set up root password and secure your MySQL installation.${RESET}"
    sudo mysql_secure_installation
    echo
}

# Configure MySQL for remote access
configure_mysql_for_remote_access() {
    echo -e "${YELLOW}⚙️  Configuring MySQL for remote access...${RESET}"

    # Create MySQL configuration script
    cat << 'EOF' > /tmp/mysql_setup.sql
-- Create remote user
CREATE USER 'remote'@'%' IDENTIFIED WITH mysql_native_password BY 'admin';
GRANT ALL PRIVILEGES ON *.* TO 'remote'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;

-- Update root password
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'admin';
FLUSH PRIVILEGES;
EOF

    # Execute MySQL configuration
    run_step "Creating remote user and updating root password" bash -c "sudo mysql < /tmp/mysql_setup.sql"
    rm /tmp/mysql_setup.sql

    # Update MySQL configuration files
    echo -e "${YELLOW}📝 Updating MySQL configuration files...${RESET}"

    # Backup original configurations
    sudo cp /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf.backup
    sudo cp /etc/mysql/my.cnf /etc/mysql/my.cnf.backup

    # Add configuration parameters to mysqld.cnf
    cat << 'EOF' | sudo tee -a /etc/mysql/mysql.conf.d/mysqld.cnf
# Custom Ready2Dev Configuration
log_bin_trust_function_creators = 1
bind-address = 0.0.0.0
EOF

    # Replace entire my.cnf with optimized configuration
    echo -e "${YELLOW}🚀 Applying optimized MySQL 8 configuration to /etc/mysql/my.cnf...${RESET}"
    cat << 'EOF' | sudo tee /etc/mysql/my.cnf
# #############################################################################################
# Optimized MySQL 8 configuration file.
# Based on production best practices and performance optimization.
# #############################################################################################

#
# The MySQL Server configuration file.
#
# For explanations see
# https://dev.mysql.com/doc/refman/8.0/en/server-system-variables.html

!includedir /etc/mysql/conf.d/
!includedir /etc/mysql/mysql.conf.d/

[mysqld]

# ============================================================================================
# General Connection Settings
# ============================================================================================
character_set_server = utf8mb4
collation_server = utf8mb4_0900_ai_ci
max_connections = 500
wait_timeout = 28800
net_read_timeout = 60
net_write_timeout = 600
max_allowed_packet = 1G
# sql_mode: Using MySQL 8 default for stricter and safer behavior
# skip-external-locking: Obsolete and removed

# ============================================================================================
# InnoDB Memory and Performance Settings (Primary Engine)
# ============================================================================================
# Buffer Pool (Most important MySQL cache)
innodb_buffer_pool_size = 13G       # CRITICAL: Set to 70% of available RAM
innodb_buffer_pool_instances = 10   # 1 instance per GB of Buffer Pool is good practice

# Redo Log Files
innodb_log_file_size = 2G           # Robust size for heavy workloads
innodb_log_buffer_size = 256M       # Sufficient for most transactions

# Buffers for Specific Operations
bulk_insert_buffer_size = 256M
tmp_table_size = 256M
max_heap_table_size = 256M
join_buffer_size = 256M
innodb_lock_wait_timeout = 60       # Timeout for row locks

# ============================================================================================
# Data Security and Durability (FAST RESTORATION MODE)
# ============================================================================================
# WARNING! Use only for restorations. Revert these changes afterward.
innodb_flush_log_at_trx_commit = 0  # Don't write on each commit, only every second
sync_binlog = 0                     # Don't sync binary log on each commit
innodb_doublewrite = OFF            # Disable double write buffer, major speed improvement

# ============================================================================================
# Concurrency and I/O Speed (Input/Output)
# ============================================================================================
# Optimized for fast disks (SSD/NVMe)
innodb_io_capacity = 4000
innodb_io_capacity_max = 8000
innodb_read_io_threads = 8
innodb_write_io_threads = 8
innodb_flush_method = O_DIRECT      # Recommended for Linux with hardware RAID
# innodb_thread_concurrency: Obsolete. Let MySQL 8 manage automatically (value 0)

# ============================================================================================
# Table Cache Settings
# ============================================================================================
table_open_cache = 4096
table_open_cache_instances = 8
thread_cache_size = 128

# ============================================================================================
# Other Settings
# ============================================================================================
event_scheduler = ON                # Enabled as per configuration

# #############################################################################################
# ADDITIONAL SECTIONS
# #############################################################################################

[mysqldump]
quick
max_allowed_packet = 1G
column-statistics=0

[mysql]
no-auto-rehash
default-character-set=utf8mb4

[isamchk]
key_buffer_size = 256M
sort_buffer_size = 256M
read_buffer_size = 24M
write_buffer_size = 24M

[myisamchk]
key_buffer_size = 256M
sort_buffer_size = 256M
read_buffer_size = 24M
write_buffer_size = 24M

sql_mode=only_full_group_by
EOF

    echo -e "${GREEN}✅ MySQL configuration files updated with optimized settings.${RESET}"
    echo

    # Restart and enable MySQL service
    run_step "Restarting MySQL service" sudo systemctl restart mysql
    run_step "Enabling MySQL service" sudo systemctl enable mysql

    echo -e "${YELLOW}📊 Checking MySQL service status...${RESET}"
    sudo systemctl status mysql --no-pager -l
    echo
}

# Setup MySQL firewall
setup_mysql_firewall() {
    echo -e "${YELLOW}🔥 Configuring firewall for MySQL (port 3306)...${RESET}"

    # Check if ufw is available
    if command -v ufw &> /dev/null; then
        run_step "Allowing MySQL port 3306 through ufw" sudo ufw allow 3306
        echo -e "${GREEN}✅ Firewall configured to allow MySQL connections.${RESET}"
    else
        echo -e "${BLUE}ℹ️  UFW firewall not found (common in WSL). Skipping firewall configuration.${RESET}"
        echo -e "${CYAN}💡 MySQL port 3306 is accessible by default in WSL environments.${RESET}"
    fi
    echo
}

# Show MySQL configuration summary
show_mysql_summary() {
    echo -e "${GREEN}✅ MySQL configuration completed successfully!${RESET}"
    echo -e "${CYAN}📋 MySQL Connection Details:${RESET}"
    echo -e "   🔹 Remote User: remote"
    echo -e "   🔹 Remote Password: admin"
    echo -e "   🔹 Root Password: admin"
    echo -e "   🔹 Port: 3306"
    echo
}

# Installation completion and system information
installation_completion() {
    section_header "🎉 SECTION 6: Installation Completion"
    echo -e "${GREEN}✅ Alias block added and loaded for user ${TARGET_USER}.${RESET}"
    echo

    echo -e "${CYAN}📋 Final system information:${RESET}"
    neofetch
    echo

    show_wsl_network_info

    echo -e "${GREEN}🚀 Your development environment is ready!${RESET}"
    echo -e "${YELLOW}💡 Type 'help_aliases' to see all available commands.${RESET}"
}

# Display WSL network information
show_wsl_network_info() {
    echo -e "${CYAN}🌐 WSL Network Information:${RESET}"
    echo -e "${YELLOW}📡 WSL IP Address (for MySQL connections):${RESET}"
    if command -v ip &> /dev/null; then
        WSL_IP=$(ip addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        if [ -n "$WSL_IP" ]; then
            echo -e "${GREEN}   🔗 IP: ${WSL_IP}${RESET}"
            echo -e "${BLUE}   💡 Use this IP to connect to MySQL from external applications${RESET}"
        else
            echo -e "${YELLOW}   ⚠️  Could not detect WSL IP address${RESET}"
            echo -e "${BLUE}   💡 Run 'ip addr show eth0' manually to get the IP${RESET}"
        fi
    else
        echo -e "${YELLOW}   ⚠️  'ip' command not available${RESET}"
        echo -e "${BLUE}   💡 Run 'ip addr show eth0' manually to get the IP${RESET}"
    fi
    echo
}

# Completion message for the "install tools only" flow
tools_install_completion() {
    section_header "🎉 Aliases y tools instalados"
    echo -e "${GREEN}✅ Listo para ${TARGET_USER}.${RESET}"
    echo -e "${YELLOW}💡 Abre una nueva terminal o ejecuta 'source ~/.bashrc' y luego 'help_aliases'.${RESET}"
}

# Completion message for the "update tools" flow
tools_update_completion() {
    section_header "🎉 Aliases y tools actualizados"
    echo -e "${GREEN}✅ Listo para ${TARGET_USER}.${RESET}"
    echo -e "${CYAN}💡 Abre una nueva terminal o ejecuta 'source ~/.bashrc' para aplicar los cambios.${RESET}"
}

# ===== MAIN EXECUTION FLOW =====

main() {
    # Display header and let the user pick a flow
    show_header
    select_mode

    case "$INSTALL_MODE" in
        full)
            system_update
            section_separator

            git_configuration
            section_separator

            user_selection
            section_separator

            deploy_tool_scripts
            section_separator

            configure_db_restore_credentials "install"
            section_separator

            write_alias_block
            section_separator

            xentro_environment_setup
            section_separator

            clone_xentro_repositories
            section_separator

            mysql_configuration
            section_separator

            installation_completion
            ;;

        install_tools)
            user_selection
            section_separator

            deploy_tool_scripts
            section_separator

            configure_db_restore_credentials "install"
            section_separator

            write_alias_block
            section_separator

            tools_install_completion
            ;;

        update_tools)
            user_selection
            section_separator

            deploy_tool_scripts
            section_separator

            configure_db_restore_credentials "update"
            section_separator

            write_alias_block
            section_separator

            tools_update_completion
            ;;
    esac
}

# Execute main function
main "$@"