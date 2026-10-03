#!/usr/bin/env bash
#
# app-info.sh APP — what the upstream community scripts say about one app,
# as JSON: title, source URL, tags, and the resources its LXC gets. Read from
# the header of ct/APP.sh, where every app declares APP= and var_*=.
#
# Reads the mirror checkout at $UPSTREAM_DIR (default .upstream; see
# tools/upstream/checkout.sh).

set -euo pipefail

APP="${1:?usage: app-info.sh APP}"
UP="${UPSTREAM_DIR:-.upstream}"
CT="${UP}/ct/${APP}.sh"
[[ -f "${CT}" ]] || { echo "error: ${CT} not found (is ${UP} checked out?)" >&2; exit 1; }

# var_x="${var_x:-VALUE}" → VALUE
var() { sed -n "s/^var_$1=\"\${var_$1:-\(.*\)}\".*/\1/p" "${CT}" | head -1; }

title="$(sed -n 's/^APP="\(.*\)".*/\1/p' "${CT}" | head -1)"
source_line="$(grep -m1 '^# Source:' "${CT}" || true)"
homepage="$(sed -n 's/^# Source: *\([^ |]*\).*/\1/p' <<< "${source_line}")"
github="$(sed -n 's/.*Github: *\([^ ]*\).*/\1/p' <<< "${source_line}")"
commit="$(git -C "${UP}" rev-parse HEAD 2>/dev/null || echo unknown)"
install="install/${APP}-install.sh"
[[ -f "${UP}/${install}" ]] || install=""

jq -n \
    --arg app "${APP}" --arg title "${title}" --arg homepage "${homepage}" --arg github "${github}" \
    --arg commit "${commit}" --arg install "${install}" \
    --arg tags "$(var tags)" --arg cpu "$(var cpu)" --arg ram "$(var ram)" --arg disk "$(var disk)" \
    --arg os "$(var os)" --arg version "$(var version)" '
    {
      app: $app, title: $title,
      homepage: ($homepage | select(. != "")), github: ($github | select(. != "")),
      upstream_commit: $commit,
      scripts: { ct: "ct/\($app).sh", install: ($install | select(. != "")) },
      tags: ($tags | split(";") | map(select(. != ""))),
      resources: { cpu: ($cpu | tonumber? // null), ram_mb: ($ram | tonumber? // null),
                   disk_gb: ($disk | tonumber? // null), os: $os, os_version: $version }
    }'
