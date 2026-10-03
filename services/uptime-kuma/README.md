# uptime-kuma

Uptime Kuma is a self-hosted uptime monitoring tool.

Configuration, ports, data volumes, the compose snippet and the NixOS
options are generated into the docs site from `default.nix`.

- The admin account is created in the web UI on first visit (port 3001).
- SQLite is the default database; data lives in `/var/lib/uptime-kuma`.
- Browser-engine monitors (chromium) are not included.
