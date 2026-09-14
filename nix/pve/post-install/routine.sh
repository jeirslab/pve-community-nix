# Proxmox VE post-install routine — non-interactive, declarative port of
# legacy/tools/pve/post-pve-install.sh. Config arrives as PVE_PI_* env vars
# (set by the Nix layer from pve.postInstall options); a few run-time flags
# override the decide-at-the-moment bits. Detects PVE 8 (bookworm/.list) vs
# 9 (trixie/deb822) and applies the matching format. No telemetry, no whiptail.
#
# Safety: DRY-RUN by default. Nothing is changed until `--yes` is passed — on a
# production hypervisor an accidental `nix run` should print a plan, not mutate
# APT sources. writeShellApplication provides the shebang + set -euo pipefail.

APPLY=0

usage() {
  cat <<'USAGE'
pve-post-install — declarative Proxmox VE post-install (dry-run by default)

  nix run …#pve-post-install            # print the plan, change nothing
  nix run …#pve-post-install -- --yes   # apply it

Flags:
  --yes             Apply changes (default is dry-run).
  --dry-run         Force dry-run (default).
  --reboot          Reboot when finished.
  --no-reboot       Do not reboot (override the declared default).
  --no-update       Skip apt update && dist-upgrade.
  -h, --help        This help.

What it does is declared in nix/pve/post-install/options.nix; the compiled-in
defaults are shown in the plan header.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --yes) APPLY=1 ;;
    --dry-run) APPLY=0 ;;
    --reboot) PVE_PI_REBOOT=1 ;;
    --no-reboot) PVE_PI_REBOOT=0 ;;
    --no-update) PVE_PI_UPDATE=0 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "pve-post-install: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
  shift
done

log() { printf '  %s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }
yn() { if [ "$1" = 1 ]; then echo yes; else echo no; fi; }
mode() { if [ "$APPLY" = 1 ]; then echo APPLY; else echo 'DRY-RUN (pass --yes to apply)'; fi; }

# Run a command, or describe it in dry-run.
run() {
  if [ "$APPLY" = 1 ]; then
    "$@"
  else
    log "[dry-run] would run: $*"
  fi
}

# Write stdin to a file, or describe it in dry-run.
write_file() {
  local path="$1"
  if [ "$APPLY" = 1 ]; then
    cat >"$path"
    log "wrote $path"
  else
    log "[dry-run] would write $path:"
    sed 's/^/        | /'
  fi
}

if [ "$(id -u)" -ne 0 ]; then
  echo "pve-post-install: must run as root on the Proxmox VE host" >&2
  exit 1
fi
if ! command -v pveversion >/dev/null 2>&1; then
  echo "pve-post-install: pveversion not found — this is not a Proxmox VE host" >&2
  exit 1
fi

PVE_VER="$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"
PVE_MAJOR="${PVE_VER%%.*}"
PVE_REST="${PVE_VER#*.}"
PVE_MINOR="${PVE_REST%%.*}"

case "$PVE_MAJOR" in
  8) SUITE="bookworm" ;;
  9) SUITE="trixie" ;;
  *) echo "pve-post-install: unsupported PVE major version '$PVE_MAJOR' (8 or 9)" >&2; exit 105 ;;
esac

cat <<PLAN

Proxmox VE post-install — detected PVE ${PVE_VER} (${SUITE})
Mode: $(mode)

Plan:
  correct sources     : $(yn "$PVE_PI_CORRECT_SOURCES")
  disable enterprise  : $(yn "$PVE_PI_DISABLE_ENTERPRISE")
  enable no-sub       : $(yn "$PVE_PI_ENABLE_NOSUB")
  ceph                : ${PVE_PI_CEPH}
  add pve-test (off)  : $(yn "$PVE_PI_PVE_TEST")
  disable nag         : $(yn "$PVE_PI_DISABLE_NAG")
  high availability   : ${PVE_PI_HA}
  update (dist-upgrade): $(yn "$PVE_PI_UPDATE")
  reboot after        : $(yn "$PVE_PI_REBOOT")
PLAN

# ── Sources ──────────────────────────────────────────────────────────
if [ "$PVE_PI_CORRECT_SOURCES" = 1 ]; then
  step "Correcting base APT sources ($SUITE)"
  if [ "$PVE_MAJOR" = 9 ]; then
    run rm -f /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/pve-install-repo.list
    if [ -f /etc/apt/sources.list ]; then
      run sed -i '/proxmox/d;/bookworm/d' /etc/apt/sources.list
    fi
    write_file /etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: ${SUITE}
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: ${SUITE}-security
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://deb.debian.org/debian
Suites: ${SUITE}-updates
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
  else
    write_file /etc/apt/sources.list <<EOF
deb https://deb.debian.org/debian ${SUITE} main contrib
deb https://deb.debian.org/debian ${SUITE}-updates main contrib
deb https://security.debian.org/debian-security ${SUITE}-security main contrib
EOF
    write_file /etc/apt/apt.conf.d/no-bookworm-firmware.conf <<'EOF'
APT::Get::Update::SourceListWarnings::NonFreeFirmware "false";
EOF
  fi
fi

# ── pve-enterprise ───────────────────────────────────────────────────
if [ "$PVE_PI_DISABLE_ENTERPRISE" = 1 ]; then
  step "Disabling pve-enterprise repository"
  if [ "$PVE_MAJOR" = 9 ]; then
    for f in /etc/apt/sources.list.d/*.sources; do
      [ -e "$f" ] || continue
      if grep -q "enterprise.proxmox.com" "$f"; then
        if grep -q '^Enabled:' "$f"; then
          run sed -i 's/^Enabled:.*/Enabled: false/' "$f"
        else
          if [ "$APPLY" = 1 ]; then printf 'Enabled: false\n' >>"$f"; log "disabled $f"; else log "[dry-run] would set Enabled: false in $f"; fi
        fi
      fi
    done
  else
    write_file /etc/apt/sources.list.d/pve-enterprise.list <<EOF
# deb https://enterprise.proxmox.com/debian/pve ${SUITE} pve-enterprise
EOF
  fi
fi

# ── pve-no-subscription ──────────────────────────────────────────────
if [ "$PVE_PI_ENABLE_NOSUB" = 1 ]; then
  step "Enabling pve-no-subscription repository"
  if [ "$PVE_MAJOR" = 9 ]; then
    write_file /etc/apt/sources.list.d/proxmox.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: ${SUITE}
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
  else
    write_file /etc/apt/sources.list.d/pve-install-repo.list <<EOF
deb http://download.proxmox.com/debian/pve ${SUITE} pve-no-subscription
EOF
  fi
fi

# ── Ceph (PVE 9 deb822 only) ─────────────────────────────────────────
if [ "$PVE_PI_CEPH" = "no-subscription" ] && [ "$PVE_MAJOR" = 9 ]; then
  if [ "${PVE_MINOR:-0}" -ge 2 ]; then CEPH_RELEASE="ceph-tentacle"; else CEPH_RELEASE="ceph-squid"; fi
  step "Adding Ceph no-subscription repository (${CEPH_RELEASE})"
  write_file /etc/apt/sources.list.d/ceph.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/${CEPH_RELEASE}
Suites: ${SUITE}
Components: no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
fi

# ── pvetest (disabled entry) ─────────────────────────────────────────
if [ "$PVE_PI_PVE_TEST" = 1 ] && [ "$PVE_MAJOR" = 9 ]; then
  step "Adding pve-test repository (disabled)"
  write_file /etc/apt/sources.list.d/pve-test.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: ${SUITE}
Components: pve-test
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
Enabled: false
EOF
fi

# ── Subscription nag ─────────────────────────────────────────────────
if [ "$PVE_PI_DISABLE_NAG" = 1 ]; then
  step "Disabling subscription nag"
  write_file /usr/local/bin/pve-remove-nag.sh <<'EOF'
#!/bin/sh
WEB_JS=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
if [ -s "$WEB_JS" ] && ! grep -q NoMoreNagging "$WEB_JS"; then
    sed -i -e "/data\.status/ s/!//" -e "/data\.status/ s/active/NoMoreNagging/" "$WEB_JS"
fi
EOF
  run chmod 755 /usr/local/bin/pve-remove-nag.sh
  write_file /etc/apt/apt.conf.d/no-nag-script <<'EOF'
DPkg::Post-Invoke { "/usr/local/bin/pve-remove-nag.sh"; };
EOF
  run chmod 644 /etc/apt/apt.conf.d/no-nag-script
  if [ "$APPLY" = 1 ]; then
    /usr/local/bin/pve-remove-nag.sh || true
    apt --reinstall install -y proxmox-widget-toolkit >/dev/null 2>&1 || log "widget-toolkit reinstall skipped/failed"
  else
    log "[dry-run] would run the nag patch + reinstall proxmox-widget-toolkit"
  fi
fi

# ── High availability ────────────────────────────────────────────────
case "$PVE_PI_HA" in
  enable)
    step "Enabling high availability"
    run systemctl enable -q --now pve-ha-lrm pve-ha-crm corosync
    ;;
  disable)
    step "Disabling high availability (single-node)"
    run systemctl disable -q --now pve-ha-lrm pve-ha-crm corosync
    ;;
  leave) : ;;
esac

# ── Update ───────────────────────────────────────────────────────────
if [ "$PVE_PI_UPDATE" = 1 ]; then
  step "Updating Proxmox VE (apt update && dist-upgrade)"
  if [ "$APPLY" = 1 ]; then
    apt update
    apt -y dist-upgrade
    log "updated"
  else
    log "[dry-run] would run: apt update && apt -y dist-upgrade"
  fi
fi

# ── Reboot ───────────────────────────────────────────────────────────
if [ "$PVE_PI_REBOOT" = 1 ]; then
  step "Rebooting"
  run reboot
elif [ "$APPLY" = 1 ]; then
  printf '\nDone. A reboot is recommended after a dist-upgrade.\n'
else
  printf '\nDone (dry-run — nothing changed; pass --yes to apply).\n'
fi
