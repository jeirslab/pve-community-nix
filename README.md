# pve-community-nix

Self-hosted apps as **NixOS service modules** and **container images built
from the same definition**, with a test per app that proves both behave the
same. Develop against the image in Docker or Coolify; deploy the module on
NixOS.

- Images: `ghcr.io/jeirslab/svc/<name>` (`:stable`, `:edge`, `:<release>`)
- Docs (every service, its env vars, compose snippet and NixOS options):
  built from this repo with `nix build .#docs`
- The app list tracks the [Proxmox VE community scripts](https://github.com/community-scripts/ProxmoxVE)
  as a reference, not an authority.

```nix
{
  inputs.pve-community-nix.url = "github:jeirslab/pve-community-nix/stable";
  # …
  imports = [ inputs.pve-community-nix.nixosModules.<name> ];
  svc.<name> = { enable = true; environmentFile = "/run/secrets/<name>.env"; };
}
```

New services are written by agents, one agent run per upstream app, and
land through PRs into `nightly`. See [AGENTS.md](./AGENTS.md) for the layout
and rules, and `docs/` for how services are built.
