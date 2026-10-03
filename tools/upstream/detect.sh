#!/usr/bin/env bash
#
# detect.sh [BASE [HEAD]] — upstream container apps that need an agent run:
# apps whose ct/APP.sh or install/APP-install.sh changed between two mirror
# commits (or every app, with no BASE), minus apps that already have a
# service here (services/*/upstream.json → .app). One app id per line.
#
# Containers only for now: vm/, tools/ and turnkey/ are ignored.

set -euo pipefail

UP="${UPSTREAM_DIR:-.upstream}"
BASE="${1:-}"
HEAD="${2:-HEAD}"

if [[ -n "${BASE}" ]]; then
    git -C "${UP}" diff --name-only "${BASE}" "${HEAD}" -- ct install
else
    git -C "${UP}" ls-tree --name-only "${HEAD}" ct/
fi \
    | sed -n -e 's|^ct/\(.*\)\.sh$|\1|p' -e 's|^install/\(.*\)-install\.sh$|\1|p' \
    | sort -u \
    | while read -r app; do
        # Still a container app at HEAD (deleted/renamed ones drop out).
        git -C "${UP}" cat-file -e "${HEAD}:ct/${app}.sh" 2>/dev/null && echo "${app}"
    done \
    | grep -vxF -f <(cat services/*/upstream.json 2>/dev/null | jq -r '.app' ; echo "__none__") \
    || true
