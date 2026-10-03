#!/usr/bin/env bash
#
# run-service-agent.sh APP — one agent run for one upstream app, start to PR.
# The control flow lives here (deterministic); Claude only does the three
# judgment steps, each as its own role from .claude/agents/:
#
#   1. research  service-researcher → .agent/APP/research.json (name, approach, contract)
#   2. scaffold  tools/new-service.sh (no AI)
#   3. author    service-author implements services/NAME and iterates on verify
#   4. verify    tools/verify-service.sh NAME (no AI); on failure the author
#                gets the log and another try, up to MAX_FIX times
#   5. review    service-reviewer → review.json; blocking issues → one more
#                author round + verify
#   6. guard     only services/NAME may have changed (no AI)
#   7. publish   branch svc/NAME → PR into BASE_BRANCH, labelled; a draft
#                if verify never passed or the review didn't approve
#
# Models: the workers (researcher, author) run on Sonnet, the validator
# (reviewer) on Opus — set in each role's frontmatter. The orchestration is
# this script, not a model.
#
# Claude's state for the run lives in .claude/.sessions (CLAUDE_CONFIG_DIR);
# the session transcripts under .claude/.sessions/projects/ are committed
# with the service as the record of what the agents did. MCP servers for the
# agents: .claude/mcp.json (mcp-nixos for package/option search).
#
# Needs: claude with CLAUDE_CODE_OAUTH_TOKEN (from `claude setup-token`),
# nix, git, gh (for publish), jq; the upstream mirror at .upstream
# (tools/upstream/checkout.sh). Run from the repo root on a clean tree.
# Env: BASE_BRANCH (default nightly), MAX_FIX (default 3), PUBLISH (default 1).

set -euo pipefail

APP="${1:?usage: run-service-agent.sh APP}"
BASE_BRANCH="${BASE_BRANCH:-nightly}"
MAX_FIX="${MAX_FIX:-3}"
PUBLISH="${PUBLISH:-1}"
WORK=".agent/${APP}"
mkdir -p "${WORK}"
export CLAUDE_CONFIG_DIR="${PWD}/.claude/.sessions"
mkdir -p "${CLAUDE_CONFIG_DIR}"
MCP=()
[[ -f .claude/mcp.json ]] && MCP=(--mcp-config .claude/mcp.json)
log() { printf '\n== %s\n' "$*"; }

[[ -z "$(git status --porcelain -- . ':!.agent' ':!.upstream' ':!.claude/.sessions')" ]] \
    || { echo "error: working tree not clean" >&2; git status --short >&2; exit 2; }
[[ -f ".upstream/ct/${APP}.sh" ]] || { echo "error: no upstream app ${APP} (run tools/upstream/checkout.sh)" >&2; exit 2; }

claude_run() {  # <agent> <transcript-name> <prompt>
    # --settings explicitly: a fresh CLAUDE_CONFIG_DIR has never trusted this
    # workspace, and an untrusted project's .claude/settings.json permissions
    # are ignored — every allowed command would be refused.
    claude -p --agent "$1" --permission-mode acceptEdits --settings .claude/settings.json \
        "${MCP[@]}" --output-format json "$3" \
        > "${WORK}/$2.json" 2> "${WORK}/$2.err" || true
    jq -r '.result // empty' "${WORK}/$2.json" 2>/dev/null | tail -30
}

# --- 1. research
log "research ${APP}"
claude_run service-researcher research "Research upstream app '${APP}'. Upstream mirror: .upstream/ (ct/${APP}.sh, install/${APP}-install.sh). Upstream metadata: $(tools/upstream/app-info.sh "${APP}" | jq -c .). Write your decision to ${WORK}/research.json."
jq -e . "${WORK}/research.json" >/dev/null || { echo "error: researcher wrote no valid ${WORK}/research.json" >&2; exit 1; }
if [[ "$(jq -r .feasible "${WORK}/research.json")" != true ]]; then
    echo "not feasible: $(jq -r .infeasible_reason "${WORK}/research.json")"
    exit 3
fi
NAME="$(jq -r .name "${WORK}/research.json")"
[[ "${NAME}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "error: bad service name '${NAME}'" >&2; exit 1; }
[[ ! -e "services/${NAME}" ]] || { echo "error: services/${NAME} already exists" >&2; exit 1; }

# --- 2. scaffold, on the publish branch
git checkout -q -B "svc/${NAME}"
tools/new-service.sh "${NAME}" "${APP}"

# --- 3+4. author, then verify with a bounded fix loop
author_prompt="Implement service '${NAME}' in services/${NAME}/ (scaffolded from the template). Research: ${WORK}/research.json. Iterate with tools/verify-service.sh ${NAME} --quick, then tools/verify-service.sh ${NAME}, until it passes."
log "author ${NAME}"
claude_run service-author author-0 "${author_prompt}"

verified=false
for i in $(seq 1 "${MAX_FIX}"); do
    log "verify ${NAME} (round ${i})"
    if tools/verify-service.sh "${NAME}" | tee "${WORK}/verify-${i}.out"; then verified=true; break; fi
    [[ "${i}" -lt "${MAX_FIX}" ]] || break
    log "author fix ${i}"
    claude_run service-author "author-fix-${i}" "tools/verify-service.sh ${NAME} fails. Its output:
$(tail -60 "${WORK}/verify-${i}.out")
Full logs are in .agent/${NAME}/. Fix services/${NAME}/ and re-run until it passes."
done

# --- 5. review (+ one round on blocking issues)
review() {
    claude_run service-reviewer "review-$1" "Review service '${NAME}' (services/${NAME}/). Research: ${WORK}/research.json. Write your review to ${WORK}/review.json."
    jq -e . "${WORK}/review.json" >/dev/null 2>&1 || echo '{"approved":false,"issues":[],"summary":"reviewer wrote no review.json"}' > "${WORK}/review.json"
}
approved=false
if ${verified}; then
    log "review ${NAME}"
    review 1
    if [[ "$(jq -r .approved "${WORK}/review.json")" != true ]]; then
        log "author: address review"
        claude_run service-author author-review "The reviewer found blocking issues in services/${NAME}/:
$(jq -c '[.issues[] | select(.severity == "blocking")]' "${WORK}/review.json")
Fix them, then make tools/verify-service.sh ${NAME} pass again."
        if tools/verify-service.sh "${NAME}" > "${WORK}/verify-post-review.out"; then review 2; else verified=false; fi
    fi
    [[ "$(jq -r .approved "${WORK}/review.json")" == true ]] && approved=true
fi

# --- 6. guard: nothing outside services/NAME (and the scratch dirs)
mapfile -t outside < <(git status --porcelain -- . ':!services/'"${NAME}" ':!.agent' ':!.upstream' ':!.claude/.sessions' | awk '{print $2}')
if (( ${#outside[@]} )); then
    echo "error: the agent changed files outside services/${NAME}/ — reverting them:" >&2
    printf '  %s\n' "${outside[@]}" >&2
    git checkout -- "${outside[@]}" 2>/dev/null || true
    git clean -fdq -- "${outside[@]}" 2>/dev/null || true
fi

# --- 7. publish
jq -n --arg app "${APP}" --arg name "${NAME}" --argjson verified "${verified}" --argjson approved "${approved}" \
    '{app: $app, service: $name, verified: $verified, approved: $approved}' | tee "${WORK}/outcome.json"
git add "services/${NAME}"
git add .claude/.sessions/projects 2>/dev/null || true
git commit -q -m "services/${NAME}: add (upstream ${APP})

Approach: $(jq -r .approach "${WORK}/research.json") — $(jq -r .approach_reason "${WORK}/research.json")
Verified: ${verified} · review approved: ${approved}

Co-Authored-By: Claude <noreply@anthropic.com>"

[[ "${PUBLISH}" == 1 ]] || { log "PUBLISH=0: committed on svc/${NAME}, not pushed"; exit 0; }

body="${WORK}/pr.md"
{
    echo "Agent run for upstream app \`${APP}\` → \`services/${NAME}\`."
    echo
    echo "| | |"; echo "|---|---|"
    echo "| approach | \`$(jq -r .approach "${WORK}/research.json")\`: $(jq -r .approach_reason "${WORK}/research.json") |"
    echo "| verify (eval, image, compose, parity) | $(${verified} && echo pass || echo '**fail**') |"
    echo "| review | $(${approved} && echo approved || echo '**not approved**') |"
    echo
    echo "### Review"; echo; jq -r '.summary' "${WORK}/review.json" 2>/dev/null || echo "_no review_"
    jq -r '.issues[]? | "- **\(.severity)** `\(.file)`: \(.problem)"' "${WORK}/review.json" 2>/dev/null || true
    echo; echo "### Verify"; echo; echo '```'; jq . .agent/"${NAME}"/verify.json 2>/dev/null; echo '```'
} > "${body}"

for l in "service:${NAME}" ai-generated needs-human; do
    gh label create "${l}" --force --color "$([[ ${l} == needs-human ]] && echo d93f0b || echo 5319e7)" >/dev/null 2>&1 || true
done
git push -q -f origin "svc/${NAME}"
labels="service:${NAME},ai-generated"
draft=()
if ! ${verified} || ! ${approved}; then labels+=",needs-human"; draft=(--draft); fi
if ! gh pr create --base "${BASE_BRANCH}" --head "svc/${NAME}" "${draft[@]}" \
        --title "services/${NAME}: add (upstream ${APP})" --label "${labels}" --body-file "${body}"; then
    # Typically the org setting "Allow GitHub Actions to create and approve
    # pull requests" being off. The work is on the branch either way.
    echo "::warning::could not open the PR; branch svc/${NAME} is pushed — open it from there (body: ${body})"
fi
