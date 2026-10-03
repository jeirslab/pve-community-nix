# The mdBook site: the hand-written chapters under docs/src, plus one page
# per service generated from its contract and NixOS options — configuration
# table, ports, volumes, the compose snippet, and the option reference —
# and the option reference of each Proxmox VE host tool.
{ lib, pkgs, pve }:

services:

let
  esc = s: lib.replaceStrings [ "|" "\n" ] [ "\\|" " " ] s;
  code = s: "`${s}`";

  envTable = c:
    if c.env == { } then "_No environment variables._\n" else
    ''
      | Variable | Default | Required | Description |
      |---|---|---|---|
    '' + lib.concatStrings (lib.mapAttrsToList (k: v: ''
      | ${code k} | ${if v.secret then "_secret_" else if v.default != null then code v.default else ""} | ${if v.required then "yes" else ""} | ${esc v.description} |
    '') c.env);

  portList = c:
    if c.ports == [ ] then "_None._\n" else
    lib.concatMapStrings (p: "- ${code "${toString p.port}/${p.protocol}"}: ${p.description}\n") c.ports;

  optionsDoc = s: (pkgs.nixosOptionsDoc {
    options = s.system.options.svc.${s.name};
    transformOptions = o: o // { declarations = [ ]; };
  }).optionsCommonMark;

  # A host tool's options, rendered into its hand-written chapter in place
  # of an <NAME>_OPTIONS line.
  pveOptionsDoc = m: (pkgs.nixosOptionsDoc {
    options = (lib.evalModules { modules = [ m ]; }).options.pve;
    transformOptions = o: o // { declarations = [ ]; };
  }).optionsCommonMark;

  page = s: pkgs.writeText "${s.name}.md" ''
    # ${s.name}

    ${s.contract.description}
    ${lib.optionalString (s.contract.homepage != null) "\nHomepage: <${s.contract.homepage}>\n"}
    Container image: ${code "${s.image.passthru.ref}"} · approach: ${code s.contract.approach}

    ## Configuration

    The same variables configure both deployments: an `environmentFile` on
    NixOS, `environment` / an env file in Docker or Coolify.

    ${envTable s.contract}

    ## Ports

    ${portList s.contract}

    ## Data

    ${if s.image.passthru.volumes == [ ] then "_No persistent data._" else
      lib.concatMapStrings (v: "- ${code v}\n") s.image.passthru.volumes}

    ## Docker Compose

    ```yaml
    COMPOSE_PLACEHOLDER
    ```

    ## NixOS

    ```nix
    {
      imports = [ inputs.pve-community-nix.nixosModules.${s.name} ];
      svc.${s.name} = {
        enable = true;
        environmentFile = "/run/secrets/${s.name}.env";
      };
    }
    ```

    ## Options

    OPTIONS_PLACEHOLDER
  '';

  names = lib.attrNames services;
in
pkgs.runCommand "pve-community-nix-docs" { nativeBuildInputs = [ pkgs.mdbook ]; } ''
  cp -r ${../docs} book
  chmod -R u+w book
  mkdir -p book/src/services
  sed -i -e '/POST_INSTALL_OPTIONS/{r ${pveOptionsDoc pve.options.postInstall}
  d}' book/src/pve-host.md
  {
    cat book/src/SUMMARY.md
    echo
    echo "# Services"
    echo
    ${lib.concatMapStrings (n: ''
      echo "- [${n}](services/${n}.md)"
    '') names}
    ${lib.optionalString (names == [ ]) ''echo "_No services yet._"''}
  } > book/src/SUMMARY.gen.md
  mv book/src/SUMMARY.gen.md book/src/SUMMARY.md
  ${lib.concatMapStrings (n: let s = services.${n}; in ''
    sed -e '/COMPOSE_PLACEHOLDER/{r ${s.compose}
    d}' -e '/OPTIONS_PLACEHOLDER/{r ${optionsDoc s}
    d}' ${page s} > book/src/services/${n}.md
  '') names}
  mdbook build book -d $out
''
