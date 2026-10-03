# Proxmox VE host tools

Besides services, the flake carries tools for the Proxmox VE host itself:
the community scripts' `tools/pve/*.sh`, rewritten so that every choice
their whiptail dialogs asked for is a setting in Nix. Each tool is a
function in `lib.pve` that takes those settings and returns a program to
run on the host. They are not services and have no container image.

## Post-install

The non-interactive form of upstream's `post-pve-install.sh`: correct the
APT sources for the running release (PVE 8 or 9), switch from the
enterprise to the no-subscription repository, optionally add Ceph and
`pve-test`, remove the subscription nag, set HA on or off, optionally
install Determinate Nix, and dist-upgrade. No telemetry.

It is a **dry run unless `--yes` is passed**: run it once to read the plan,
then again with `--yes` to apply it.

With the default settings, on the PVE host (as root, with Nix installed):

```sh
nix run github:jeirslab/pve-community-nix/stable#pve-post-install            # plan
nix run github:jeirslab/pve-community-nix/stable#pve-post-install -- --yes   # apply
```

With your own settings, from a flake of yours:

```nix
{
  inputs.pve-community-nix.url = "github:jeirslab/pve-community-nix/stable";

  outputs = { pve-community-nix, ... }: {
    packages.x86_64-linux.pve-post-install = pve-community-nix.lib.pve.postInstall {
      ceph = "no-subscription";
      highAvailability = "disable";   # single node
    };
  };
}
```

then `nix run .#pve-post-install`. An unknown setting or a bad value is an
evaluation error, not a surprise on the host.

Run-time flags: `--yes`, `--dry-run`, `--reboot` / `--no-reboot`,
`--no-update`, `--install-nix` / `--no-install-nix`, `--help`.

### Settings

POST_INSTALL_OPTIONS
