# Proxmox VE host tooling. Each tool is a function from settings (checked
# against its options module) to a package that runs on the PVE host, so a
# host's setup is declared in Nix and applied with one command. These are
# not services: they configure the hypervisor, not an app.
{ lib, pkgs }:

{
  # postInstall { ceph = "no-subscription"; … } → pve-post-install
  postInstall = import ./post-install { inherit lib pkgs; };

  # The options modules, for docs.
  options = {
    postInstall = ./post-install/options.nix;
  };
}
