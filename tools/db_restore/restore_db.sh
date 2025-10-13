#!/bin/bash
set -eo pipefail

# Shared is_yes()/is_no()/confirm() helpers (tools/scripts/git_ui.sh) - same
# module the git_*.sh tool scripts and install.sh use, so every yes/no
# prompt in the project accepts the same input. Sourced this early because
# check_dependencies() below (called before this script does anything else)
# already needs is_no().
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/git_ui.sh
source "$SCRIPT_DIR/../scripts/git_ui.sh"

# --- Verificación e Instalación de Dependencias ---
check_dependencies() {
    local dependencies=("mysql" "tar" "numfmt")
    local missing_deps=()

    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo ""
        echo "❌   Faltan las siguientes dependencias: ${missing_deps[*]}"
        echo ""
        if command -v apt-get &>/dev/null; then
            if confirm "  ¿Instalar automáticamente con apt-get?" "y"; then
                sudo apt-get install -y default-mysql-client tar coreutils || {
                    echo "❌   No se pudieron instalar las dependencias."; exit 1
                }
            else
                exit 1
            fi
        elif command -v yum &>/dev/null; then
            confirm "  ¿Instalar automáticamente con yum?" "y" && sudo yum install -y mysql tar coreutils || exit 1
        else
            echo "  Instálalas manualmente:"
            for dep in "${missing_deps[@]}"; do echo "    - $dep"; done
            exit 1
        fi
    fi

    # Verificar / auto-instalar gdown (necesario para descargas de Google Drive)
    if ! command -v gdown &>/dev/null; then
        local _g=""

        # 1. Buscar en ubicaciones comunes
        for _d in "$HOME/.local/bin" "$HOME/bin" "/usr/local/bin" "/usr/bin"; do
            [ -x "$_d/gdown" ] && { _g="$_d/gdown"; break; }
        done

        # 2. Buscar junto al pip3 activo → mismo entorno virtual (ej: entornoXentro/bin/)
        if [ -z "$_g" ] && command -v pip3 &>/dev/null; then
            local _c="$(dirname "$(command -v pip3)")/gdown"
            [ -x "$_c" ] && _g="$_c"
        fi

        # 3. Búsqueda amplia en $HOME (virtualenvs en cualquier subruta)
        if [ -z "$_g" ]; then
            _g=$(find "$HOME" -maxdepth 6 -name "gdown" -type f -executable 2>/dev/null | head -1)
        fi

        if [ -n "$_g" ]; then
            echo "  ✔   gdown encontrado: $_g"
        else
            local _pip
            _pip=$(command -v pip3 2>/dev/null || command -v pip 2>/dev/null || echo "")
            if [ -n "$_pip" ]; then
                echo "  ℹ️   Instalando gdown..."
                # Intentar --user (no requiere sudo y no rompe el sistema)
                if "$_pip" install --user gdown -q 2>/dev/null; then
                    _g=$(command -v gdown 2>/dev/null || echo "$HOME/.local/bin/gdown")
                    echo "  ✔   gdown instalado en: $_g"
                elif command -v pipx &>/dev/null && pipx install gdown --quiet 2>/dev/null; then
                    _g=$(command -v gdown 2>/dev/null)
                    echo "  ✔   gdown instalado con pipx."
                else
                    echo "  ⚠️   Instalación normal fallida. Intentando con --break-system-packages..."
                    if "$_pip" install gdown -q --break-system-packages 2>/dev/null; then
                        _g=$(command -v gdown 2>/dev/null || echo "$HOME/.local/bin/gdown")
                        echo "  ✔   gdown instalado."
                    else
                        echo "  ⚠️   No se pudo instalar gdown."
                        echo "       Activa tu entorno virtual antes de ejecutar: source /ruta/al/venv/bin/activate"
                    fi
                fi
            else
                echo "  ⚠️   pip no disponible. Instala gdown: pip3 install gdown"
            fi
        fi

        [ -n "$_g" ] && export GDOWN_BIN="$_g" || export GDOWN_BIN=""
    else
        export GDOWN_BIN="$(command -v gdown)"
    fi
}

check_dependencies

# --- Carga de configuración (.env) ---
ENV_FILE="$SCRIPT_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    env_perms=$(stat -c "%a" "$ENV_FILE" 2>/dev/null || echo "unknown")
    if [[ "$env_perms" != "600" && "$env_perms" != "400" && "$env_perms" != "unknown" ]]; then
        echo "⚠️   Advertencia: $ENV_FILE tiene permisos inseguros ($env_perms). Ejecuta: chmod 600 \"$ENV_FILE\""
    fi
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi

# --- Colores y Estilos ---
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
GREEN='\033[32m'
RED='\033[31m'
CYAN='\033[36m'
YELLOW='\033[33m'
BLUE='\033[34m'

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}┌──────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BOLD}${CYAN}│${RESET}  ${BOLD}$1${RESET}"
    echo -e "${BOLD}${CYAN}└──────────────────────────────────────────────────────────┘${RESET}"
    echo ""
}

# --- Carpeta de backups ---
# Puede sobreescribirse en .env con una ruta absoluta o relativa al script.
# Default: ~/backups  (se crea automáticamente si no existe).
BACKUPS_DIR="${BACKUPS_DIR:-$HOME/backups}"
if [[ "$BACKUPS_DIR" != /* ]]; then
    BACKUPS_DIR="$SCRIPT_DIR/$BACKUPS_DIR"
fi
mkdir -p "$BACKUPS_DIR"

# --- Funciones Principales ---
usage() {
  echo "Uso:"
  echo "  Restaurar y/u optimizar: $0 [OPCIONES] <archivo_backup.sql o .tar.gz> <nombre_base_datos>"
  echo "  Solo optimizar: $0 -o <nombre_base_datos>"
  echo ""
  echo "Opciones:"
  echo "  -r, --restore-only      Ejecuta solamente el proceso de restauración."
  echo "  -o, --optimize-only     Ejecuta solamente el proceso de optimización."
  echo "  -h, --help              Muestra esta ayuda y sale."
}

# is_yes()/is_no()/confirm() come from git_ui.sh (sourced at the top of
# this file) - same helpers used by install.sh and the git_*.sh scripts.

# --- Menú Interactivo ---

# Limpia pantalla y muestra el progreso de selecciones realizadas hasta el momento
print_step_header() {
    clear
    print_header "🗄️   Ready2Dev — Database Manager"
    local _any=false
    if [ -n "${_ACTION_LABEL:-}" ]; then
        echo -e "  ${DIM}Acción:${RESET}   ${BOLD}$_ACTION_LABEL${RESET}"
        _any=true
    fi
    if ${PAIRED_RESTORE:-false}; then
        [ -n "${BACKUP_FILE_LLC:-}" ] && \
            echo -e "  ${DIM}Backup LLC:${RESET} ${BOLD}$(basename "$BACKUP_FILE_LLC")${RESET}"
        [ -n "${BACKUP_FILE_NAC:-}" ] && \
            echo -e "  ${DIM}Backup NAC:${RESET} ${BOLD}$(basename "$BACKUP_FILE_NAC")${RESET}"
        echo -e "  ${DIM}Bases:${RESET}    ${BOLD}${XENTRO_NAME_LLC:-xentro_llc} → ${XENTRO_NAME_NAC:-xentro_nac}${RESET}"
        _any=true
    else
        if [ -n "${BACKUP_FILE:-}" ]; then
            echo -e "  ${DIM}Backup:${RESET}   ${BOLD}$(basename "$BACKUP_FILE")${RESET}"
            _any=true
        fi
        if [ -n "${DATABASE_NAME:-}" ]; then
            echo -e "  ${DIM}Database:${RESET} ${BOLD}$DATABASE_NAME${RESET}"
            _any=true
        fi
    fi
    $_any && echo -e "${DIM}──────────────────────────────────────────────────────────────${RESET}"
    echo ""
    # Mostrar resúmenes de BDs ya completadas en esta sesión
    if [ "${#_COMPLETED_DB_SUMMARIES[@]}" -gt 0 ] 2>/dev/null; then
        for _cds in "${_COMPLETED_DB_SUMMARIES[@]}"; do
            echo -e "$_cds"
        done
        echo -e "${DIM}──────────────────────────────────────────────────────────────${RESET}"
        echo ""
    fi
    if [ -n "${_CURRENT_DB:-}" ]; then
        echo -e "  ${CYAN}${BOLD}➤   Restaurando: ${_CURRENT_DB}${RESET}"
        echo ""
    fi
}

# Detecta el nombre de la BD a partir del nombre del archivo de backup.
# Mapeos: xentro_nacional_* → xentro_nac | xentro_llc_* → xentro_llc | fenrir_* → fenrir | *_inhouse_* → nombre completo
detect_db_name() {
    local _f
    _f=$(basename "$1")
    _f="${_f%.tar.gz}"; _f="${_f%.sql.gz}"; _f="${_f%.sql}"
    # Quitar sufijo de fecha _YYYYMMDD o _YYYYMMDD_HHMMSS
    _f=$(echo "$_f" | sed -E 's/_[0-9]{8}(_[0-9]{6})?$//')
    case "$_f" in
        xentro_nacional*|xentro_nac*) echo "xentro_nac" ;;
        xentro_llc*)                  echo "xentro_llc" ;;
        fenrir*)                      echo "fenrir"      ;;
        *)                            echo "$_f"         ;;
    esac
}

# Retorna el default de optimización para una BD: "yes" o "no"
get_optimization_default() {
    case "$1" in
        xentro_nac|xentro_llc) echo "yes" ;;
        *)                     echo "no"  ;;
    esac
}

# Selección del archivo de backup (carpeta predefinida o ruta manual)
select_backup_file() {
    print_step_header
    if [ -n "${_SECOND_BACKUP_FOR:-}" ]; then
        echo -e "  ${YELLOW}${BOLD}Restauración encadenada${RESET} — selecciona el backup de ${CYAN}${BOLD}$_SECOND_BACKUP_FOR${RESET}"
        echo ""
    fi
    echo -e "  ${BOLD}¿Desde dónde tomar el backup?${RESET}"
    echo ""
    echo -e "   ${CYAN}1)${RESET} Carpeta de backups  ${DIM}($BACKUPS_DIR)${RESET}"
    echo -e "   ${CYAN}2)${RESET} Especificar ruta manualmente"
    echo -e "   ${CYAN}3)${RESET} Descargar desde Google Drive (URL)"
    echo ""
    read -rp "  👉   Elige: " _src

    case "$_src" in
        1)
            if [ ! -d "$BACKUPS_DIR" ]; then
                echo -e "\n  ${RED}✖ La carpeta no existe: $BACKUPS_DIR${RESET}"
                echo -e "  ${DIM}Créala o ajusta BACKUPS_DIR en .env${RESET}\n"
                exit 1
            fi
            mapfile -t _BFILES < <(find "$BACKUPS_DIR" -maxdepth 1 -type f \
                \( -name "*.sql" -o -name "*.tar.gz" -o -name "*.sql.gz" \) | sort)
            if [ ${#_BFILES[@]} -eq 0 ]; then
                echo -e "\n  ${RED}✖ No hay archivos de backup en $BACKUPS_DIR${RESET}\n"
                exit 1
            fi
            echo ""
            echo -e "  ${BOLD}Archivos disponibles:${RESET}"
            echo ""
            for i in "${!_BFILES[@]}"; do
                local _sz _szh
                _sz=$(stat -c%s "${_BFILES[$i]}" 2>/dev/null || echo "0")
                _szh=$(numfmt --to=iec "$_sz" 2>/dev/null || echo "${_sz}B")
                printf "   ${CYAN}%2d)${RESET} %-50s ${DIM}%s${RESET}\n" \
                    "$((i+1))" "$(basename "${_BFILES[$i]}")" "$_szh"
            done
            echo ""
            read -rp "  👉   Elige un archivo: " _fc
            if ! [[ "$_fc" =~ ^[0-9]+$ ]] || \
               [ "$_fc" -lt 1 ] || [ "$_fc" -gt "${#_BFILES[@]}" ]; then
                echo -e "\n  ${RED}✖ Opción inválida${RESET}\n"; exit 1
            fi
            BACKUP_FILE="${_BFILES[$((_fc-1))]}"
            ;;
        2)
            echo ""
            read -rp "  📂   Ruta del archivo de backup: " BACKUP_FILE
            if [ ! -f "$BACKUP_FILE" ]; then
                echo -e "\n  ${RED}✖ El archivo no existe: $BACKUP_FILE${RESET}\n"; exit 1
            fi
            ;;
        3)
            collect_and_download_gdrive
            return
            ;;
        *)
            echo -e "\n  ${RED}✖ Opción inválida${RESET}\n"; exit 1 ;;
    esac
    echo ""
    echo -e "  ${DIM}Seleccionado:${RESET} ${BOLD}$(basename "$BACKUP_FILE")${RESET}"
}

# Selección / confirmación del nombre de la base de datos
select_database_name() {
    local _det=""
    if [ -n "${BACKUP_FILE:-}" ]; then
        _det=$(detect_db_name "$BACKUP_FILE")
    fi
    print_step_header
    if [ -n "$_det" ]; then
        echo -e "  ${BOLD}Base de datos detectada del archivo:${RESET} ${CYAN}$_det${RESET}"
        echo ""
        echo -e "   ${CYAN}1)${RESET} Usar  ${BOLD}$_det${RESET}"
        echo -e "   ${CYAN}2)${RESET} Especificar otro nombre"
        echo ""
        read -rp "  👉   Elige: " _dbc
        case "${_dbc:-1}" in
            1) DATABASE_NAME="$_det" ;;
            2) echo ""; read -rp "  📝   Nombre de la base de datos: " DATABASE_NAME ;;
            *) echo -e "\n  ${RED}✖ Opción inválida${RESET}\n"; exit 1 ;;
        esac
    else
        local _KNOWN=("xentro_nac" "xentro_llc" "fenrir")
        echo -e "  ${BOLD}Selecciona la base de datos destino:${RESET}"
        echo ""
        for i in "${!_KNOWN[@]}"; do
            printf "   ${CYAN}%d)${RESET} %s\n" "$((i+1))" "${_KNOWN[$i]}"
        done
        printf "   ${CYAN}%d)${RESET} Especificar nombre\n" "$((${#_KNOWN[@]}+1))"
        echo ""
        read -rp "  👉   Elige: " _dbc
        if [[ "$_dbc" =~ ^[0-9]+$ ]] && \
           [ "$_dbc" -ge 1 ] && [ "$_dbc" -le "${#_KNOWN[@]}" ]; then
            DATABASE_NAME="${_KNOWN[$((_dbc-1))]}"
        elif [[ "$_dbc" =~ ^[0-9]+$ ]] && [ "$_dbc" -eq "$((${#_KNOWN[@]}+1))" ]; then
            echo ""; read -rp "  📝   Nombre de la base de datos: " DATABASE_NAME
        else
            echo -e "\n  ${RED}✖ Opción inválida${RESET}\n"; exit 1
        fi
    fi
    if [[ ! "$DATABASE_NAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "\n  ${RED}✖ Nombre inválido '${DATABASE_NAME}': solo letras, números y guión bajo.${RESET}\n"
        exit 1
    fi
    if ${restore:-false} && [[ "$DATABASE_NAME" == "xentro_nac" || "$DATABASE_NAME" == "xentro_llc" ]]; then
        PAIRED_RESTORE=true
        XENTRO_NAME_LLC="xentro_llc"
        XENTRO_NAME_NAC="xentro_nac"
    else
        PAIRED_RESTORE=false
    fi
}

# Confirmación de optimización con default según la BD seleccionada
confirm_optimization() {
    local _def
    _def=$(get_optimization_default "$DATABASE_NAME")
    print_step_header
    if [ "$_def" = "yes" ]; then
        confirm "  ⚡   ¿Ejecutar optimización SQL?" "y" && optimize=true || optimize=false
    else
        confirm "  ⚡   ¿Ejecutar optimización SQL?" "n" && optimize=true || optimize=false
    fi
}

# Confirmación de limpieza de archivos de backup tras la restauración
confirm_cleanup() {
    CLEANUP_AFTER=false
    print_step_header
    if confirm "  🗑️   ¿Eliminar el archivo de backup al terminar?" "n"; then CLEANUP_AFTER=true; fi
}

# Solicita el backup de la BD complementaria cuando se detecta restauración encadenada
# (xentro_llc y xentro_nac siempre se restauran juntas: primero llc, luego nac)
select_second_paired_backup() {
    local _complement _saved
    if [[ "$DATABASE_NAME" == "xentro_llc" ]]; then
        _complement="xentro_nac"
        BACKUP_FILE_LLC="$BACKUP_FILE"
    else
        _complement="xentro_llc"
        BACKUP_FILE_NAC="$BACKUP_FILE"
    fi
    _saved="$BACKUP_FILE"
    _SECOND_BACKUP_FOR="$_complement"
    select_backup_file
    _SECOND_BACKUP_FOR=""
    if [[ "$DATABASE_NAME" == "xentro_llc" ]]; then
        BACKUP_FILE_NAC="$BACKUP_FILE"
    else
        BACKUP_FILE_LLC="$BACKUP_FILE"
    fi
    BACKUP_FILE="$_saved"
}

# Busca en BACKUPS_DIR el backup de la BD xentro indicada.
# $1 = nombre de la BD (ej: "xentro_llc"). Establece _XENTRO_FOUND_FILE con la ruta.
find_xentro_backup() {
    local _label="$1"
    local _files=()
    _XENTRO_FOUND_FILE=""

    if [ -d "$BACKUPS_DIR" ]; then
        mapfile -t _files < <(find "$BACKUPS_DIR" -maxdepth 1 -type f \
            \( -name "*.sql" -o -name "*.tar.gz" -o -name "*.sql.gz" \) \
            | grep -i "$_label" | sort -r)
    fi

    if [ ${#_files[@]} -eq 0 ]; then
        echo -e "  ${YELLOW}⚠️   No se encontró backup de ${BOLD}$_label${RESET}${YELLOW} en $BACKUPS_DIR${RESET}"
        echo ""
        read -rp "  📂   Ruta del backup de $_label: " _xm
        if [ ! -f "$_xm" ]; then
            echo -e "\n  ${RED}✖ El archivo no existe: $_xm${RESET}\n"; exit 1
        fi
        _XENTRO_FOUND_FILE="$_xm"
    elif [ ${#_files[@]} -eq 1 ]; then
        local _sz _szh
        _sz=$(stat -c%s "${_files[0]}" 2>/dev/null || echo 0)
        _szh=$(numfmt --to=iec "$_sz" 2>/dev/null || echo "${_sz}B")
        echo -e "  ${GREEN}✔${RESET}  ${DIM}$_label:${RESET} ${BOLD}$(basename "${_files[0]}")${RESET} ${DIM}($_szh)${RESET}"
        _XENTRO_FOUND_FILE="${_files[0]}"
    else
        echo -e "  ${BOLD}Selecciona el backup de $_label:${RESET}"
        echo ""
        for i in "${!_files[@]}"; do
            local _sz _szh
            _sz=$(stat -c%s "${_files[$i]}" 2>/dev/null || echo 0)
            _szh=$(numfmt --to=iec "$_sz" 2>/dev/null || echo "${_sz}B")
            printf "   ${CYAN}%2d)${RESET} %-50s ${DIM}%s${RESET}\n" \
                "$((i+1))" "$(basename "${_files[$i]}")" "$_szh"
        done
        echo ""
        read -rp "  👉   Elige: " _xfc
        if ! [[ "$_xfc" =~ ^[0-9]+$ ]] || \
           [ "$_xfc" -lt 1 ] || [ "$_xfc" -gt "${#_files[@]}" ]; then
            echo -e "\n  ${RED}✖ Opción inválida${RESET}\n"; exit 1
        fi
        _XENTRO_FOUND_FILE="${_files[$((_xfc-1))]}"
    fi
}

# Flujo dedicado para restaurar las bases de datos de Xentro (llc + nac en cadena)
xentro_restore_menu() {
    restore=true
    PAIRED_RESTORE=true
    _ACTION_LABEL="Restaurar bases de Xentro"

    # --- Búsqueda automática de backups ---
    print_step_header
    echo -e "  ${BOLD}Restauración en cadena:${RESET} xentro_llc → xentro_nac"
    echo -e "  ${DIM}Buscando backups en:${RESET} $BACKUPS_DIR"
    echo ""

    _XENTRO_FOUND_FILE=""
    find_xentro_backup "xentro_llc"
    BACKUP_FILE_LLC="$_XENTRO_FOUND_FILE"

    find_xentro_backup "xentro_nac"
    BACKUP_FILE_NAC="$_XENTRO_FOUND_FILE"

    echo ""

    # --- Nombres de las bases de datos ---
    print_step_header
    echo -e "  ${BOLD}Nombres de las bases de datos:${RESET}"
    echo ""
    echo -e "   ${DIM}LLC:${RESET} ${BOLD}xentro_llc${RESET}"
    echo -e "   ${DIM}NAC:${RESET} ${BOLD}xentro_nac${RESET}"
    echo ""
    if ! confirm "  👉   ¿Mantener estos nombres?" "y"; then
        echo ""
        read -rp "  📝   Nombre para la BD de LLC: " XENTRO_NAME_LLC
        read -rp "  📝   Nombre para la BD de NAC: " XENTRO_NAME_NAC
        if [[ ! "$XENTRO_NAME_LLC" =~ ^[a-zA-Z0-9_]+$ ]] || \
           [[ ! "$XENTRO_NAME_NAC" =~ ^[a-zA-Z0-9_]+$ ]]; then
            echo -e "\n  ${RED}✖ Nombres inválidos: solo letras, números y guión bajo.${RESET}\n"
            exit 1
        fi
    else
        XENTRO_NAME_LLC="xentro_llc"
        XENTRO_NAME_NAC="xentro_nac"
    fi
    DATABASE_NAME="$XENTRO_NAME_NAC"

    # --- Optimización (default: sí) ---
    print_step_header
    confirm "  ⚡   ¿Ejecutar optimización SQL también?" "y" && optimize=true || optimize=false

    # --- Limpieza ---
    confirm_cleanup
}

# --- Descarga desde Google Drive ---

# Extrae el file ID de los formatos más comunes de URL de Google Drive
extract_gdrive_id() {
    local _url="$1" _id
    _id=$(echo "$_url" | grep -oP '(?<=/d/)[^/?&]+')
    [ -n "$_id" ] && { echo "$_id"; return; }
    _id=$(echo "$_url" | grep -oP '(?<=id=)[^&?]+')
    [ -n "$_id" ] && { echo "$_id"; return; }
    echo ""
}

# Detecta el tipo real del archivo descargado y lo renombra con la extensión correcta
normalize_downloaded_file() {
    local _file="$1" _ext=""
    if command -v file &>/dev/null; then
        local _mime
        _mime=$(file -b --mime-type "$_file" 2>/dev/null)
        case "$_mime" in
            application/gzip|application/x-gzip)
                tar -tzf "$_file" &>/dev/null 2>&1 && _ext="tar.gz" || _ext="sql.gz" ;;
            text/plain|text/x-sql|application/sql)
                _ext="sql" ;;
        esac
    fi
    # Fallback por magic bytes si 'file' no está disponible
    if [ -z "$_ext" ]; then
        local _magic
        _magic=$(od -An -tu1 -N2 "$_file" 2>/dev/null | tr -s ' ' | sed 's/^ //')
        if [[ "$_magic" == "31 139" ]]; then
            tar -tzf "$_file" &>/dev/null 2>&1 && _ext="tar.gz" || _ext="sql.gz"
        else
            _ext="sql"
        fi
    fi
    local _base="${_file%.*}" _newfile
    # Preservar doble extensión si ya tiene una
    [[ "$_file" == *.tar.gz ]] && _base="${_file%.tar.gz}"
    _newfile="${_base}.${_ext}"
    if [ "$_newfile" != "$_file" ]; then
        mv "$_file" "$_newfile" 2>/dev/null && echo "$_newfile" || echo "$_file"
    else
        echo "$_file"
    fi
}

# Descarga un archivo de Google Drive (por ID) al directorio destino.
# Resultado en la variable global _GDRIVE_OUT (ruta final). Retorna 1 en error.
download_gdrive_file() {
    local _id="$1" _dest="$2" _out="$_dest/gdrive_${_id}"
    _GDRIVE_OUT=""

    if command -v gdown &>/dev/null || [ -n "${GDOWN_BIN:-}" ]; then
        local _gdown="${GDOWN_BIN:-$(command -v gdown)}"
        if ! "$_gdown" "https://drive.google.com/uc?id=$_id" -O "$_out"; then
            echo -e "  ${RED}✖ gdown no pudo descargar el archivo.${RESET}" >&2
            echo -e "  ${DIM}Verifica que el archivo sea público o actualiza: pip3 install -U gdown${RESET}" >&2
            rm -f "$_out"
            return 1
        fi
    elif command -v curl &>/dev/null; then
        local _cookie _warn _confirm
        _cookie=$(mktemp) _warn=$(mktemp)
        curl -sc "$_cookie" \
             "https://drive.google.com/uc?export=download&id=$_id" \
             -L -o "$_warn" 2>/dev/null
        _confirm=$(grep -oP '(?<=confirm=)[^"&]+' "$_warn" 2>/dev/null | head -1)
        if [ -n "$_confirm" ]; then
            curl -Lb "$_cookie" \
                 "https://drive.google.com/uc?export=download&confirm=$_confirm&id=$_id" \
                 -o "$_out" -L --progress-bar
        else
            curl -L "https://drive.google.com/uc?export=download&id=$_id" \
                 -o "$_out" --progress-bar
        fi
        rm -f "$_cookie" "$_warn"
    else
        echo -e "  ${RED}✖ Se requiere 'gdown' o 'curl'. Instala gdown con: pip3 install gdown${RESET}" >&2
        return 1
    fi

    if [ ! -s "$_out" ]; then
        echo -e "  ${RED}✖ El archivo descargado está vacío o no existe.${RESET}" >&2
        rm -f "$_out"
        return 1
    fi

    # Detectar tipo real por magic bytes y renombrar con extensión correcta
    local _magic _ext
    _magic=$(od -An -tx1 -N2 "$_out" 2>/dev/null | tr -d ' \n')
    if [[ "$_magic" == "1f8b" ]]; then
        # Gzip: determinar si es tar.gz o sql.gz buscando magic 'ustar' en los primeros bytes
        if (set +o pipefail; gzip -dc "$_out" 2>/dev/null | head -c 300 | grep -q 'ustar'); then
            _ext="tar.gz"
        else
            _ext="sql.gz"
        fi
    else
        _ext="sql"
    fi
    mv "$_out" "${_out}.${_ext}" 2>/dev/null && _out="${_out}.${_ext}" || true

    _GDRIVE_OUT="$_out"
}

# Recolecta URLs de Google Drive en bucle, descarga todos y selecciona el archivo
collect_and_download_gdrive() {
    local _ids=()
    print_step_header
    echo -e "  ${BOLD}Agrega las URLs de Google Drive a descargar${RESET}"
    echo -e "  ${DIM}Formatos: /file/d/ID/view  ·  ?id=ID  ·  uc?id=ID${RESET}"
    echo -e "  ${DIM}Deja en blanco y presiona Enter para comenzar la descarga.${RESET}"
    echo ""

    local _i=1
    while true; do
        read -rp "  URL $_i: " _url
        [[ -z "$_url" ]] && break

        if ! echo "$_url" | grep -qiE 'drive\.google\.com|docs\.google\.com'; then
            if ! confirm "  ⚠️   No parece URL de Google Drive. ¿Agregar de todas formas?" "n"; then continue; fi
        fi

        local _id
        _id=$(extract_gdrive_id "$_url")
        if [ -z "$_id" ]; then
            echo -e "  ${RED}✖ No se pudo extraer el ID de la URL.${RESET}"
            continue
        fi

        _ids+=("$_id")
        echo -e "  ${GREEN}✔${RESET} Agregada  ${DIM}(ID: $_id)${RESET}"
        _i=$((_i+1))
    done

    if [ ${#_ids[@]} -eq 0 ]; then
        echo -e "\n  ${YELLOW}No se ingresaron URLs. Volviendo a la selección de origen.${RESET}\n"
        select_backup_file
        return
    fi

    local _dldir="${BACKUPS_DIR:-$HOME/backups}"
    mkdir -p "$_dldir"
    echo ""
    echo -e "  ${BOLD}Descargando ${#_ids[@]} archivo(s)…${RESET}"
    echo ""

    local _downloaded=() _failed=0
    for _id in "${_ids[@]}"; do
        echo -e "  ${CYAN}⬇${RESET}   ID: ${BOLD}$_id${RESET}"
        _GDRIVE_OUT=""
        if download_gdrive_file "$_id" "$_dldir"; then
            local _sz
            _sz=$(numfmt --to=iec "$(stat -c%s "$_GDRIVE_OUT" 2>/dev/null || echo 0)" 2>/dev/null)
            echo -e "  ${GREEN}✔   Descargado:${RESET} ${BOLD}$(basename "$_GDRIVE_OUT")${RESET} ${DIM}(≈$_sz)${RESET}"
            _downloaded+=("$_GDRIVE_OUT")
        else
            echo -e "  ${RED}✖ Falló la descarga del ID: $_id${RESET}"
            _failed=$((_failed+1))
        fi
    done

    echo ""
    [ $_failed -gt 0 ] && echo -e "  ${YELLOW}⚠️   $_failed descarga(s) fallida(s)${RESET}"

    if [ ${#_downloaded[@]} -eq 0 ]; then
        echo -e "  ${RED}✖ No se descargó ningún archivo.${RESET}\n"; exit 1
    fi

    if [ ${#_downloaded[@]} -eq 1 ]; then
        BACKUP_FILE="${_downloaded[0]}"
        echo -e "  ${GREEN}✔${RESET} Usando: ${BOLD}$(basename "$BACKUP_FILE")${RESET}"
    else
        echo -e "  ${BOLD}Selecciona el archivo a restaurar:${RESET}"
        echo ""
        for i in "${!_downloaded[@]}"; do
            local _sz
            _sz=$(numfmt --to=iec "$(stat -c%s "${_downloaded[$i]}" 2>/dev/null || echo 0)" 2>/dev/null)
            printf "   ${CYAN}%2d)${RESET} %-50s ${DIM}%s${RESET}\n" \
                "$((i+1))" "$(basename "${_downloaded[$i]}")" "$_sz"
        done
        echo ""
        read -rp "  👉   Elige: " _fc
        if ! [[  "$_fc" =~ ^[0-9]+$ ]] || \
           [ "$_fc" -lt 1 ] || [ "$_fc" -gt "${#_downloaded[@]}" ]; then
            echo -e "\n  ${RED}✖ Opción inválida${RESET}\n"; exit 1
        fi
        BACKUP_FILE="${_downloaded[$((_fc-1))]}"
        echo -e "  ${GREEN}✔${RESET} Usando: ${BOLD}$(basename "$BACKUP_FILE")${RESET}"
    fi
}

# Menú principal — se invoca cuando el script se ejecuta sin argumentos
interactive_menu() {
    clear
    print_header "🗄️   Ready2Dev — Database Manager"
    echo -e "  ${BOLD}¿Qué deseas hacer?${RESET}"
    echo ""
    echo -e "  ${DIM}── Bases de Xentro ─────────────────────────────────────${RESET}"
    echo -e "   ${CYAN}1)${RESET} Restaurar bases de Xentro"
    echo -e "   ${CYAN}2)${RESET} Solo Optimizar"
    echo ""
    echo -e "  ${DIM}── Otras bases de datos (inhouse / fenrir) ──────────────${RESET}"
    echo -e "   ${CYAN}3)${RESET} Restaurar"
    echo ""
    echo -e "   ${CYAN}4)${RESET} Salir"
    echo ""
    read -rp "  👉   Elige una opción: " _ac
    echo ""

    case "$_ac" in
        1) xentro_restore_menu ;;
        2) restore=false; optimize=true;  _ACTION_LABEL="Solo Optimizar (Xentro)"  ;;
        3) restore=true;  optimize=false; _ACTION_LABEL="Restaurar"                ;;
        4) exit 0 ;;
        *) echo -e "  ${RED}✖ Opción inválida${RESET}\n"; exit 1 ;;
    esac

    # Para opciones 2-3: flujo genérico de selección
    if [[ "$_ac" != "1" ]]; then
        if $restore; then
            select_backup_file
        fi

        select_database_name

        if $restore && $PAIRED_RESTORE; then
            select_second_paired_backup
        fi

        if $restore; then
            confirm_cleanup
        fi
    fi

    # Resumen antes de ejecutar
    clear
    print_header "🗄️   Ready2Dev — Database Manager"
    echo -e "${DIM}──────────────────────────────────────────────────────────────${RESET}"
    echo -e "  ${DIM}Resumen:${RESET}"
    if $PAIRED_RESTORE; then
        echo -e "  ${DIM}Backup LLC:${RESET} ${BOLD}$(basename "$BACKUP_FILE_LLC")${RESET}"
        echo -e "  ${DIM}Backup NAC:${RESET} ${BOLD}$(basename "$BACKUP_FILE_NAC")${RESET}"
        echo -e "  ${DIM}Bases:${RESET}     ${BOLD}$XENTRO_NAME_LLC → $XENTRO_NAME_NAC${RESET}"
    else
        $restore && echo -e "  ${DIM}Backup:${RESET}    ${BOLD}$(basename "${BACKUP_FILE:-N/A}")${RESET}"
        echo -e "  ${DIM}Database:${RESET}  ${BOLD}$DATABASE_NAME${RESET}"
    fi
    echo -e "  ${DIM}Restaurar:${RESET} $($restore  && echo "${GREEN}SÍ${RESET}" || echo "${DIM}NO${RESET}")"
    echo -e "  ${DIM}Optimizar:${RESET} $($optimize && echo "${GREEN}SÍ${RESET}" || echo "${DIM}NO${RESET}")"
    $restore && echo -e "  ${DIM}Limpiar:${RESET}   $($CLEANUP_AFTER && echo "${YELLOW}SÍ${RESET}" || echo "${DIM}NO${RESET}")"
    echo -e "${DIM}──────────────────────────────────────────────────────────────${RESET}"
    echo ""
    if ! confirm "  ¿Continuar?" "y"; then
        echo -e "\n  ${YELLOW}Cancelado.${RESET}\n"; exit 0
    fi
    echo ""
}

# --- Procesamiento de Argumentos ---
restore=true
optimize=true
restore_only_flag=false
optimize_only_flag=false
CLEANUP_AFTER=false
PAIRED_RESTORE=false
BACKUP_FILE_LLC=""
BACKUP_FILE_NAC=""
XENTRO_NAME_LLC=""
XENTRO_NAME_NAC=""
_SECOND_BACKUP_FOR=""

while [[ "$1" == -* ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -r|--restore-only) restore_only_flag=true; restore=true; optimize=false ;;
        -o|--optimize-only) optimize_only_flag=true; optimize=true; restore=false ;;
        *) echo "Opción desconocida: $1"; usage; exit 1 ;;
    esac
    shift
done

if $restore_only_flag && $optimize_only_flag; then
    echo "❌   Error: No se pueden usar las opciones --restore-only y --optimize-only al mismo tiempo."
    usage
    exit 1
fi

# Sin argumentos → menú interactivo
if [[ "$#" -eq 0 ]] && ! $restore_only_flag && ! $optimize_only_flag; then
    interactive_menu
elif $optimize_only_flag; then
    if [ "$#" -ne 1 ]; then
        echo "❌   Error: La opción --optimize-only requiere exactamente un argumento: <nombre_base_datos>"
        usage
        exit 1
    fi
    DATABASE_NAME="$1"
else
    if [ "$#" -ne 2 ]; then
        echo "❌   Error: Se requieren exactamente dos argumentos: <archivo_backup> y <nombre_base_datos>"
        usage
        exit 1
    fi
    BACKUP_FILE="$1"
    DATABASE_NAME="$2"
fi

# Validar que el nombre de la base de datos solo contenga caracteres seguros
if [[ ! "$DATABASE_NAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
    echo "❌   Error: El nombre de la base de datos '$DATABASE_NAME' contiene caracteres no permitidos."
    echo "   Solo se permiten letras, números y guión bajo."
    exit 1
fi

# --- Inicio del Script ---
START_TIME=$(date +%s)

# MYSQL_USER toma el valor definido en .env, en la variable de entorno, o el default 'remote'.
MYSQL_USER="${MYSQL_USER:-remote}"

if $restore; then
    if $PAIRED_RESTORE; then
        [ ! -f "$BACKUP_FILE_LLC" ] && { echo "Error: El archivo '$BACKUP_FILE_LLC' no existe."; exit 1; }
        [ ! -f "$BACKUP_FILE_NAC" ] && { echo "Error: El archivo '$BACKUP_FILE_NAC' no existe."; exit 1; }
    elif [ ! -f "$BACKUP_FILE" ]; then
        echo "Error: El archivo '$BACKUP_FILE' no existe."
        exit 1
    fi
fi

if [ -n "${MYSQL_PASS:-}" ]; then
    # Contraseña cargada desde .env o variable de entorno — no se solicita interactivamente.
    export MYSQL_PWD="$MYSQL_PASS"
    unset MYSQL_PASS
    if ! mysql -u "$MYSQL_USER" -e "SELECT 1;" >/dev/null 2>&1; then
        echo "❌   Error: No se pudo conectar a MySQL con las credenciales del archivo .env."
        unset MYSQL_PWD
        exit 1
    fi
else
    MAX_ATTEMPTS=3
    attempt=0

    while true; do
        attempt=$((attempt + 1))
        echo -n "Introduce la contraseña de MySQL: "
        read -s MYSQL_PASS
        echo ""

        # Exportar la contraseña como variable de entorno para evitar exponerla
        # en la lista de procesos del sistema (ps aux).
        export MYSQL_PWD="$MYSQL_PASS"
        unset MYSQL_PASS

        # Verificar credenciales
        if mysql -u "$MYSQL_USER" -e "SELECT 1;" >/dev/null 2>&1; then
            break
        fi

        unset MYSQL_PWD
        if [ $attempt -ge $MAX_ATTEMPTS ]; then
            echo "❌   Error: Contraseña incorrecta. Se agotaron los $MAX_ATTEMPTS intentos."
            exit 1
        fi
        echo "⚠️   Contraseña incorrecta. Intento $attempt de $MAX_ATTEMPTS."
    done
fi

# Función de limpieza al salir (por señal o error inesperado)
cleanup() {
    unset MYSQL_PWD
    # Matar procesos huérfanos de importación si existen
    [[ -n "${reader_pid:-}" ]] && kill "$reader_pid" 2>/dev/null
    [[ -n "${consumer_pid:-}" ]] && kill "$consumer_pid" 2>/dev/null
    [[ -n "${progress_pipe:-}" ]] && rm -f "$progress_pipe"
    # Restaurar cursor visible por si se interrumpió mid-render
    printf '\033[?25h' 2>/dev/null
}
trap cleanup EXIT INT TERM

print_step() {
    local step=$1; local total=$2; local status=$3; local message="$4"
    local color="$CYAN"
    local icon="●"
    case "$status" in
        running) color="$YELLOW"; icon="◌" ;;
        done)    color="$GREEN";  icon="✔" ;;
        fail)    color="$RED";    icon="✖" ;;
    esac
    printf "\r\033[K  ${DIM}[%d/%d]${RESET} ${color}${icon}${RESET} %s" "$step" "$total" "$message"
}

run_restore_step() {
    local step_num=$1; local total=$2; local message="$3"
    shift 3
    local tmp_log
    tmp_log=$(mktemp)

    print_step "$step_num" "$total" "running" "$message"

    # Suprimir notificaciones de job control redirigiendo stderr del shell
    exec 3>&2 2>/dev/null
    "$@" >"$tmp_log" 2>&1 &
    local pid=$!
    local SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local frame=0

    while kill -0 $pid 2>/dev/null; do
        local char="${SPINNER_CHARS:$frame:1}"
        printf "\r\033[K  ${DIM}[%d/%d]${RESET} ${YELLOW}%s${RESET} %s" "$step_num" "$total" "$char" "$message"
        sleep 0.08
        frame=$(( (frame + 1) % ${#SPINNER_CHARS} ))
    done

    # Capture via if/else, not a bare "wait": under `set -e` a bare wait that
    # returns non-zero would kill the script right here, before we ever get
    # to show the ✖ and the error log below.
    local exit_code
    if wait $pid 2>/dev/null; then
        exit_code=0
    else
        exit_code=$?
    fi
    exec 2>&3 3>&-  # Restaurar stderr

    if [ $exit_code -ne 0 ]; then
        print_step "$step_num" "$total" "fail" "$message"
        printf '\n'
        echo -e "  ${RED}Error:${RESET}"
        sed 's/^/    /' "$tmp_log"
        rm -f "$tmp_log"
        exit 1
    fi

    print_step "$step_num" "$total" "done" "$message"
    printf '\n'
    echo ""
    rm -f "$tmp_log"
}

# --- Proceso de Restauración ---
if $restore; then
    if $PAIRED_RESTORE; then
        _RQUEUE_FILES=("$BACKUP_FILE_LLC" "$BACKUP_FILE_NAC")
        _RQUEUE_NAMES=("$XENTRO_NAME_LLC" "$XENTRO_NAME_NAC")
    else
        _RQUEUE_FILES=("$BACKUP_FILE")
        _RQUEUE_NAMES=("$DATABASE_NAME")
    fi
    _PROC_RESTORE_TIMES=()
    _COMPLETED_DB_SUMMARIES=()
    # Helper: formatea segundos a Xh MMm SSs
    _fmts() { printf "%dh %02dm %02ds" $(($1/3600)) $((($1%3600)/60)) $(($1%60)); }

    for _qi in "${!_RQUEUE_FILES[@]}"; do
        BACKUP_FILE="${_RQUEUE_FILES[$_qi]}"
        DATABASE_NAME="${_RQUEUE_NAMES[$_qi]}"
        _CURRENT_DB="$DATABASE_NAME"
        _t_rs=$(date +%s)
        _step_ts=()
        _decomp_elapsed=""
        _import_elapsed=0

    # Archivos comprimidos requieren un paso extra de descompresión
    if [[ "$BACKUP_FILE" == *.tar.gz || "$BACKUP_FILE" == *.sql.gz ]]; then
        RESTORE_STEPS=5
    else
        RESTORE_STEPS=4
    fi
    print_step_header

    _ts=$(date +%s)
    run_restore_step 1 $RESTORE_STEPS "   Eliminando base de datos existente..." \
        mysql -u "$MYSQL_USER" --silent --skip-column-names -e "DROP DATABASE IF EXISTS $DATABASE_NAME;"
    _step_ts+=( "$(( $(date +%s) - _ts ))" )

    _ts=$(date +%s)
    run_restore_step 2 $RESTORE_STEPS "   Creando base de datos..." \
        mysql -u "$MYSQL_USER" --silent --skip-column-names -e "CREATE DATABASE $DATABASE_NAME;"
    _step_ts+=( "$(( $(date +%s) - _ts ))" )

    _ts=$(date +%s)
    run_restore_step 3 $RESTORE_STEPS "   Configurando permisos de funciones..." \
        mysql -u "$MYSQL_USER" --silent --skip-column-names -e "SET GLOBAL log_bin_trust_function_creators = 1;"
    _step_ts+=( "$(( $(date +%s) - _ts ))" )

    # Pasos 4(+5): Descompresión (si aplica) e importación con barra de progreso
    restore_error_log=$(mktemp)
    file_size=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || stat -f%z "$BACKUP_FILE" 2>/dev/null)
    human_size=$(numfmt --to=iec "$file_size" 2>/dev/null || echo "${file_size} bytes")

    # Función: dibuja barra de progreso moderna
    draw_import_progress() {
        local bytes_read=$1; local total=$2; local elapsed=$3
        local pct=0 speed=0 eta_s=0
        if [ "$total" -gt 0 ]; then
            pct=$((bytes_read * 100 / total))
        fi
        if [ "$elapsed" -gt 0 ]; then
            speed=$((bytes_read / elapsed))
        fi
        if [ "$speed" -gt 0 ]; then
            eta_s=$(( (total - bytes_read) / speed ))
        fi

        local width=40
        local filled=$((pct * width / 100))
        local bar=""
        for ((i=0; i<filled; i++)); do bar+="━"; done
        if [ $filled -lt $width ]; then
            bar+="╸"
            for ((i=filled+1; i<width; i++)); do bar+="─"; done
        fi

        local h_read h_speed
        h_read=$(numfmt --to=iec "$bytes_read" 2>/dev/null || echo "$bytes_read")
        h_speed=$(numfmt --to=iec "$speed" 2>/dev/null || echo "$speed")
        local eta_m=$((eta_s / 60)) eta_sec=$((eta_s % 60))
        local el_m=$((elapsed / 60)) el_s=$((elapsed % 60))

        printf "\r\033[K    ${CYAN}%s${RESET} %3d%% ${DIM}│${RESET} %s/s ${DIM}│${RESET} %s ${DIM}│${RESET} ETA %02d:%02d ${DIM}│${RESET} %02d:%02d" \
            "$bar" "$pct" "$h_speed" "$h_read" "$eta_m" "$eta_sec" "$el_m" "$el_s"
    }

    # Función: bytes leídos por un proceso (fd 0)
    get_bytes_read() {
        local pid=$1
        if [[ -r "/proc/$pid/fdinfo/0" ]]; then
            awk '/^pos:/ {print $2}' "/proc/$pid/fdinfo/0" 2>/dev/null || echo 0
        elif command -v lsof &>/dev/null; then
            lsof -o -p "$pid" 2>/dev/null | awk '/REG/ {gsub(/0t/,"",$7); print $7; exit}' || echo 0
        else
            echo 0
        fi
    }

    MYSQL_IMPORT_OPTS="--binary-mode --default-character-set=utf8mb4 --force"

    temp_sql=""
    import_src="$BACKUP_FILE"
    import_size="$file_size"
    import_human="$human_size"
    import_step=4

    # --- Paso 4 (solo para comprimidos): Descompresión con barra de progreso ---
    if [[ "$BACKUP_FILE" == *.tar.gz || "$BACKUP_FILE" == *.sql.gz ]]; then
        echo -e "  ${DIM}[4/${RESTORE_STEPS}]${RESET} ${YELLOW}◌${RESET}    Descomprimiendo ${DIM}(${human_size} comprimido)${RESET}"
        echo ""

        temp_sql=$(mktemp "${TMPDIR:-/tmp}/restore_XXXXXX.sql")
        decomp_pipe=$(mktemp -u); mkfifo "$decomp_pipe"
        decomp_start=$(date +%s)

        exec 3>&2 2>/dev/null
        cat < "$BACKUP_FILE" > "$decomp_pipe" &
        reader_pid=$!
        if [[ "$BACKUP_FILE" == *.tar.gz ]]; then
            tar -xzO < "$decomp_pipe" > "$temp_sql" &
        else
            gzip -dc < "$decomp_pipe" > "$temp_sql" &
        fi
        consumer_pid=$!

        while kill -0 $reader_pid 2>/dev/null; do
            bytes_read=$(get_bytes_read $reader_pid)
            elapsed=$(( $(date +%s) - decomp_start ))
            draw_import_progress "${bytes_read:-0}" "$file_size" "$elapsed"
            sleep 0.5
        done
        decomp_exit=0
        wait $consumer_pid 2>/dev/null || decomp_exit=$?
        wait $reader_pid 2>/dev/null || true
        exec 2>&3 3>&-
        rm -f "$decomp_pipe"

        elapsed=$(( $(date +%s) - decomp_start ))
        draw_import_progress "$file_size" "$file_size" "$elapsed"
        printf '\n'
        _decomp_elapsed=$elapsed

        printf '\033[3A\r\033[K'
        if [ "${decomp_exit:-1}" -ne 0 ]; then
            echo -e "  ${DIM}[4/${RESTORE_STEPS}]${RESET} ${RED}✖${RESET}    Descomprimiendo ${DIM}(${human_size} comprimido)${RESET}"
            printf '\033[2B'
            echo -e "\n  ${RED}✖ Error al descomprimir el archivo.${RESET}"
            rm -f "$restore_error_log" "$temp_sql"
            exit 1
        fi
        echo -e "  ${DIM}[4/${RESTORE_STEPS}]${RESET} ${GREEN}✔${RESET}    Descomprimiendo ${DIM}(${human_size} comprimido)${RESET}"
        printf '\033[J'

        import_src="$temp_sql"
        import_size=$(stat -c%s "$temp_sql" 2>/dev/null || echo 0)
        import_human=$(numfmt --to=iec "$import_size" 2>/dev/null || echo "${import_size} bytes")
        import_step=5

    elif [[ "$BACKUP_FILE" != *.sql ]]; then
        echo -e "  ${RED}✖ Formato no soportado. Usa .sql, .sql.gz o .tar.gz${RESET}"
        rm -f "$restore_error_log"
        exit 1
    fi

    # --- Paso 4 o 5: Importación SQL con barra de progreso ---
    echo ""
    echo -e "  ${DIM}[${import_step}/${RESTORE_STEPS}]${RESET} ${YELLOW}◌${RESET}    Importando datos ${DIM}(${import_human})${RESET}"
    echo ""

    import_pipe=$(mktemp -u); mkfifo "$import_pipe"
    import_start=$(date +%s)

    exec 3>&2 2>/dev/null
    cat < "$import_src" > "$import_pipe" &
    reader_pid=$!
    mysql $MYSQL_IMPORT_OPTS -u "$MYSQL_USER" "$DATABASE_NAME" < "$import_pipe" 2>"$restore_error_log" &
    consumer_pid=$!

    while kill -0 $reader_pid 2>/dev/null; do
        bytes_read=$(get_bytes_read $reader_pid)
        elapsed=$(( $(date +%s) - import_start ))
        draw_import_progress "${bytes_read:-0}" "$import_size" "$elapsed"
        sleep 0.5
    done

    import_exit=0
    wait $consumer_pid 2>/dev/null || import_exit=$?
    wait $reader_pid 2>/dev/null || true
    exec 2>&3 3>&-
    rm -f "$import_pipe"
    [ -n "$temp_sql" ] && rm -f "$temp_sql"

    elapsed=$(( $(date +%s) - import_start ))
    draw_import_progress "$import_size" "$import_size" "$elapsed"
    printf '\n'
    _import_elapsed=$elapsed

    if [ "${import_exit:-1}" -ne 0 ] || [ -s "$restore_error_log" ]; then
        printf '\033[3A\r\033[K'
        echo -e "  ${DIM}[${import_step}/${RESTORE_STEPS}]${RESET} ${YELLOW}⚠${RESET}    Importando datos ${DIM}(${import_human})${RESET}"
        printf '\033[2B'
        warning_count=$(wc -l < "$restore_error_log" 2>/dev/null || echo 0)
        echo -e "  ${YELLOW}⚠️   Importación completada con ${warning_count} warning(s):${RESET}"
        sed 's/^/    /' "$restore_error_log"
    else
        printf '\033[3A\r\033[K'
        echo -e "  ${DIM}[${import_step}/${RESTORE_STEPS}]${RESET} ${GREEN}✔${RESET}    Importando datos ${DIM}(${import_human})${RESET}"
        printf '\033[2B'
    fi

    rm -f "$restore_error_log"

    if $CLEANUP_AFTER && [ -n "${BACKUP_FILE:-}" ]; then
        echo ""
        echo -e "  ${DIM}🗑️   Eliminando archivo de backup...${RESET}"
        rm -f "$BACKUP_FILE"
        echo -e "  ${YELLOW}✔    Eliminado:${RESET} ${BOLD}$(basename "$BACKUP_FILE")${RESET}"
    fi

    _t_re=$(date +%s)
    _t_el=$(( _t_re - _t_rs ))
    printf -v _t_fmt "%dh %02dm %02ds" $((_t_el/3600)) $(((_t_el%3600)/60)) $((_t_el%60))
    _PROC_RESTORE_TIMES+=("${DATABASE_NAME}|${_t_fmt}")

    # --- Guardar resumen por pasos de esta BD para mostrarlo en iteraciones posteriores ---
    _cs="  ${GREEN}${BOLD}✅  ${DATABASE_NAME}${RESET}   ${DIM}total: ${_t_fmt}${RESET}\n"
    _cs+="     ${DIM}├ Eliminar BD:   ${RESET}$(_fmts "${_step_ts[0]:-0}")\n"
    _cs+="     ${DIM}├ Crear BD:      ${RESET}$(_fmts "${_step_ts[1]:-0}")\n"
    _cs+="     ${DIM}├ Permisos:      ${RESET}$(_fmts "${_step_ts[2]:-0}")\n"
    if [ -n "${_decomp_elapsed:-}" ]; then
        _cs+="     ${DIM}├ Descomprimir:  ${RESET}$(_fmts "$_decomp_elapsed")\n"
    fi
    _cs+="     ${DIM}└ Importar SQL:  ${RESET}$(_fmts "${_import_elapsed:-0}")"
    _COMPLETED_DB_SUMMARIES+=("$_cs")

    echo ""
    echo -e "  ${GREEN}${BOLD}✅   Restauración completada con éxito${RESET}"
    echo ""

    done  # fin del loop de restauración pareada
fi

# --- Proceso de Optimización ---
if $optimize; then
    SQL_FILE="$SCRIPT_DIR/optimize_db.sql"
    if [ ! -f "$SQL_FILE" ]; then
        echo -e "  ${RED}✖ Error: No se encontró el archivo de optimización: $SQL_FILE${RESET}"
        exit 1
    fi

    if $PAIRED_RESTORE; then
        _OQUEUE_NAMES=("$XENTRO_NAME_LLC" "$XENTRO_NAME_NAC")
        _OQUEUE_BACKUPS=("${BACKUP_FILE_LLC:-}" "${BACKUP_FILE_NAC:-}")
    else
        _OQUEUE_NAMES=("$DATABASE_NAME")
        _OQUEUE_BACKUPS=("${BACKUP_FILE:-}")
    fi
    _OPT_SUMMARY=()

    TOTAL_STEPS=3
    SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

    draw_progress_line() {
        local current=$1; local total=$2; local message="$3"; local indicator="$4"; local width=32
        local percentage=$((current * 100 / total))
        local filled_len=$((current * width / total))
        local bar=""
        for ((i=0; i<filled_len; i++)); do bar+="━"; done
        if [ $filled_len -lt $width ]; then
            bar+="╸"
            for ((i=filled_len+1; i<width; i++)); do bar+="─"; done
        fi
        printf "\r\033[K  ${DIM}[${RESET}${CYAN}%s${RESET}${DIM}]${RESET} %3d%% ${DIM}(%2d/%2d)${RESET} %b %s" "$bar" "$percentage" "$current" "$total" "$indicator" "$message"
    }

    execute_sql_step() {
        local message="$1"; local sql_query="$2"; local error_message="$3"
        CURRENT_STEP=$((CURRENT_STEP + 1))
        local tmp_log
        tmp_log=$(mktemp)
        exec 3>&2 2>/dev/null
        mysql -u "$MYSQL_USER" "$DATABASE_NAME" -e "$sql_query" >"$tmp_log" 2>&1 &
        local pid=$!
        local frame=0

        draw_progress_line "$CURRENT_STEP" "$TOTAL_STEPS" "$message" "${SPINNER_CHARS:$frame:1}"
        while kill -0 $pid 2>/dev/null; do
            sleep 0.08
            frame=$(( (frame + 1) % ${#SPINNER_CHARS} ))
            draw_progress_line "$CURRENT_STEP" "$TOTAL_STEPS" "$message" "${YELLOW}${SPINNER_CHARS:$frame:1}${RESET}"
        done

        # if/else, not a bare "wait": under `set -e` a failing bare wait would
        # exit here before we ever show the ✖ and error log below.
        local exit_code
        if wait $pid; then exit_code=0; else exit_code=$?; fi
        exec 2>&3 3>&-
        if [ $exit_code -ne 0 ]; then
            draw_progress_line "$CURRENT_STEP" "$TOTAL_STEPS" "$message" "${RED}✖${RESET}"
            printf '\n'
            echo -e "  ${RED}ERROR:${RESET} $error_message"
            sed 's/^/    /' "$tmp_log"
            rm -f "$tmp_log"
            exit 1
        fi

        draw_progress_line "$CURRENT_STEP" "$TOTAL_STEPS" "$message" "${GREEN}✔${RESET}"
        printf '\n'
        rm -f "$tmp_log"
    }

    execute_sql_file_step() {
        local message="$1"; local sql_file="$2"; local error_message="$3"; local init_cmd="${4:-}"
        CURRENT_STEP=$((CURRENT_STEP + 1))
        local tmp_log
        tmp_log=$(mktemp)
        exec 3>&2 2>/dev/null
        if [ -n "$init_cmd" ]; then
            mysql -u "$MYSQL_USER" --init-command "$init_cmd" "$DATABASE_NAME" < "$sql_file" >"$tmp_log" 2>&1 &
        else
            mysql -u "$MYSQL_USER" "$DATABASE_NAME" < "$sql_file" >"$tmp_log" 2>&1 &
        fi
        local pid=$!
        local frame=0

        draw_progress_line "$CURRENT_STEP" "$TOTAL_STEPS" "$message" "${SPINNER_CHARS:$frame:1}"
        while kill -0 $pid 2>/dev/null; do
            sleep 0.08
            frame=$(( (frame + 1) % ${#SPINNER_CHARS} ))
            draw_progress_line "$CURRENT_STEP" "$TOTAL_STEPS" "$message" "${YELLOW}${SPINNER_CHARS:$frame:1}${RESET}"
        done

        local exit_code
        if wait $pid; then exit_code=0; else exit_code=$?; fi
        exec 2>&3 3>&-
        if [ $exit_code -ne 0 ]; then
            draw_progress_line "$CURRENT_STEP" "$TOTAL_STEPS" "$message" "${RED}✖${RESET}"
            printf '\n'
            echo -e "  ${RED}ERROR:${RESET} $error_message"
            sed 's/^/    /' "$tmp_log"
            rm -f "$tmp_log"
            exit 1
        fi

        draw_progress_line "$CURRENT_STEP" "$TOTAL_STEPS" "$message" "${GREEN}✔${RESET}"
        printf '\n'
        rm -f "$tmp_log"
    }

    for _qi in "${!_OQUEUE_NAMES[@]}"; do
        DATABASE_NAME="${_OQUEUE_NAMES[$_qi]}"
        _bkfile="${_OQUEUE_BACKUPS[$_qi]:-}"
        _bkname=""
        _bkref=""
        if [ -n "$_bkfile" ]; then
            _bkname="$(basename "$_bkfile")"
            _bkref="$_bkname"
            _bkref="${_bkref%.sql.gz}"; _bkref="${_bkref%.tar.gz}"
            _bkref="${_bkref%.sql}";    _bkref="${_bkref%.gz}"
            _bkref="${_bkref##*_}"
        fi
        _init_cmd="SET @backup_nombre='${_bkname}'; SET @ref_backup='${_bkref}';"

        CURRENT_STEP=0
        print_step_header

        execute_sql_step "Desactivando revisiones de llaves..." \
            "SET GLOBAL foreign_key_checks=0; SET GLOBAL unique_checks=0;" \
            "Desactivar llaves"

        execute_sql_file_step "Ejecutando optimización y limpieza..." \
            "$SQL_FILE" \
            "Ejecutar SQL de optimización" \
            "$_init_cmd"

        execute_sql_step "Reactivando revisiones de llaves..." \
            "SET GLOBAL foreign_key_checks=1; SET GLOBAL unique_checks=1;" \
            "Reactivar llaves"

        echo ""
        echo -e "  ${GREEN}${BOLD}✅   Optimización y limpieza completadas con éxito${RESET}"
        echo ""
        _OPT_SUMMARY+=("${DATABASE_NAME}|${_bkname}|${_bkref}")
    done  # fin del loop de optimización pareada

    if [ ${#_OPT_SUMMARY[@]} -gt 1 ]; then : ; fi  # reservado
fi

# --- Resumen final del proceso ---
if [ ${#_OPT_SUMMARY[@]} -gt 1 ] || [ ${#_PROC_RESTORE_TIMES[@]} -gt 1 ]; then
    print_header "📋   Resumen del proceso"
    _sum_n=$(( ${#_OPT_SUMMARY[@]} > ${#_PROC_RESTORE_TIMES[@]} ? ${#_OPT_SUMMARY[@]} : ${#_PROC_RESTORE_TIMES[@]} ))
    for (( _i=0; _i<_sum_n; _i++ )); do
        _sdb=""; _sbk=""; _sref=""; _srtime=""; _has_opt=false
        if [ $_i -lt ${#_OPT_SUMMARY[@]} ]; then
            IFS='|' read -r _sdb _sbk _sref <<< "${_OPT_SUMMARY[$_i]}"
            _has_opt=true
        fi
        if [ $_i -lt ${#_PROC_RESTORE_TIMES[@]} ]; then
            IFS='|' read -r _rdn _srtime <<< "${_PROC_RESTORE_TIMES[$_i]}"
            [ -z "$_sdb" ] && _sdb="$_rdn"
        fi
        echo -e "  ${BOLD}${CYAN}${_sdb}${RESET}"
        [ -n "$_sbk" ] && echo -e "  ${DIM}Backup:${RESET} ${BOLD}${_sbk}${RESET}   ${DIM}[ref: ${_sref}]${RESET}"
        [ -n "$_srtime" ] && echo -e "    ${GREEN}✔${RESET}   Restauración completada          ${DIM}(${_srtime})${RESET}"
        if $_has_opt; then
            echo -e "    ${GREEN}✔${RESET}   Desactivando revisiones de llaves"
            echo -e "    ${GREEN}✔${RESET}   Optimización y limpieza ejecutada"
            echo -e "    ${GREEN}✔${RESET}   Reactivando revisiones de llaves"
        fi
        echo ""
    done
fi

# --- Finalización ---
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
HOURS=$((TOTAL_TIME / 3600))
MINUTES=$(( (TOTAL_TIME % 3600) / 60 ))
SECONDS=$((TOTAL_TIME % 60))

echo -e "${DIM}──────────────────────────────────────────────────────────────${RESET}"
echo -e "  ${BLUE}⏳${RESET}   Tiempo total: ${BOLD}${HOURS}h ${MINUTES}m ${SECONDS}s${RESET}"
echo -e "  ${GREEN}🚀${RESET}   Proceso completado con éxito"
echo -e "${DIM}──────────────────────────────────────────────────────────────${RESET}"