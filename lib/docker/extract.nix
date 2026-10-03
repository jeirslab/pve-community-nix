# The `extracted` approach: evaluate the service's real NixOS module, take
# the systemd unit it produces, and run that unit's process as a plain
# single-process image — same package, same generated config, same
# pre-start setup as on a NixOS host. What can't come along is systemd
# itself (sandboxing options, DynamicUser, timers); the image runs as a
# fixed non-root user instead, and anything a service needs beyond that goes
# in its docker.nix.
{ lib, pkgs, registry, source }:

{ name, c, system, dockerCfg, tag ? "latest" }:

let
  mkImage = import ./image.nix { inherit lib pkgs registry source; };

  unit = system.config.systemd.services.${c.unit}
    or (throw "service ${name}: no systemd.services.${c.unit} in the evaluated system — check contract.unit");
  sc = unit.serviceConfig;

  asList = x: if x == null then [ ] else if builtins.isList x then x else [ x ];
  # systemd command prefixes (-, @, +, !, :) mean nothing outside systemd.
  stripPrefix = s: builtins.head (builtins.match "[-@+!:]*(.*)" (toString s));

  execStart =
    let cmds = asList (sc.ExecStart or null); in
    if cmds == [ ] then throw "service ${name}: ${c.unit} has no ExecStart" else stripPrefix (lib.last cmds);
  # Includes the unit's preStart: NixOS already renders it as an ExecStartPre.
  execStartPre = map stripPrefix (asList (sc.ExecStartPre or null));

  # systemd's managed directories, and the variables it exports for them.
  dirs = key: base:
    map (d: "${base}/${d}") (lib.filter (d: d != "") (lib.splitString " " (toString (sc.${key} or ""))));
  stateDirs = dirs "StateDirectory" "/var/lib";
  cacheDirs = dirs "CacheDirectory" "/var/cache";
  logsDirs = dirs "LogsDirectory" "/var/log";
  runtimeDirs = dirs "RuntimeDirectory" "/run";
  configDirs = dirs "ConfigurationDirectory" "/etc";
  allDirs = stateDirs ++ cacheDirs ++ logsDirs ++ runtimeDirs ++ configDirs;
  dirEnv = lib.filterAttrs (_: v: v != "") {
    STATE_DIRECTORY = lib.concatStringsSep ":" stateDirs;
    CACHE_DIRECTORY = lib.concatStringsSep ":" cacheDirs;
    LOGS_DIRECTORY = lib.concatStringsSep ":" logsDirs;
    RUNTIME_DIRECTORY = lib.concatStringsSep ":" runtimeDirs;
    CONFIGURATION_DIRECTORY = lib.concatStringsSep ":" configDirs;
  };

  # Environment= lines set directly in serviceConfig, as an attrset.
  envLines = lib.listToAttrs (map
    (l: let m = builtins.match "([^=]+)=(.*)" l; in lib.nameValuePair (builtins.elemAt m 0) (builtins.elemAt m 1))
    (lib.filter (l: builtins.match "[^=]+=.*" l != null) (asList (sc.Environment or null))));

  # Defaults only: anything set at `docker run -e` / env_file / compose wins,
  # exactly like an environmentFile wins over Environment= on NixOS. PATH is
  # the exception — a container always arrives with one, so the unit's PATH
  # is prepended instead of defaulted.
  allEnv = dirEnv // envLines // unit.environment;
  # NixOS puts systemd on every unit's PATH; systemctl & co. are useless in
  # a container and would pull systemd's whole closure into the image.
  unitPath = lib.concatStringsSep ":"
    (lib.filter (p: builtins.match ".*-systemd-[0-9].*" p == null)
      (lib.splitString ":" (allEnv.PATH or "")));
  defaults = builtins.removeAttrs allEnv [ "PATH" ];

  entrypoint = pkgs.writeShellScript "${name}-entrypoint" ''
    set -eu
    ${lib.optionalString (unitPath != "") ''export PATH=${lib.escapeShellArg unitPath}"''${PATH:+:$PATH}"''}
    ${lib.concatStrings (lib.mapAttrsToList (k: v: ''
      if [ -z "''${${k}+set}" ]; then export ${k}=${lib.escapeShellArg v}; fi
    '') defaults)}
    ${lib.optionalString (allDirs != [ ]) "mkdir -p ${lib.escapeShellArgs allDirs}"}
    ${lib.concatMapStrings (p: "${p}\n") execStartPre}
    exec ${execStart}
  '';
in
mkImage {
  inherit name c dockerCfg entrypoint tag;
  dirs = allDirs;
  volumes = stateDirs;
  workingDir = sc.WorkingDirectory or (if stateDirs != [ ] then builtins.head stateDirs else "/");
}
