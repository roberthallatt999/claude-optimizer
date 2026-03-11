#!/usr/bin/env bash
set -e

# Update the superpowers subtree from the forked repository
# Usage: ./update-superpowers.sh

REMOTE_URL="https://github.com/roberthallatt999/superpowers.git"
BRANCH="main"
PREFIX="superpowers"

echo "Pulling latest superpowers from ${REMOTE_URL}..."
git subtree pull --prefix="${PREFIX}" "${REMOTE_URL}" "${BRANCH}" --squash

echo "Superpowers updated successfully."
