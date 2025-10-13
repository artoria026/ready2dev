#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=git_ui.sh
source "$SCRIPT_DIR/git_ui.sh"

print_header "🌱 Git Create New Remote Branch"

# Get current branch
current_branch=$(git rev-parse --abbrev-ref HEAD)
echo -e "${BLUE}📍 Current branch: $current_branch${RESET}"

# Check if we have any changes to commit
git add .
if git diff-index --quiet HEAD --; then
    echo -e "${YELLOW}⚠️  No changes detected to commit.${RESET}"
    has_changes=false
else
    echo -e "${GREEN}📝 Changes detected and staged for commit.${RESET}"
    has_changes=true
fi

# Ask for branch name
echo
read -p "$(echo -e "${YELLOW}🏷️  Enter the new branch name (or press Enter to use current branch '$current_branch'): ${RESET}")" new_branch_name

# Use current branch if no name provided
if [[ -z "$new_branch_name" ]]; then
    new_branch_name="$current_branch"
    echo -e "${BLUE}Using current branch: $new_branch_name${RESET}"
else
    echo -e "${BLUE}New branch name: $new_branch_name${RESET}"
fi
echo

# Check if branch already exists remotely
echo -e "${CYAN}🔍 Checking if branch exists on remote...${RESET}"
if git ls-remote --heads origin "$new_branch_name" | grep -q "$new_branch_name"; then
    echo -e "${RED}❌ Branch '$new_branch_name' already exists on remote origin!${RESET}"
    echo -e "${YELLOW}💡 Use 'g_push' instead for existing branches.${RESET}"
    exit 1
fi
echo

# If we're not on the target branch, create and switch to it
if [[ "$current_branch" != "$new_branch_name" ]]; then
    echo -e "${MAGENTA}🔀 Creating and switching to branch '$new_branch_name'...${RESET}"
    git checkout -b "$new_branch_name" || {
        echo -e "${RED}❌ Failed to create branch '$new_branch_name'${RESET}"
        exit 1
    }
    echo
fi

# Commit changes if any
if [[ "$has_changes" == true ]]; then
    echo -e "${BLUE}💾 Committing changes...${RESET}"
    git commit || {
        echo -e "${RED}❌ Commit failed or was cancelled${RESET}"
        exit 1
    }
    echo
fi

# Push to origin and set upstream
run_step "Pushing '$new_branch_name' to origin and setting upstream" git push -u origin "$new_branch_name" || {
    echo -e "${RED}❌ Failed to push branch to origin${RESET}"
    exit 1
}

# Show final status
echo
echo -e "${GREEN}✅ Successfully created and pushed new branch '$new_branch_name'!${RESET}"
echo -e "${GREEN}✅ Upstream tracking has been set to origin/$new_branch_name${RESET}"
echo

echo -e "${CYAN}📋 Current git status:${RESET}"
git status
