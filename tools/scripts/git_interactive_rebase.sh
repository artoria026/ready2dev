#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=git_ui.sh
source "$SCRIPT_DIR/git_ui.sh"

print_header "🌿 Git Interactive Rebase"

# Get the current branch
current_branch=$(git rev-parse --abbrev-ref HEAD)
echo -e "${BLUE}📍 Current branch: $current_branch${RESET}"
echo

# Select base branch
echo -e "${CYAN}Select the base branch to rebase from:${RESET}"
echo -e "  1) master"
echo -e "  2) master-stage ${GREEN}(default)${RESET}"
echo -e "  3) main"
echo -e "  4) Enter a custom branch name"
echo
read -rp "$(echo -e "${YELLOW}👉 Option [1/2/3/4] (press Enter for master-stage): ${RESET}")" BRANCH_CHOICE

case "$BRANCH_CHOICE" in
    1)
        base_branch="master"
        ;;
    3)
        base_branch="main"
        ;;
    4)
        read -rp "$(echo -e "${YELLOW}✏️  Enter branch name: ${RESET}")" custom_branch
        if [[ -z "$custom_branch" ]]; then
            echo -e "${RED}❌ Error: Branch name cannot be empty.${RESET}"
            exit 1
        fi
        base_branch="$custom_branch"
        ;;
    *)
        base_branch="master-stage"
        ;;
esac

echo
echo -e "${BLUE}📌 Base branch: ${base_branch}${RESET}"
echo

# Check if we are already on the base branch
if [[ "$current_branch" == "$base_branch" ]]; then
    echo -e "${RED}❌ Error: You are already on '${base_branch}'. Cannot rebase a branch onto itself.${RESET}"
    exit 1
fi

# Verify the base branch exists locally or remotely
if ! git show-ref --verify --quiet "refs/heads/${base_branch}" && \
   ! git show-ref --verify --quiet "refs/remotes/origin/${base_branch}"; then
    echo -e "${RED}❌ Error: Branch '${base_branch}' not found locally or in origin.${RESET}"
    exit 1
fi

# Ensure base branch is up to date
git checkout "$base_branch" || exit 1
run_step "Fetching latest changes" git fetch origin

if git show-ref --verify --quiet "refs/remotes/origin/${base_branch}"; then
    run_step "Pulling latest ${base_branch}" git pull origin "$base_branch" || exit 1
else
    echo -e "${BLUE}ℹ️  '${base_branch}' has no remote copy on origin — skipping pull, using local state.${RESET}"
fi
echo

# Switch back to the original branch
echo -e "${YELLOW}🔙 Switching back to $current_branch...${RESET}"
git checkout "$current_branch" || exit 1
echo

# Determine the merge base
merge_base=$(git merge-base "$base_branch" "$current_branch")

# Perform the interactive rebase
echo -e "${GREEN}✨ Starting interactive rebase from $merge_base (base: ${base_branch})...${RESET}"
git rebase -i "$merge_base"
