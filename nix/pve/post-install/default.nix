{ pkgs, lib }:

# Compiles the declared pve.postInstall options (options.nix) into a single
# non-interactive `nix run` executable: a small prelude sets the PVE_PI_* env
# vars from the option defaults, then the static routine (routine.sh) applies
# them. Run-time flags (--yes / --dry-run / --reboot / --no-update) override the
# decide-at-the-moment bits; everything else is what the .nix declares.
#
# The routine drives a live PVE host, so it calls the host's apt / pveversion /
# systemctl — those come from $PATH at run time (writeShellApplication PREPENDS
# runtimeInputs to PATH, it does not replace it). runtimeInputs pins only the
# generic text tools the routine uses, for reproducibility.

let
  cfg = (lib.evalModules { modules = [ ./options.nix ]; }).config.pve.postInstall;
  b = v: if v then "1" else "0";
  prelude = ''
    # ── defaults compiled from nix/pve/post-install/options.nix ──
    PVE_PI_CORRECT_SOURCES=${b cfg.correctSources}
    PVE_PI_DISABLE_ENTERPRISE=${b cfg.disableEnterprise}
    PVE_PI_ENABLE_NOSUB=${b cfg.enableNoSubscription}
    PVE_PI_CEPH=${cfg.ceph}
    PVE_PI_PVE_TEST=${b cfg.pveTest}
    PVE_PI_DISABLE_NAG=${b cfg.disableNag}
    PVE_PI_HA=${cfg.highAvailability}
    PVE_PI_INSTALL_NIX=${b cfg.installNix}
    PVE_PI_UPDATE=${b cfg.update}
    PVE_PI_REBOOT=${b cfg.reboot}
  '';
in
pkgs.writeShellApplication {
  name = "pve-post-install";
  runtimeInputs = with pkgs; [ coreutils gnused gawk gnugrep findutils curl ];
  text = prelude + "\n" + builtins.readFile ./routine.sh;
  meta = {
    description = "Declarative, non-interactive Proxmox VE post-install routine (nix run)";
    mainProgram = "pve-post-install";
    license = lib.licenses.mit;
  };
}
