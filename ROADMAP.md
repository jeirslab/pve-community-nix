# ROADMAP — full Nix-declarative Proxmox catalog

Turns `pve-community-nix` into the estate's single, Nix-declarative source of
service modules **and** PVE utilities — the whole community-scripts surface,
minus their telemetry and branding, consumed by fleetkit. The integration
boundary is [ADR-0001](docs/adr/0001-catalog-as-fleetkit-submodule.md): fleetkit
consumes this repo as a `flake = false` `git+file` submodule and folds its
checks into one gate. Everything below builds on that.

Guiding rules (hold for every phase):
- **No telemetry, ever.** community-scripts installs monitoring by default; no
  ported item may carry it (Phase 2).
- **Branding is declarative, not theirs** (Phase 2).
- **`nix flake check` is the judge** — LLM-drafted work lands as a *draft* PR
  that must pass; never auto-merge.
- **The status registry prevents loops** (Phase 1): nothing is retried forever.

## Phase 0 — Integration boundary (ADR-0001)

Make fleetkit consume the catalog:
- Add this repo as a git submodule under `fleetkit/submodules/pve-community-nix`;
  wire `inputs.catalog = { url = "git+file:./submodules/pve-community-nix"; flake = false; }`.
- fleetkit imports the catalog's modules (`nix/fleet`, `nix/modules/apps`) and
  its check *definitions*, folding the light checks into its `nix flake check`.
- Keep this repo's standalone flake (inputs fleetkit from GitHub) for isolated
  dev + the heavy `ported-apps` build-per-app CI.
- nexus: `.syncignore` so the canonical checkout is the one inside fleetkit;
  the two gitlinks move together (xgcs-deployments precedent).
- Revise AGENTS.md (the "consumer-side / never vendor" framing is superseded).

## Phase 1 — Implementation-status registry (source of truth for automation)

Extend the preset schema into a full lifecycle the workflows read, covering
**both app modules and PVE utilities** (not just apps):

- `implemented` — a Nix module / ansible role exists and passes checks
  (today's `ported`/`verified`).
- `pending` — known upstream item, not yet ported (the work queue).
- `not-applicable` — moot under Nix, with a reason (e.g. their config-file
  *templating* is redundant when we are already declarative).
- `impossible` — cannot be expressed here, with a reason (loop-prevention
  backstop; expected to be rare/empty).

Surface it in `catalog-json` (the eval-free artifact `fleet apps` / `fleet pve`
already read) so both humans and the workflows can answer "done vs pending vs
skip". This registry is what makes Phase 4 bounded.

## Phase 2 — De-brand + de-telemetry (safety-critical, every ported item)

A shared sanitize contract every port must satisfy, enforced by a check:
- **Strip telemetry** — the `source <(curl … api.func)` / init_tool_telemetry
  fetches (already done for post-install); no network callbacks to upstream.
- **Branding is a declarative option, not theirs.** Replace the hard-coded
  community-scripts LXC tags, the PVE **Notes** section (logo + repo link), and
  the installed **MOTD** with `catalog.branding = { tags; notes; motd; }` —
  default to fleetkit/estate branding or none, never theirs.

## Phase 3 — Engine: ansible + Python, not raw shell

Replace the bash execution layer:
- A **Python implementation layer** for complex logic/orchestration that runs
  **ansible playbooks via ansible-runner** (pyansible). fleetkit already carries
  the ansible layer (non-NixOS guests + hypervisor management) — reuse it, don't
  re-vendor.
- Playbooks **call shell scripts directly** when no variable injection is
  needed; only **template** a script when ansible vars must land at specific
  points. (Prefer running shell-as-written over rewriting it into ansible tasks.)
- **Convert the `nix run` post-install** (the routine we shipped) to this
  engine: `nix run` stays the entrypoint but drives ansible-runner, gaining
  structured/parseable outputs instead of scraping stdout.

## Phase 4 — The two drafting workflows (endpoint: ai.jeirslab.xyz)

Both call the self-hosted OpenAI-compatible endpoint `ai.jeirslab.xyz`
(cli-proxy → Claude models: fable/opus; API key via repo secret). Because a
GitHub-hosted runner can't reach the tailnet, both run on the **self-hosted
runner** (the fleetkit `infra.build.githubRunner` module) or the endpoint is
exposed public+authenticated.

- **(a) upstream-triggered auto-draft** — on updates to the upstream mirror
  branch (**`official-community-scripts`** — note: not `original`), diff against
  last-synced state and, for each **new OR changed** item, send it + the porting
  conventions (the existing `port-upstream-app` skill's logic as the prompt) to
  the endpoint → draft preset + module/role → `nix flake check` → open a **draft
  PR**. On check failure, feed the errors back for a bounded retry. Monitors
  changes-to-existing, not just new arrivals.
- **(b) pick-one-unimplemented** — schedule/manual trigger: read the status
  registry (Phase 1), pick one `pending` item, draft via the same
  endpoint→check→draft-PR loop. Bounded by the registry (skips
  `not-applicable`/`impossible`) so it can't loop forever.

## Phase 5 — Coverage: utilities, non-NixOS apps, templates

- **PVE utility scripts** (pve8/pbs upgrades, update-lxcs, update-repo, …) →
  `nix run`/ansible, declarative, same de-brand/de-telemetry contract.
- **Non-NixOS apps** (cannot be a NixOS module) → provision the same shape as a
  NixOS host, but as a **terranix-created guest (bpg/proxmox) + an ansible role**
  running the adapted installer. `impl` routes `nixos-*` vs `ansible-lxc`.
- **Upstream "template" functionality** → assess per item: config-file
  templating is largely `not-applicable` (we're declarative); any real
  LXC/VM template-build aspect maps onto fleetkit's images family, not a
  reimplementation here.

## Phase 6 — Consolidate estate service modules (last)

Once the boundary + pipeline are proven, migrate the app/service modules that
currently live in consumer repos (homelab: authentik, mealie, wger, …) into the
catalog, so it is genuinely the single source.

## Verification / guardrails

- `nix flake check` green both folded-into-fleetkit (light) and standalone
  (heavy `ported-apps`).
- A **no-telemetry / no-foreign-branding** check fails any port that reintroduces
  either.
- LLM output is **draft-PR only**; CI + human review gate every merge.
- The status registry is authoritative — workflows never act outside it.
