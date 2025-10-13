#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=git_ui.sh
source "$SCRIPT_DIR/git_ui.sh"

print_header "🔄 Git Reset — Clean Repository Reset"

# Get current branch
current_branch=$(git rev-parse --abbrev-ref HEAD)
echo -e "${BLUE}📍 Current branch: $current_branch${RESET}"
echo

# The target branch is always chosen here, interactively — never accepted as
# a CLI argument, so there is exactly one way to pick it, no matter which
# alias (g_reset) is used to launch this script.
echo -e "${CYAN}🌿 Select the branch to reset/switch to:${RESET}"
echo -e "  1) master ${GREEN}(default)${RESET}"
echo -e "  2) master-stage"
echo -e "  3) QA-MSC-AX"
echo -e "  4) main"
echo -e "  5) Enter a custom branch name"
echo
read -rp "$(echo -e "${YELLOW}👉 Option [1/2/3/4/5] (press Enter for master): ${RESET}")" BRANCH_CHOICE

case "$BRANCH_CHOICE" in
    2)
        target_branch="master-stage"
        ;;
    3)
        target_branch="QA-MSC-AX"
        ;;
    4)
        target_branch="main"
        ;;
    5)
        read -rp "$(echo -e "${YELLOW}✏️  Enter branch name: ${RESET}")" custom_branch
        if [[ -z "$custom_branch" ]]; then
            echo -e "${RED}❌ Error: Branch name cannot be empty.${RESET}"
            exit 1
        fi
        target_branch="$custom_branch"
        ;;
    *)
        target_branch="master"
        ;;
esac

echo
echo -e "${BLUE}📌 Target branch: ${target_branch}${RESET}"
echo

# Verify the target branch exists locally or remotely. No branch name (not even
# "master") gets a free pass here — a repo may use "main" instead, or no shared
# base branch at all, so we never assume one exists.
if ! git show-ref --verify --quiet "refs/heads/${target_branch}" && \
   ! git show-ref --verify --quiet "refs/remotes/origin/${target_branch}"; then
    echo -e "${RED}❌ Error: Branch '${target_branch}' not found locally or in origin.${RESET}"
    exit 1
fi

echo -e "${YELLOW}⚠️  This will delete ALL local branches except '${target_branch}'!${RESET}"
echo

# Confirmation prompt
if ! confirm "Are you sure you want to continue?"; then
    echo -e "${YELLOW}❌ Operation cancelled.${RESET}"
    exit 0
fi
echo

# Discard a leftover garbage branch from a previous interrupted run, if any.
if git show-ref --verify --quiet refs/heads/garbageCollectorBranch; then
    git checkout -q "$current_branch" 2>/dev/null || git checkout -q "$target_branch" 2>/dev/null || true
    git branch -D garbageCollectorBranch >/dev/null 2>&1 || true
fi

echo -e "${MAGENTA}🗑️  Creating temporary garbage collector branch...${RESET}"
git checkout -b garbageCollectorBranch
echo

echo -e "${YELLOW}💾 Adding and committing any pending changes...${RESET}"
git add .
git commit -m 'GarbageForDelete' || true
echo

run_step "Fetching latest changes" git fetch origin
echo

# Switch straight to the target branch — no matter whether we started on
# master, main, a feature branch, or the target itself. If it doesn't exist
# locally yet but does on origin, git creates the local tracking branch here.
echo -e "${BLUE}🏠 Switching to '${target_branch}'...${RESET}"
git checkout "$target_branch"
echo

if git show-ref --verify --quiet "refs/remotes/origin/${target_branch}"; then
    run_step "Pulling latest ${target_branch}" git pull origin "$target_branch"
else
    echo -e "${YELLOW}ℹ️  '${target_branch}' has no remote copy on origin — skipping pull.${RESET}"
fi
echo

echo -e "${RED}🧹 Deleting all local branches except '${target_branch}'...${RESET}"
mapfile -t _local_branches < <(git branch --format='%(refname:short)')
for _b in "${_local_branches[@]}"; do
    [[ "$_b" == "$target_branch" ]] && continue
    git branch -D "$_b"
done
echo

echo -e "${GREEN}📋 Current branches:${RESET}"
git branch
echo

echo -e "${GREEN}✅ Repository successfully reset to clean '${target_branch}' state!${RESET}"
