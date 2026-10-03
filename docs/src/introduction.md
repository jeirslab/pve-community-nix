# Introduction

Self-hosted applications, each packaged twice from one definition:

- a **NixOS module** for NixOS hosts, VMs and containers, and
- a **container image** (`ghcr.io/jeirslab/svc/<name>`) with a ready
  docker-compose snippet, for Docker and Coolify.

Both are built from the same NixOS service definition and are tested
against each other: every service has a parity test that runs it natively
under systemd and as its image under podman, with the same configuration,
and requires the same healthcheck to pass on both. What you run in Docker
during development is what runs on NixOS in production.

The list of applications follows the
[Proxmox VE community scripts](https://github.com/community-scripts/ProxmoxVE)
as a reference, not an authority: an app is added here when it can be built
from nixpkgs to this standard.
