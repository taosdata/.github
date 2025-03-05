#!/bin/bash
set -eo pipefail

# 接收参数
TARGET_PARENT_DIR="$1"
REPO_URL="$2"
BRANCH="$3"
GITHUB_TOKEN="$4"


################################################################
# Main Execution Flow
# Parameters:
#   $1: Target parent directory - REQUIRED
#   $2: Repository URL - REQUIRED
#   $3: Branch - REQUIRED
#   $4: GitHub token - REQUIRED
################################################################


# Validate mandatory parameters
if [[ $# -lt 4 ]]; then
  echo "::error::Missing required parameters"
  echo "Usage: $0 <target_parent_dir> <repo_url> <branch> <github_token>"
  exit 1
fi

# Get repo name
REPO_NAME=$(basename "$REPO_URL" .git)
TARGET_DIR="$TARGET_PARENT_DIR/$REPO_NAME"

# Export the target directory
# echo "TEST_ROOT=$TARGET_DIR" >> $GITHUB_ENV

# Create the target directory
mkdir -p "$TARGET_PARENT_DIR"

# Clone or update the repository
if [ -d "$TARGET_DIR" ] && [ "$(ls -A "$TARGET_DIR")" ]; then
  echo "🔄 Updating existing repository: $REPO_NAME"
  cd "$TARGET_DIR"

  # Check if the current branch is the same as the target branch
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
    echo "🔀 Switching to branch: $BRANCH"
    git fetch --all
    git checkout -f "$BRANCH"
  fi

  # Pull the latest changes
  echo "⬇️ Pulling latest changes..."
  git remote set-url origin "https://x-access-token:$GITHUB_TOKEN@${REPO_URL#https://}"
  git reset --hard origin/"$BRANCH"
else
  echo "🆕 Cloning new repository: $REPO_NAME"
  git clone -b "$BRANCH" "https://x-access-token:$GITHUB_TOKEN@${REPO_URL#https://}" "$TARGET_DIR"
fi