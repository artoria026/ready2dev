#!/usr/bin/env bash
# ===============================================
# Ready2Dev - Shared library
# ===============================================
# Description: Functions shared by install.sh across its
#              "full install", "install tools" and "update tools"
#              modes. Sourced, never executed directly.
# ===============================================

# Repo root, resolved relative to this file so it works regardless of
# the caller's current directory (tools/lib/common.sh -> repo root).
_COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$_COMMON_LIB_DIR/../.." && pwd)"

# Colors, print_header() and run_step() come from the same file the deployed
# git_*.sh tool scripts use (tools/scripts/git_ui.sh), so install.sh's own
# output looks identical instead of duplicating the same helpers twice.
# shellcheck source=../scripts/git_ui.sh
source "$REPO_ROOT/tools/scripts/git_ui.sh"

# ===== Shared configuration =====
BLOCK_START="# >>> CUSTOM_ALIASES START"
BLOCK_END="# <<< CUSTOM_ALIASES END"
PYTHON_CMD="python3.12"

# ===== Global variables populated by user_selection() =====
TARGET_USER=""
TARGET_HOME=""
TARGET_SHELL=""

# SECTION: User Selection & Validation
user_selection() {
    echo -e "${MAGENTA}👤 User Selection & Validation${RESET}"
    echo -e "${BLUE}🔧 Searching for users with /home and bash shell...${RESET}"
    echo

    mapfile -t USERS < <(getent passwd | awk -F: '$6 ~ "^/home/" && $7 ~ /bash$/{print $1 ":" $6 ":" $7}' | sort)

    if getent passwd root >/dev/null 2>&1; then
      ROOT_HOME=$(getent passwd root | awk -F: '{print $6}')
      ROOT_SHELL=$(getent passwd root | awk -F: '{print $7}')
      USERS+=("root:${ROOT_HOME}:${ROOT_SHELL}")
    fi

    if [ ${#USERS[@]} -eq 0 ]; then
      echo -e "${RED}⛔ No login users found with /home and bash shell.${RESET}"
      exit 1
    fi

    echo -e "${CYAN}📋 Detected users:${RESET}"
    i=1
    for entry in "${USERS[@]}"; do
      IFS=":" read -r UNAME UHOME USHELL <<<"$entry"
      printf "  %2d) %-15s  home=%s  shell=%s\n" "$i" "$UNAME" "$UHOME" "$USHELL"
      ((i++))
    done
    echo

    read -rp "$(echo -e "${YELLOW}👉 Choose the user number to register the aliases: ${RESET}")" CHOICE
    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt ${#USERS[@]} ]; then
      echo -e "${RED}⛔ Invalid option.${RESET}"
      exit 1
    fi

    SELECTED="${USERS[$((CHOICE-1))]}"
    IFS=":" read -r TARGET_USER TARGET_HOME TARGET_SHELL <<<"$SELECTED"
    echo
    echo -e "${GREEN}✅ Selected user: ${TARGET_USER} (${TARGET_HOME})${RESET}"
    echo
}

# SECTION: Deploy / refresh tool scripts (tools/scripts + db_restore)
# Safe to call both on a fresh install (target dirs don't exist yet)
# and as an update (removes outdated scripts before copying new ones,
# so scripts renamed/removed upstream don't linger on the target).
deploy_tool_scripts() {
    echo -e "${MAGENTA}🛠️  Deploying tool scripts...${RESET}"
    echo -e "${BLUE}📍 Installation root: ${TARGET_HOME}/.local/share/ready2dev${RESET}"
    echo

    local READY2DEV_INSTALL_ROOT="${TARGET_HOME}/.local/share/ready2dev"
    TOOLS_DIR="${READY2DEV_INSTALL_ROOT}/tools/scripts"

    echo -e "${YELLOW}🗑️  Removing any existing deployment in ${TOOLS_DIR}...${RESET}"
    sudo rm -rf "${TOOLS_DIR:?}"
    echo

    echo -e "${BLUE}📁 Preparing tools directory...${RESET}"
    sudo mkdir -p "$TOOLS_DIR"
    echo

    echo -e "${YELLOW}📋 Copying tool scripts and documentation...${RESET}"
    sudo cp -r "$REPO_ROOT/tools/scripts/"* "$TOOLS_DIR/"
    sudo cp "$REPO_ROOT/tools/ALIAS_HELP.txt" "${READY2DEV_INSTALL_ROOT}/"
    echo

    echo -e "${YELLOW}🔐 Setting execution permissions for scripts...${RESET}"
    sudo chmod +x "$TOOLS_DIR"/*.sh
    echo

    echo -e "${YELLOW}👤 Setting file ownership to user ${TARGET_USER}...${RESET}"
    sudo chown -R "$TARGET_USER":"$TARGET_USER" "${READY2DEV_INSTALL_ROOT}"
    echo

    echo -e "${YELLOW}📋 Copying db_restore tool to ${READY2DEV_INSTALL_ROOT}/tools/db_restore/...${RESET}"
    DB_RESTORE_DEST="${READY2DEV_INSTALL_ROOT}/tools/db_restore"
    DB_RESTORE_SRC="$REPO_ROOT/tools/db_restore"
    sudo mkdir -p "$DB_RESTORE_DEST"
    # Remove everything currently there except .env (real credentials live
    # only there) before copying the current files, so files renamed/removed
    # upstream don't linger on the target.
    sudo find "$DB_RESTORE_DEST" -maxdepth 1 -type f ! -name ".env" -delete
    sudo find "$DB_RESTORE_SRC" -maxdepth 1 -type f ! -name ".env" \
        -exec sudo cp -f {} "$DB_RESTORE_DEST/" \;
    sudo chmod +x "$DB_RESTORE_DEST/restore_db.sh"
    sudo chown -R "$TARGET_USER":"$TARGET_USER" "$DB_RESTORE_DEST"
    echo

    echo -e "${GREEN}✅ Tool scripts deployed successfully.${RESET}"
    echo
}

# SECTION: MySQL credentials for db_restore
# mode="install" -> always prompts and writes .env (fresh setup)
# mode="update"  -> asks confirmation first, keeps existing .env if declined
configure_db_restore_credentials() {
    local mode="${1:-install}"
    local READY2DEV_INSTALL_ROOT="${TARGET_HOME}/.local/share/ready2dev"
    local DB_ENV_FILE="${READY2DEV_INSTALL_ROOT}/tools/db_restore/.env"

    echo -e "${MAGENTA}🗄️  MySQL Credentials for db_restore${RESET}"

    if [[ "$mode" == "update" ]]; then
        if ! confirm "🔐 ¿Deseas actualizar las credenciales de MySQL para db_restore?" "n"; then
            echo -e "${BLUE}ℹ️  Credenciales sin cambios.${RESET}"
            echo
            return 0
        fi
        echo
    fi

    echo -e "${YELLOW}🔐 Configuring MySQL credentials for the restore tool...${RESET}"
    echo

    read -rp "$(echo -e "${CYAN}  MySQL user [default: remote]: ${RESET}")" _MYSQL_USER
    _MYSQL_USER="${_MYSQL_USER:-remote}"

    read -rsp "$(echo -e "${CYAN}  MySQL password (leave empty to be prompted at runtime): ${RESET}")" _MYSQL_PASS
    echo

    read -rp "$(echo -e "${CYAN}  Backups directory [default: ${TARGET_HOME}/backups]: ${RESET}")" _BACKUPS_DIR
    _BACKUPS_DIR="${_BACKUPS_DIR:-${TARGET_HOME}/backups}"

    sudo tee "$DB_ENV_FILE" >/dev/null <<ENVEOF
# Credenciales de MySQL para restore_db.sh
# ──────────────────────────────────────────
MYSQL_USER=${_MYSQL_USER}
MYSQL_PASS=${_MYSQL_PASS}
BACKUPS_DIR=${_BACKUPS_DIR}
ENVEOF

    sudo mkdir -p "$_BACKUPS_DIR"
    sudo chown -R "$TARGET_USER":"$TARGET_USER" "$_BACKUPS_DIR"
    sudo chown "$TARGET_USER":"$TARGET_USER" "$DB_ENV_FILE"
    echo -e "${GREEN}✅ MySQL credentials saved to ${DB_ENV_FILE}${RESET}"
    echo -e "${GREEN}✅ Backups folder ready: ${_BACKUPS_DIR}${RESET}"
    echo
}

# SECTION: Alias block in ~/.bashrc (single source of truth)
write_alias_block() {
    echo -e "${MAGENTA}⚙️  Refreshing alias block in ~/.bashrc...${RESET}"
    echo -e "${BLUE}🔁 Updating aliases to use: ${TARGET_HOME}/.local/share/ready2dev${RESET}"
    echo

    local READY2DEV_INSTALL_ROOT="${TARGET_HOME}/.local/share/ready2dev"
    BASHRC="${TARGET_HOME}/.bashrc"
    BACKUP="${BASHRC}.$(date +%Y%m%d_%H%M%S).bak"

    echo -e "${BLUE}📄 Target file: ${BASHRC}${RESET}"
    sudo touch "$BASHRC"
    echo

    echo -e "${YELLOW}🗄️ Creating backup: ${BACKUP}${RESET}"
    sudo cp -a "$BASHRC" "$BACKUP" 2>/dev/null || true
    echo

    if sudo grep -qF "$BLOCK_START" "$BASHRC" 2>/dev/null; then
      echo -e "${YELLOW}🧽 Found previous alias block(s), removing to avoid duplicates...${RESET}"
      # Exact-line comparison (awk "==", no regex) instead of a sed range
      # pattern: BLOCK_START/BLOCK_END contain ">>>"/"<<<", and GNU sed's BRE
      # reads "\>"/"\<" as word-boundary anchors rather than literal
      # characters, so a sed-based delete here silently matches nothing.
      # This also strips every existing block, not just the first, so any
      # duplicates left over from that bug get cleaned up too.
      #
      # The temp file lives next to .bashrc itself (not /tmp via mktemp):
      # mktemp would create it as the current unprivileged user, and on some
      # WSL setups `sudo tee` writing into a file it doesn't already own can
      # fail with "Permission denied" even though sudo is root. Writing a
      # brand-new file with `sudo tee` from the start, on the same
      # filesystem we already know is writable via sudo, avoids that.
      local _cleaned_bashrc="${BASHRC}.cleaning.$$"
      sudo awk -v start="$BLOCK_START" -v end="$BLOCK_END" '
          $0 == start { skip = 1; next }
          skip { if ($0 == end) skip = 0; next }
          { print }
      ' "$BASHRC" | sudo tee "$_cleaned_bashrc" >/dev/null
      sudo mv "$_cleaned_bashrc" "$BASHRC"
      echo
    fi

    echo -e "${YELLOW}✍️  Adding alias block to the end of ${BASHRC}...${RESET}"

    # NOTA: heredoc sin comillas para que se expandan ${TARGET_HOME} y ${PYTHON_CMD}
    sudo tee -a "$BASHRC" >/dev/null <<EOF

$BLOCK_START
# ------------------------------------- Custom Alias for Local Development Environment ------------------------------------ #
# System
alias sys_perms="stat -c '%a %n' *"
alias sys_killport="fuser -n tcp -k"
alias sys_bash_edit="sudo nano ~/.bashrc && source ~/.bashrc"
alias sys_bash_reload="source ~/.bashrc"
alias help_aliases="cat ${READY2DEV_INSTALL_ROOT}/ALIAS_HELP.txt"

# Docker
alias docker_ps="${READY2DEV_INSTALL_ROOT}/tools/scripts/docker_ps.sh"

# Git
alias g_push="${READY2DEV_INSTALL_ROOT}/tools/scripts/git_push.sh"
alias g_branch_new="${READY2DEV_INSTALL_ROOT}/tools/scripts/git_create_new_remote_branch.sh"
alias g_rebase="${READY2DEV_INSTALL_ROOT}/tools/scripts/git_interactive_rebase.sh"
alias g_reset="${READY2DEV_INSTALL_ROOT}/tools/scripts/git_reset_to.sh"

# Django
alias dj="${PYTHON_CMD} manage.py"
alias dj_missing_migrations="clear && ${PYTHON_CMD} manage.py showmigrations | grep '\\[ \\]\\|^[a-z]' | grep '\\[ \\]' -B 1"

# Xentro
alias open_xentro_nac="cd ${TARGET_HOME}/projects/msc/xentro_nac && source ../entornoXentro/bin/activate"
alias open_xentro_llc="cd ${TARGET_HOME}/projects/msc/xentro_llc && source ../entornoXentro/bin/activate"
alias run_xentro_nac="clear && cd ${TARGET_HOME}/projects/msc/xentro_nac && source ../entornoXentro/bin/activate && ${PYTHON_CMD} manage.py runserver"
alias run_xentro_llc="clear && cd ${TARGET_HOME}/projects/msc/xentro_llc && source ../entornoXentro/bin/activate && ${PYTHON_CMD} manage.py runserver 8080"

# Fenrir
alias open_fenrir="cd ${TARGET_HOME}/projects/msc/fenrir"
alias run_fenrir="clear && cd ${TARGET_HOME}/projects/msc/fenrir && npm run dev"

# MRP
alias open_mrp="cd ${TARGET_HOME}/projects/webapps/mrp"
alias run_mrp="clear && cd ${TARGET_HOME}/projects/webapps/mrp && sudo docker compose -f docker-compose.local.yml -p mrp down && sudo docker compose -f docker-compose.local.yml -p mrp build && sudo docker compose -f docker-compose.local.yml -p mrp up -d --force-recreate && sudo docker compose -f docker-compose.local.yml -p mrp ps"

# CRM
alias open_crm="cd ${TARGET_HOME}/projects/webapps/crm"
alias run_crm="clear && cd ${TARGET_HOME}/projects/webapps/crm && sudo docker compose -f docker-compose.local.yml -p crm down && sudo docker compose -f docker-compose.local.yml -p crm build && sudo docker compose -f docker-compose.local.yml -p crm up -d --force-recreate && sudo docker compose -f docker-compose.local.yml -p crm ps"

# Database Restore
alias db_restore="${READY2DEV_INSTALL_ROOT}/tools/db_restore/restore_db.sh"
$BLOCK_END
EOF

    sudo chown "$TARGET_USER":"$TARGET_USER" "$BASHRC" "$BACKUP" 2>/dev/null || true

    echo -e "${YELLOW}🔄 Reloading ~/.bashrc...${RESET}"
    sudo -u "$TARGET_USER" bash -lc "source ~/.bashrc"

    echo -e "${GREEN}✅ Alias block updated successfully.${RESET}"
    echo
}
