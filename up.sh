#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$dir"

read_token() {
  [[ -f "$1" ]] && tr -d '\r' < "$1" | sed -n 's/^GITHUB_TOKEN=//p' | tail -n 1
}

token="${GITHUB_TOKEN:-}"
for f in .env ../.env ../eisf/docker/.env; do
  [[ -n "$token" ]] && break
  token="$(read_token "$f" || true)"
done
if [[ ! "$token" =~ ^[A-Za-z0-9_]+$ ]]; then
  echo 'Set GITHUB_TOKEN (letters, digits, underscores) in legacy/.env for the SOMS image build.' >&2
  exit 1
fi

umask 077
mkdir -p docker/secrets
printf '{"github-oauth":{"github.com":"%s"}}' "$token" > docker/secrets/composer_auth
# Read access to RealTime-Software-Solutions/rt-design-system (yarn git dependency).
printf '%s' "$token" > docker/secrets/design_system_token
unset token GITHUB_TOKEN

env_args=()
[[ -f .env ]] && env_args=(--env-file .env)
docker compose "${env_args[@]}" up -d --build "$@"

# Bring the DB schema up to the checked-out soms branch. The baseline export lags the code,
# and a missing column fails every document upload with a generic error. Skipped when
# legacy-soms isn't running (e.g. `up.sh legacy-db`).
if [[ "$(docker inspect -f '{{.State.Running}}' legacy-soms 2>/dev/null)" == true ]]; then
  # The entrypoint writes app/config/database.php, which phinx reads, before the container turns healthy.
  for _ in $(seq 1 60); do
    [[ "$(docker inspect -f '{{.State.Health.Status}}' legacy-soms)" == healthy ]] && break
    sleep 2
  done
  echo 'Running SOMS migrations...'
  if ! out="$(docker exec -u www-data -w /srv/http/ctms/soms legacy-soms vendor/bin/phinx migrate 2>&1)"; then
    printf '%s\n' "$out" >&2
    echo 'phinx migrate failed (full output above).' >&2
    exit 1
  fi
  printf '%s\n' "$out" | grep -E '^ == .*migrated|All Done' || true
fi

docker compose "${env_args[@]}" ps -a
echo "SOMS: http://localhost:${LEGACY_SOMS_PORT:-8081}/soms/ (admin / password)"
