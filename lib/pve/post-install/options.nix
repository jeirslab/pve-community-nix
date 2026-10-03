{ lib, ... }:

# Every choice the upstream interactive post-install script
# (tools/pve/post-pve-install.sh on the official-community-scripts branch)
# prompts for, as an option with a safe default. default.nix evaluates these
# against the caller's settings and compiles a non-interactive routine.
# PVE 8 (bookworm, .list sources) and PVE 9 (trixie, deb822) are both
# handled; the routine detects the running version.

let
  inherit (lib) mkOption types;
in
{
  options.pve.postInstall = {
    correctSources = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Rewrite the base Debian APT sources to the correct set for the running
        PVE release (deb822 `debian.sources` on PVE 9, classic `sources.list`
        on PVE 8). On PVE 9 this also removes the legacy `.list` sources the
        installer leaves behind.
      '';
    };

    disableEnterprise = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Disable the `pve-enterprise` (and enterprise Ceph) repository, which
        needs a paid subscription and otherwise makes every `apt update` fail
        with a 401. The source is disabled in place, not deleted.
      '';
    };

    enableNoSubscription = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable the `pve-no-subscription` repository, the feed a host without
        a subscription updates from.
      '';
    };

    ceph = mkOption {
      type = types.enum [ "none" "no-subscription" ];
      default = "none";
      description = ''
        Ceph repository to add. `none` leaves Ceph sources untouched (right
        for a host that does not run Ceph); `no-subscription` adds the
        open-source Ceph feed matching the PVE release (squid on 9.0/9.1,
        tentacle on 9.2+). PVE 9 only.
      '';
    };

    pveTest = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Add the `pve-test` repository as a disabled entry, ready to switch on
        for pre-release packages. Adding it never enables it. PVE 9 only.
      '';
    };

    disableNag = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Remove the "no valid subscription" dialog from the web and mobile UI,
        through a `DPkg::Post-Invoke` hook that re-applies the patch after
        every apt run, so a widget-toolkit upgrade cannot bring it back.
      '';
    };

    highAvailability = mkOption {
      type = types.enum [ "leave" "enable" "disable" ];
      default = "leave";
      description = ''
        The HA and Corosync services. `leave` changes nothing; `enable` starts
        pve-ha-lrm, pve-ha-crm and corosync; `disable` stops and disables them
        to save resources on a single node. Never `disable` on a cluster
        member.
      '';
    };

    installNix = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Install Determinate Nix on the host (the installer is idempotent).
        Running this tool through `nix run` already needs Nix, so this cannot
        bootstrap the first run; it makes "the host has Nix" a declared,
        repeatable outcome. Fetches and runs the Determinate Systems
        installer from install.determinate.systems.
      '';
    };

    update = mkOption {
      type = types.bool;
      default = true;
      description = "Run `apt update && apt -y dist-upgrade` once the repositories are corrected.";
    };

    reboot = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Reboot when the routine finishes. A reboot is recommended after a
        dist-upgrade but is left to the operator (or the `--reboot` flag).
      '';
    };
  };
}
