# ADR-0001 — The catalog is a fleetkit submodule; fleetkit consumes it

- Status: Accepted
- Date: 2026-09-14
- Supersedes: the "consumer-side catalog / never vendor" framing in AGENTS.md
  (to be revised to match this decision).

## Context

`pve-community-nix` is a comprehensive catalog: per-app presets, NixOS app
modules (`apps.<name>`), and the PVE-host utilities (post-install, upgrades,
LXC maintenance) ported from the community-scripts project. Today it is a
**downstream flake that consumes fleetkit** (`inputs.fleetkit`), and AGENTS.md
frames it as a consumer-side catalog whose engine lives in fleetkit.

We want three things that framing does not give us:

1. **The catalog to be THE source of service modules and PVE utilities** for
   every fleetkit-based estate — one place those live, not scattered across
   consumer repos (homelab, XGCS).
2. **One validation gate.** fleetkit's `nix flake check` should evaluate the
   catalog too, so engine + catalog are proven together, not in two repos that
   can drift.
3. **A single distribution.** A consumer should get engine + catalog from one
   fleetkit input, not two.

The obvious objection — bundling the catalog bloats fleetkit's install/eval —
does not hold: NixOS modules are lazy, and the catalog's `apps.<name>` modules
are inert unless enabled by `mkApp`. A consumer enabling five apps out of
hundreds pays for five (option declarations are cheap; `config` is behind
`mkIf`). The only cost that scales with the catalog is *building a toplevel per
app*, which is a CI concern, addressed below.

## Decision

1. **Reverse the dependency direction: fleetkit consumes `pve-community-nix`**,
   tracked as a **git submodule inside fleetkit** and wired as a
   **`flake = false` `git+file`** input
   (`inputs.catalog = { url = "git+file:./submodules/pve-community-nix"; flake = false; }`).
   fleetkit then imports the catalog's source directly
   (`${inputs.catalog}/nix/fleet`, `${inputs.catalog}/nix/modules/apps`, and its
   check definitions).

2. **`flake = false` is load-bearing — it breaks the input cycle.** The catalog
   still declares `inputs.fleetkit` for its own standalone use; `flake = false`
   means fleetkit imports the catalog's *source tree* without evaluating its
   flake, so that `inputs.fleetkit` is never resolved from within fleetkit.
   fleetkit → catalog → fleetkit is therefore not a Nix input cycle. This is the
   same pattern homelab already uses for `git+file:./submodules/xgcs/deployments`.

3. **The catalog mirrors fleetkit's check conventions and exposes its checks as
   importable definitions** (functions of `{ pkgs, lib, fleetkit-context }`),
   not just as `flake.checks` outputs — so fleetkit folds them into its own
   `nix flake check`.

4. **Heavy validation stays in the catalog's standalone CI.** The catalog keeps
   its own flake (inputs fleetkit from GitHub) and runs the expensive
   `ported-apps` build-a-toplevel-per-app check there, where it scales
   independently. fleetkit's folded gate runs the *light* checks — catalog
   schema, integration eval, a representative subset of toplevels — so adding
   apps does not linearly inflate fleetkit's CI.

5. **The catalog's modules must work both ways** — imported into fleetkit's eval
   (fleetkit supplies `lib` / fleet schema natively) and standalone via the
   flake. Written as plain modules taking schema/lib through module args, they
   already do; this becomes a hard rule.

## Consequences

- **Positive**: one input and one validation gate for engine + catalog;
  the catalog becomes the estate's single source of service modules + PVE
  utilities; consumers get everything transitively, inert until enabled.
- **Negative / watch**:
  - fleetkit is no longer a *minimal* engine — its scope now includes the
    catalog surface. The "everything here is load-bearing" rule is preserved by
    keeping the catalog a submodule (removable boundary), not inlined files.
  - CI time: mitigated by (4) — build-per-app lives in the catalog's CI.
  - **nexus double-pins the catalog** (top-level `jeirslab/pve-community-nix`
    *and* inside `jeirslab/fleetkit/submodules/`). Resolve via `.syncignore`:
    the canonical checkout is the one inside fleetkit; the two gitlinks move
    together (the xgcs-deployments precedent in the nexus CLAUDE.md).
  - The catalog dual-inputs fleetkit (standalone) while fleetkit `flake=false`-
    imports the catalog — a deliberate asymmetry that must be documented so it
    is not "fixed" into a cycle.

## Alternatives considered

- **Keep two separate flakes** (status quo): consumers add two inputs; the
  catalog is validated in its own repo only, free to drift from the engine it
  targets. Rejected — fails goals 1–3.
- **fleetkit takes the catalog as a normal (`flake = true`) input**: an
  outright input cycle (catalog inputs fleetkit). Impossible in Nix.
- **Inline the catalog into fleetkit's own tree** (no submodule): loses the
  independent history, the standalone dev flake, and the removable boundary
  that keeps fleetkit's "load-bearing" rule honest. Rejected.
