# Using a service

Every service is configured only through environment variables. Each
service's page lists them with their defaults.

## Docker / Coolify

Copy the service's compose snippet. Every variable is written as
`${VAR}` / `${VAR:-default}`, so set them in Coolify's environment UI or a
`.env` file next to the compose file. Data lives in the named volumes the
snippet declares.

Tags: `:stable` (released), `:edge` (latest nightly build), `:<release>`.

## NixOS

```nix
{
  inputs.pve-community-nix.url = "github:jeirslab/pve-community-nix/stable";

  # in a host's configuration:
  imports = [ inputs.pve-community-nix.nixosModules.<name> ];
  svc.<name> = {
    enable = true;
    environmentFile = "/run/secrets/<name>.env";   # e.g. rendered by sops-nix
    openFirewall = true;
  };
}
```

The `environmentFile` takes exactly the variables the image takes.

### In a NixOS container on Proxmox VE

The module runs the same in a NixOS LXC container as on any NixOS host.
Two things about the container itself:

- **Proxmox VE 9.** Its `PVE::LXC::Setup::NixOS` writes the guest's
  network configuration from the container's `net0` (`ip=`, `gw=`) at
  create time, so a NixOS container comes up on the network without a
  console session. PVE 8 does not.
- **Privileged containers, for now.** The systemd in current
  nixos-unstable (260) cannot set up its per-service credentials inside an
  unprivileged user namespace (`status=243/CREDENTIALS`), which breaks
  journald, networkd and logind. Until PVE or NixOS resolves it, create the
  container privileged.
