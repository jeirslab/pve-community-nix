# Import ONE declared Garage access key and grant it bucket permissions
# (idempotent). Co-located with the apps.garage module; wrapped by
# writeShellApplication and driven by a per-key oneshot
# `garage-key-<name>-bootstrap.service`, which injects:
#
#   Environment=      GARAGE_KEY_NAME, GARAGE_KEY_GRANTS
#   EnvironmentFile=  RPC-secret env file + the key's credentials file, which
#                     provides GARAGE_KEY_ACCESS_KEY_ID + GARAGE_KEY_SECRET_ACCESS_KEY
#
# Keys are IMPORTED (declared out of band, e.g. from SOPS), not generated, so
# both producer (Garage) and consumer (PBS, pgbackrest, …) share one credential
# and no secret has to be scraped back out of Garage. GARAGE_KEY_GRANTS is one
# "<bucket> <perms>" per line, where perms is any of r/w/o (e.g. "pbs r w o" →
# "pbs-chunkstore rwo").

for _ in $(seq 1 30); do
  if garage status 2>/dev/null | grep -qE "HEALTHY|UP"; then break; fi
  sleep 2
done

if garage key info "$GARAGE_KEY_NAME" >/dev/null 2>&1; then
  echo "garage-key-bootstrap: ${GARAGE_KEY_NAME}: exists"
else
  echo "garage-key-bootstrap: ${GARAGE_KEY_NAME}: importing"
  garage key import --yes --name "$GARAGE_KEY_NAME" \
    "$GARAGE_KEY_ACCESS_KEY_ID" "$GARAGE_KEY_SECRET_ACCESS_KEY"
fi

while IFS= read -r line; do
  [ -n "$line" ] || continue
  bucket="${line%% *}"
  perms="${line#* }"
  args=()
  case "$perms" in *r*) args+=(--read) ;; esac
  case "$perms" in *w*) args+=(--write) ;; esac
  case "$perms" in *o*) args+=(--owner) ;; esac
  if [ "${#args[@]}" -gt 0 ]; then
    echo "garage-key-bootstrap: grant ${GARAGE_KEY_NAME} on ${bucket} (${perms})"
    garage bucket allow "${args[@]}" --key "$GARAGE_KEY_NAME" "$bucket"
  fi
done <<< "${GARAGE_KEY_GRANTS:-}"
