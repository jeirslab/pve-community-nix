# AGENTS.md — rules for agents working in this repo

This repo packages self-hosted apps as NixOS service modules, each with a
container image built from the same definition and a parity test proving
the two behave the same. The app list follows the Proxmox VE community
scripts (mirrored on branch `official-community-scripts`) as a reference,
not an authority.

## Layout

| Path | Owner | What |
|---|---|---|
| `lib/` | humans | the framework: contract, image backends, compose, checks, docs |
| `tools/` | humans | deterministic scripts (upstream metadata, scaffold, verify, the agent pipeline) |
| `templates/service/` | humans | what every service starts from |
| `services/<name>/` | **agents** | one directory per service — the only place agents write |
| `.agent/`, `.upstream/` | scratch | gitignored: agent work files, the upstream mirror checkout |

## Iron rules

1. **An agent edits only `services/<name>/` for the service it was given.**
   `tools/agent/run-service-agent.sh` reverts anything else, and
   `.claude/settings.json` denies writes to `lib/`, `tools/`, `templates/`,
   `.github/`, `.claude/`.
2. **`tools/verify-service.sh <name>` is the acceptance gate**: eval, image,
   compose, and the parity VM test. Nothing merges red.
3. **All configuration is environment variables declared in the contract.**
   Defaults live in the contract so they apply to NixOS and the container
   identically. No hard-coded site values, hostnames or credentials.
4. **Prefer nixpkgs.** Configure an existing nixpkgs module rather than
   writing a systemd unit; package nothing that nixpkgs already has.
5. **Setup runs in preStart** (scripts.nix), so it runs in the container
   too, as the unprivileged service user.
6. **Record decisions** in `upstream.json` → `decision` (approach and why).

## Branches

- `unstable` — the framework (lib, tools, templates, workflows). Human work.
- `nightly` — agent-written services, one PR per service from `svc/<name>`.
- `stable` — releases; consumers pin to it.
- `official-community-scripts` — untouched mirror of upstream.
- `main` — the earlier layout; frozen, not referenced.

## Commands

```bash
tools/upstream/checkout.sh               # upstream mirror → .upstream/
tools/upstream/detect.sh [BASE [HEAD]]   # apps needing an agent run
tools/upstream/app-info.sh <app>         # upstream metadata as JSON
tools/new-service.sh <name> <app>        # scaffold services/<name>
tools/verify-service.sh <name> [--quick] # the acceptance gate
tools/agent/run-service-agent.sh <app>   # one full agent run → PR
nix flake check                          # framework self-test (fixture) + every service
nix build .#docs                         # mdBook site
```
