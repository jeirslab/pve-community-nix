#!/usr/bin/env bash
#
# checkout.sh [REF] — put the upstream mirror (branch official-community-scripts,
# a plain copy of community-scripts/ProxmoxVE) at $UPSTREAM_DIR (default
# .upstream, gitignored) as a detached worktree, for app-info.sh / detect.sh
# and for agents to read the original scripts. Read-only reference material.

set -euo pipefail

UP="${UPSTREAM_DIR:-.upstream}"
REF="${1:-official-community-scripts}"

git fetch -q origin "${REF}"
rev="$(git rev-parse FETCH_HEAD)"
if [[ -e "${UP}/.git" ]]; then
    git -C "${UP}" checkout -q --detach "${rev}"
else
    git worktree add -q --detach "${UP}" "${rev}"
fi
echo "${UP} at $(git -C "${UP}" rev-parse --short HEAD) ($(git -C "${UP}" log -1 --format=%cs))"
