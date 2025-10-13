#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=git_ui.sh
source "$SCRIPT_DIR/git_ui.sh"

print_header "🚀 Git Push"

current_branch=$(git rev-parse --abbrev-ref HEAD)
echo -e "${BLUE}📍 Current branch: $current_branch${RESET}"
echo

git add .

if git diff-index --quiet HEAD --; then
    echo -e "${YELLOW}⚠️  No changes to commit.${RESET}"
else
    echo -e "${BLUE}📝 Committing changes...${RESET}"
    git commit
    echo

    run_step "Pushing to origin/$current_branch" git push origin "$current_branch" || exit 1
    echo

    git status
    echo -e "${GREEN}✅ Changes committed and pushed to origin/$current_branch.${RESET}"
fi
