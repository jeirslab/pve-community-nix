{ lib, ... }:

# Declarative surface of the Proxmox VE post-install routine — every choice the
# original interactive whiptail script (legacy/tools/pve/post-pve-install.sh)
# prompted for, expressed as an option with a safe default. `default.nix`
# evaluates these and renders a NON-interactive routine; `nix run` executes it,
# with a few run-time flags for the decide-at-the-moment bits (see the header
# there). PVE 8 (bookworm/.list) and PVE 9 (trixie/deb822) are both handled;
# the routine detects the running version and applies the matching format.

let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.pve.postInstall = {
    correctSources = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Rewrite the base Debian APT sources to the correct set for the running
        PVE release (deb822 `debian.sources` on PVE 9 / trixie, classic
        `sources.list` on PVE 8 / bookworm). On PVE 9 this also disables any
        legacy `.list` sources in favour of deb822.
      '';
    };

    disableEnterprise = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Disable the `pve-enterprise` (and enterprise Ceph) repository, which
        needs a paid subscription and otherwise makes every `apt update` fail
        with a 401. The enterprise source is disabled in place, not deleted.
      '';
    };

    enableNoSubscription = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable the `pve-no-subscription` repository — the open-source component
        feed a non-subscribed host updates from.
      '';
    };

    ceph = mkOption {
      type = types.enum [ "none" "no-subscription" ];
      default = "none";
      description = ''
        Ceph package repository to add. "none" leaves Ceph sources untouched
        (correct for a host that does not run Ceph); "no-subscription" adds the
        open-source Ceph feed matching the PVE release (squid on 9.0/9.1,
        tentacle on 9.2+).
      '';
    };

    pveTest = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Add the `pve-test` repository as a DISABLED entry (advanced users can
        flip it on for pre-release packages). Off by default; adding it never
        enables it.
      '';
    };

    disableNag = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Remove the "no valid subscription" nag from the web + mobile UI, via a
        `DPkg::Post-Invoke` hook that re-patches after every apt run (so an
        upgrade of the widget toolkit cannot silently restore it).
      '';
    };

    highAvailability = mkOption {
      type = types.enum [ "leave" "enable" "disable" ];
      default = "leave";
      description = ''
        Proxmox HA/Corosync services. "leave" makes no change; "enable" starts
        pve-ha-lrm/crm + corosync; "disable" stops and disables them (reclaims
        resources on a single, non-clustered node — never do this on a cluster
        member).
      '';
    };

    installNix = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Install Determinate Nix on the host (idempotent — the installer detects
        an existing install). NOTE: `nix run` already needs Nix present, so this
        cannot bootstrap its own first invocation; its purpose is to make "this
        PVE host is Nix-capable" a declared, repeatable outcome of the routine
        (a step toward managing PVE hosts declaratively). Fetches and runs the
        Determinate installer — an explicit, opt-in bootstrap, unlike the silent
        telemetry the original script sourced.
      '';
    };

    update = mkOption {
      type = types.bool;
      default = true;
      description = "Run `apt update && apt -y dist-upgrade` after the repositories are corrected.";
    };

    reboot = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Reboot the host when the routine finishes. Off by default — a reboot is
        recommended after a dist-upgrade but is left to the operator (or the
        `--reboot` run-time flag).
      '';
    };
  };
}
