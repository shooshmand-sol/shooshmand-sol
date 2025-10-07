#!/usr/bin/env bash
# send-status-check-gh.sh
# Usage:
# ./send-status-check-gh.sh <owner> <repo> <sha> <state> <context> <description> [target_url]
#
# Example:
# ./send-status-check-gh.sh myuser myrepo a1b2c3d4 success "external/lint" "Lint passed" "https://ci.example.com/build/123"

set -euo pipefail

if [ "$#" -lt 6 ]; then
  echo "Usage: $0 <owner> <repo> <sha> <state> <context> <description> [target_url]"
  echo "state must be one of: error, failure, pending, success"
  exit 1
fi

OWNER=$1
REPO=$2
SHA=$3
STATE=$4
CONTEXT=$5
DESCRIPTION=$6
TARGET_URL=${7:-}

echo "Sending status '${STATE}' for ${OWNER}/${REPO}@${SHA} with context '${CONTEXT}'"

# Build the gh api arguments dynamically
ARGS=(
  --method POST
  "/repos/${OWNER}/${REPO}/statuses/${SHA}"
  -f state="${STATE}"
  -f context="${CONTEXT}"
  -f description="${DESCRIPTION}"
  -H "Accept: application/vnd.github+json"
)

# Add target_url if provided
if [ -n "${TARGET_URL}" ]; then
  ARGS+=(-f target_url="${TARGET_URL}")
fi

gh api "${ARGS[@]}"