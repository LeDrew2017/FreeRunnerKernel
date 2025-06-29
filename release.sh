#!/bin/bash

# Ensure clean exit on errors
set -e

# Repo info
REPO="git@github.com:LeDrew2017/FreeRunnerKernel.git"
REPO_NAME="LeDrew2017/FreeRunnerKernel"
FILES_DIR="/home/jay/bootimages/freerunnerkernel"

# Prompt for release tag
read -p "Enter the tag version (e.g. v2.7): " TAG

# Clone repo to a temporary directory and tag
TMPDIR=$(mktemp -d)
cd "$TMPDIR"

git clone --depth=1 "$REPO"
cd FreeRunnerKernel

# Create the tag and push
git tag "$TAG"
git push origin "$TAG"

# Use the default editor for title and description prompt
gh release create "$TAG" \
  --repo "$REPO_NAME" \
  "$FILES_DIR"/*.img "$FILES_DIR"/*.tar

# Cleanup
cd ~
rm -rf "$TMPDIR"

echo "✅ Release $TAG created using your default editor."

