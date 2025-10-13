#!/usr/bin/env bash
# ===============================================
# Ready2Dev - Shared UI for git_*.sh tool scripts
# ===============================================
# Sourced by the other scripts in this directory so all of them share
# the same look: a boxed section header and a spinner for slow,
# non-interactive git operations (fetch/pull/push/ls-remote) — the same
# style used by install.sh (headers) and db_restore/restore_db.sh
# (spinner + done/fail icons).
#
# Deployment note: this file lives alongside the other tool scripts on
# purpose. deploy_tool_scripts() (tools/lib/common.sh) copies every file
# in tools/scripts/ to ~/tools/scripts/, so it travels with them with no
# extra wiring needed.
# ===============================================

# ===== Colors =====
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'

# Boxed section header, e.g.: print_header "🚀 Git Push"
print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}┌──────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BOLD}${CYAN}│${RESET}  ${BOLD}$1${RESET}"
    echo -e "${BOLD}${CYAN}└──────────────────────────────────────────────────────────┘${RESET}"
    echo ""
}

# Run a NON-INTERACTIVE command with a spinner, printing its output only on
# failure. Do not use this for commands that need a TTY (git commit without
# -m, git rebase -i, credential prompts) — their prompts would be silently
# hidden while backgrounded.
#   run_step "Pushing to origin/$branch" git push origin "$branch"
run_step() {
    local message="$1"; shift
    local tmp_log
    tmp_log=$(mktemp)
    local spinner_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local frame=0

    # Suppress shell job-control notifications while the step runs in the background.
    exec 3>&2 2>/dev/null
    "$@" >"$tmp_log" 2>&1 &
    local pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r\033[K  ${YELLOW}%s${RESET}  %s" "${spinner_chars:$frame:1}" "$message"
        sleep 0.08
        frame=$(( (frame + 1) % ${#spinner_chars} ))
    done

    # Capture the exit code via an if/else, not a bare statement: under
    # `set -e` (install.sh uses it), a bare "wait" that returns non-zero
    # would kill the whole script right here, before we ever get to print
    # the ✖ and the error log below.
    local exit_code
    if wait "$pid" 2>/dev/null; then
        exit_code=0
    else
        exit_code=$?
    fi
    exec 2>&3 3>&-

    if [ $exit_code -ne 0 ]; then
        printf "\r\033[K  ${RED}✖${RESET}  %s\n" "$message"
        echo -e "  ${RED}Error:${RESET}"
        sed 's/^/    /' "$tmp_log"
        rm -f "$tmp_log"
        return $exit_code
    fi

    printf "\r\033[K  ${GREEN}✔${RESET}  %s\n" "$message"
    rm -f "$tmp_log"
    return 0
}

# ===== Yes/No confirmation, homologated across the whole project =====
# Normalizes an answer: strips accents, lowercases, keeps only the first
# word (so "nO NO", "  Sí  ", "NOT" all resolve sanely instead of failing
# a strict regex match).
#
# Accents are stripped via literal byte substitution BEFORE lowercasing,
# and lowercasing uses `tr` rather than bash's `${var,,}`: under a non-UTF-8
# locale (LANG/LC_ALL unset - common in minimal shells and `sudo -u user
# bash -c "..."` calls), `${var,,}` case-folds a multi-byte accented
# character byte-by-byte and corrupts it; `tr '[:upper:]' '[:lower:]'`
# only touches plain ASCII bytes, so it leaves any UTF-8 bytes intact.
_normalize_answer() {
    local first _rest
    read -r first _rest <<< "$1"
    first="${first//í/i}"; first="${first//Í/I}"
    first="${first//á/a}"; first="${first//Á/A}"
    first="${first//é/e}"; first="${first//É/E}"
    first="${first//ó/o}"; first="${first//Ó/O}"
    first="${first//ú/u}"; first="${first//Ú/U}"
    first=$(printf '%s' "$first" | tr '[:upper:]' '[:lower:]')
    printf '%s' "$first"
}

# Recognizes: s, si, sí, sip, y, ye, yes, yeah, yep
is_yes() {
    local v; v=$(_normalize_answer "$1")
    [[ "$v" =~ ^(s|si|sip|y|ye|yes|yeah|yep)$ ]]
}

# Recognizes: n, no, nop, nope, not
is_no() {
    local v; v=$(_normalize_answer "$1")
    [[ "$v" =~ ^(n|no|nop|nope|not)$ ]]
}

# Ask a yes/no question with maximal input tolerance (case, accents,
# Spanish/English variants, stray whitespace). Unrecognized input falls
# back to the default instead of erroring out.
#   if confirm "¿Continuar?"; then ...            # default: no
#   if confirm "¿Mantener este nombre?" "y"; then ... # default: yes
confirm() {
    local prompt="$1" default="${2:-n}" hint answer
    hint="[y/N]"
    [[ "$default" == "y" ]] && hint="[Y/n]"

    read -rp "$(echo -e "${YELLOW}${prompt} ${hint}: ${RESET}")" answer

    if [[ -z "$answer" ]] || { ! is_yes "$answer" && ! is_no "$answer"; }; then
        [[ "$default" == "y" ]]
        return
    fi

    is_yes "$answer"
}
