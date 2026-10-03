# postInstall: settings → the Proxmox VE post-install routine as one
# executable. The settings are checked against options.nix (a typo or a bad
# value fails at eval), compiled into a prelude of PVE_PI_* variables, and
# prepended to routine.sh. Run-time flags (--yes, --reboot, --no-update)
# cover only the decide-at-the-moment parts; everything else is what the
# caller declared.
#
# The routine drives a live PVE host, so apt, pveversion and systemctl come
# from the host's PATH (writeShellApplication prepends runtimeInputs, it
# does not replace PATH); runtimeInputs pins only the text tools it uses.
{ lib, pkgs }:

settings:

let
  cfg = (lib.evalModules { modules = [ ./options.nix { pve.postInstall = settings; } ]; }).config.pve.postInstall;
  b = v: if v then "1" else "0";
in
pkgs.writeShellApplication {
  name = "pve-post-install";
  runtimeInputs = with pkgs; [ coreutils gnused gawk gnugrep curl ];
  text = ''
    # Compiled from the caller's pve.postInstall settings.
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

  '' + builtins.readFile ./routine.sh;
  passthru.settings = cfg;
  meta = {
    description = "Non-interactive Proxmox VE post-install routine, configured in Nix";
    mainProgram = "pve-post-install";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
