# How services are built

A service is a directory `services/<name>/` that declares a **contract**
(what it is, its environment variables, ports, healthcheck) and a **NixOS
module** (usually configuring an existing nixpkgs module). The framework in
`lib/` turns that into everything else.

| File | Holds |
|---|---|
| `default.nix` | the contract, and the imports of the files below |
| `options.nix` | options beyond the standard `enable` / `environmentFile` / `openFirewall` |
| `configuration.nix` | the NixOS configuration, mapping env vars onto the service |
| `scripts.nix` | setup scripts the service needs (first-run, migrations) |
| `docker.nix` | container-only needs: extra volumes, extra image contents |
| `check.nix` | test values for the parity test, and extra test steps |
| `upstream.json` | which upstream app this follows, and why its approach was chosen |
| `README.md` | anything a human needs beyond the generated docs |

## Two ways to get a container from a NixOS service

- **extracted**: the NixOS module is evaluated and its systemd unit
  (start command, environment, pre-start, data directories) is lifted into
  a single-process image. Works with any existing nixpkgs module. What stays
  behind is systemd itself: sandboxing, dynamic users and timers.
- **modular**: the service is a nixpkgs *modular service*, whose process
  definition doesn't depend on systemd, so the image runs it directly. Newer
  and still experimental in nixpkgs.

Each service records its choice and the reason in `upstream.json`.

## The parity test

`checks.<service>-parity` boots two VMs: one runs the NixOS module under
systemd, the other loads the image into podman. Both get the same env file;
both must answer the same healthcheck.
