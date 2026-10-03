#!/usr/bin/env bash
#
# verify-service.sh NAME [--quick] — everything that must pass before a
# service can merge, in order, stopping at the first failure:
#   eval     the NixOS system with the service enabled evaluates
#   image    the container image builds
#   compose  the compose snippet renders
#   parity   (skipped with --quick) the VM test: NixOS module under systemd
#            and the image under podman, same env, same healthcheck
#
# Logs: .agent/NAME/verify-<stage>.log; summary: .agent/NAME/verify.json.
# Exit 0 only if every stage that ran passed.

set -uo pipefail

NAME="${1:?usage: verify-service.sh NAME [--quick]}"
QUICK="${2:-}"
SYSTEM="${SYSTEM:-x86_64-linux}"
OUT=".agent/${NAME}"
mkdir -p "${OUT}"
[[ -d "services/${NAME}" ]] || { echo "error: services/${NAME} not found" >&2; exit 2; }

# Flakes only see files git knows about; a new service is untracked.
git add --intent-to-add "services/${NAME}" 2>/dev/null || true

stages=(eval image compose)
[[ "${QUICK}" == "--quick" ]] || stages+=(parity)
declare -A attr=(
    [eval]=".#checks.${SYSTEM}.${NAME}-eval"
    [image]=".#packages.${SYSTEM}.${NAME}-image"
    [compose]=".#packages.${SYSTEM}.${NAME}-compose"
    [parity]=".#checks.${SYSTEM}.${NAME}-parity"
)

results="{}"; rc=0
for s in "${stages[@]}"; do
    log="${OUT}/verify-${s}.log"
    start=$(date +%s)
    if nix build -L --no-link --print-out-paths "${attr[$s]}" > "${log}" 2>&1; then
        status=pass
    else
        status=fail; rc=1
    fi
    secs=$(( $(date +%s) - start ))
    echo "${s}: ${status} (${secs}s)"
    results="$(jq -c --arg s "${s}" --arg st "${status}" --argjson t "${secs}" --arg log "${log}" \
        '.[$s] = {status: $st, seconds: $t, log: $log}' <<< "${results}")"
    if [[ "${status}" == fail ]]; then
        echo "--- last lines of ${log}:"
        grep -v '^warning\|evaluation warning\|^copying path\|^these \|^  /nix' "${log}" | tail -40
        break
    fi
done

jq -n --arg name "${NAME}" --argjson r "${results}" --argjson ok "$([[ ${rc} == 0 ]] && echo true || echo false)" \
    '{service: $name, ok: $ok, stages: $r}' > "${OUT}/verify.json"
exit "${rc}"
