#!/usr/bin/env bash
#
# new-service.sh NAME APP — create services/NAME from templates/service,
# filled in from what upstream says about APP (tools/upstream/app-info.sh).
# NAME is our service name (usually the nixpkgs name, e.g. uptime-kuma);
# APP is the upstream app id (e.g. uptimekuma).

set -euo pipefail

NAME="${1:?usage: new-service.sh NAME APP}"
APP="${2:?usage: new-service.sh NAME APP}"
[[ "${NAME}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "error: NAME must be lowercase letters, digits, dashes" >&2; exit 1; }
DIR="services/${NAME}"
[[ ! -e "${DIR}" ]] || { echo "error: ${DIR} already exists" >&2; exit 1; }

info="$(tools/upstream/app-info.sh "${APP}")"
field() { jq -r "$1 // \"\"" <<< "${info}"; }

mkdir -p services
cp -r templates/service "${DIR}"
# sed replacement text: escape \ & and the | delimiter.
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }
for f in "${DIR}"/*; do
    sed -i.bak \
        -e "s|__NAME__|$(esc "${NAME}")|g" \
        -e "s|__APP__|$(esc "${APP}")|g" \
        -e "s|__TITLE__|$(esc "$(field .title)")|g" \
        -e "s|__DESCRIPTION__|$(esc "$(field .title) (TODO: one-line description)")|g" \
        -e "s|__SOURCE__|$(esc "$(field '.github // .homepage')")|g" \
        -e "s|__COMMIT__|$(esc "$(field .upstream_commit)")|g" \
        -e "s|__RESOURCES__|$(esc "$(jq -c .resources <<< "${info}")")|g" \
        "${f}"
    rm -f "${f}.bak"
done
jq . "${DIR}/upstream.json" >/dev/null
echo "created ${DIR} from upstream app ${APP}"
