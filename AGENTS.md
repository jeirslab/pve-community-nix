# AGENTS.md — operating manual for AI agents

This repo is fleetkit's **catalog of service modules + PVE utilities**,
consumed BY fleetkit as a `flake = false` git+file submodule — see
[ADR-0001](docs/adr/0001-catalog-as-fleetkit-submodule.md), which **supersedes
the former "consumer-side catalog" framing** (the dependency direction is now
fleetkit → catalog). fleetkit's
[AGENTS.md](https://github.com/alexanderjerome/fleetkit/blob/main/AGENTS.md)
iron rules apply verbatim; these are the additions.

## What this is

Per-application presets (`fleet.catalog.apps.<name>`), the `mkApp`
helper, NixOS app modules (`apps.<name>`), PVE-host tooling, a consumer
template, and docs. The provisioning **engine** — fleet schema, terranix
emitters, images, CLI, ansible layer — still lives in fleetkit: use it, never
reimplement or vendor it here. What reversed (ADR-0001) is *consumption*:
fleetkit now imports this catalog's source, so the catalog's components follow
fleetkit's **`mkComponent` + committed-interface-schema + `component-*` check
system** (`nix/lib/mkComponent.nix`, `nix/components/`), folded into fleetkit's
single `nix flake check`. Direction + phased plan: ADR-0001 and
[ROADMAP.md](ROADMAP.md) (the historical `PLAN.md` predates the reversal).

## Iron rules (additions)

1. **Presets are data.** `nix/catalog/*.nix` may not reference `pkgs`,
   NixOS options, or `config` beyond `fleet.catalog`. They are evaluated
   by fleetkit's plain fleet eval as well as by every NixOS host.
2. **No site values.** RFC5737 addresses and `example.*` domains in every
   example and in the template. Timezone, ports, datastores, bridges are
   options or consumer overrides.
3. **`impl` is honest.** An entry is `nixos-service` / `package-systemd` /
   `oci` / `image` only when `nix/modules/apps/<nixModule>/` exists and
   evaluates; `status = "verified"` only after a real PVE 9 deploy.
   Anything that cannot be a NixOS host is `unsupported` with a reason.
4. **Attribution travels.** Every entry keeps `upstream.{url,repo,license}`
   and `legacy.{ct,install}` back-references.
5. **`nix flake check` is the acceptance gate**: `catalog-schema`,
   `example-consumer`, `tf-render`, `docs`, `ported-apps` (every module with
   status ported evaluates enabled).
6. **`legacy/` is read-only.** Never fix or extend the bash tree.

## Discovering the API

- `nix build .#docs` → options + catalog site.
- `nix build .#catalog-json` → the catalog as JSON (what `fleet apps` reads).
- `templates/consumer/` → a complete working consumer.
- [ADR-0001](docs/adr/0001-catalog-as-fleetkit-submodule.md) + [ROADMAP.md](ROADMAP.md)
  → the current direction, the checks/schema contract, and the phased bulk-work
  order (helpers + core → LXCs → VMs). `PLAN.md` is historical (pre-ADR-0001).

## Contribution shape

Small verified steps: change → `nix flake check` → conventional commit.
Ask "would this hold for a two-host homelab on one PVE node?".
