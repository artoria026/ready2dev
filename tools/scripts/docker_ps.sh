#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=git_ui.sh
source "$SCRIPT_DIR/git_ui.sh"

print_header "🐳 Docker — Contenedores"

if ! command -v docker &>/dev/null; then
    echo -e "  ${RED}❌   Docker no esta instalado o no esta en el PATH.${RESET}"
    exit 1
fi
if ! docker info &>/dev/null; then
    echo -e "  ${RED}❌   El daemon de Docker no responde. ¿Esta corriendo?${RESET}"
    exit 1
fi

SHOW_ALL=false
case "${1:-}" in
    -a|--all) SHOW_ALL=true ;;
    -h|--help)
        echo "Uso:"
        echo "  docker_ps        Solo contenedores corriendo"
        echo "  docker_ps -a     Incluye detenidos"
        exit 0
        ;;
    "") ;;
    *) echo -e "  ${RED}✖ Flag desconocido: $1${RESET}"; exit 1 ;;
esac

# Del campo Ports de docker ps (ej. "127.0.0.1:8080->8080/tcp, ..." o
# "0.0.0.0:3307->3306/tcp, [::]:3307->3306/tcp") toma solo el primer
# host:puerto publicado, que es el unico dato accionable para un humano.
port_summary() {
    local first="${1%%,*}"
    if [[ "$first" == *"->"* ]]; then
        local hostpart="${first%%->*}"
        echo "${hostpart/0.0.0.0/localhost}"
    elif [ -n "$first" ]; then
        echo "interno"
    else
        echo "-"
    fi
}

# Clasifica el campo Status de docker ps (texto libre, ej. "Up 33 minutes
# (healthy)", "Exited (137) 2 hours ago") en una etiqueta corta + color.
# Deja el resultado en las variables globales _LABEL y _COLOR.
classify_status() {
    local status="$1"
    case "$status" in
        *unhealthy*)          _LABEL="unhealthy";  _COLOR="$RED" ;;
        *"health: starting"*) _LABEL="iniciando";  _COLOR="$YELLOW" ;;
        *healthy*)            _LABEL="saludable";  _COLOR="$GREEN" ;;
        Up\ *)                _LABEL="corriendo";  _COLOR="$GREEN" ;;
        Restarting*)          _LABEL="reiniciando"; _COLOR="$YELLOW" ;;
        Paused*)              _LABEL="pausado";    _COLOR="$YELLOW" ;;
        Exited*)              _LABEL="detenido";   _COLOR="$RED" ;;
        Created*)             _LABEL="creado";     _COLOR="$DIM" ;;
        *)                    _LABEL="$status";    _COLOR="$DIM" ;;
    esac
}

FORMAT='{{.Names}}|{{.Label "com.docker.compose.project"}}|{{.Image}}|{{.Status}}|{{.Ports}}'
if $SHOW_ALL; then
    rows="$(docker ps -a --format "$FORMAT" 2>/dev/null)"
else
    rows="$(docker ps --format "$FORMAT" 2>/dev/null)"
fi

if [ -z "$rows" ]; then
    if $SHOW_ALL; then
        echo -e "  ${DIM}(sin contenedores en esta maquina)${RESET}"
    else
        echo -e "  ${DIM}(sin contenedores corriendo — usa 'docker_ps -a' para ver detenidos)${RESET}"
    fi
    echo ""
    exit 0
fi

printf "  ${DIM}%-22s %-16s %-26s %-12s %s${RESET}\n" "NOMBRE" "PROYECTO" "IMAGEN" "ESTADO" "PUERTOS"

total=0
while IFS='|' read -r name project image status ports; do
    [ -z "$name" ] && continue
    total=$((total + 1))
    [ -z "$project" ] && project="-"
    [ ${#image} -gt 25 ] && image="${image:0:22}..."
    classify_status "$status"
    port="$(port_summary "$ports")"
    printf "  %-22s %-16s %-26s ${_COLOR}%-12s${RESET} %s\n" "$name" "$project" "$image" "$_LABEL" "$port"
done <<< "$rows"

echo ""
if $SHOW_ALL; then
    echo -e "  ${DIM}Total: $total contenedor(es)${RESET}"
else
    echo -e "  ${DIM}Total: $total corriendo — usa 'docker_ps -a' para ver tambien los detenidos${RESET}"
fi
