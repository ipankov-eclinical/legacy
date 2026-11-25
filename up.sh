#!/usr/bin/env bash
# Start the stack. The soms/ checkout is bind-mounted, so the SOMS image is rebuilt only
# when its dependencies change (see deps_files) or with --build; --no-build never builds.
# Other arguments are passed through to `docker compose up`.
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$dir"

build=auto
up_args=()
for arg in "$@"; do
  case "$arg" in
    --build) build=yes ;;
    --no-build) build=no ;;
    *) up_args+=("$arg") ;;
  esac
done

env_args=()
[[ -f .env ]] && env_args=(--env-file .env)
compose() { docker compose "${env_args[@]}" "$@"; }

# What the image bakes in that the bind mount doesn't replace: vendor/, node_modules/,
# the OS packages and the entrypoint.
deps_files=(
  soms/composer.json soms/composer.lock
  soms/package.json soms/yarn.lock
  soms/app/js/esource/package.json soms/app/js/esource/yarn.lock
  soms/app/js/web-integration/package.json soms/app/js/web-integration/yarn.lock
  soms/.docker/pr-image/Dockerfile soms/.docker/pr-image/entrypoint.sh
  soms/.docker/scripts/yarn-install-private.sh
  docker/soms/Dockerfile
)
LEGACY_DEPS_HASH="$(
  for f in "${deps_files[@]}"; do
    printf '%s ' "$f"
    if [[ -f "$f" ]]; then sha256sum < "$f"; else echo missing; fi
  done | sha256sum | cut -c1-16
)"
export LEGACY_DEPS_HASH

if [[ "$build" == auto ]]; then
  built_hash="$(docker image inspect -f '{{index .Config.Labels "legacy.deps-hash"}}' legacy-soms 2>/dev/null || true)"
  if [[ "$built_hash" == "$LEGACY_DEPS_HASH" ]]; then
    build=no
  else
    build=yes
    echo 'SOMS dependencies changed (or no image yet): rebuilding the image.'
  fi
fi

if [[ "$build" == yes ]]; then
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

  (
    umask 077
    mkdir -p docker/secrets
    printf '{"github-oauth":{"github.com":"%s"}}' "$token" > docker/secrets/composer_auth
    # Read access to RealTime-Software-Solutions/rt-design-system (yarn git dependency).
    printf '%s' "$token" > docker/secrets/design_system_token
  )
  unset token GITHUB_TOKEN

  compose build
  # The dependency volumes were filled from the old image. Drop them so the next start
  # refills them from the new one.
  compose rm -sf legacy-soms
  docker volume rm -f legacy_soms_vendor legacy_soms_node_modules \
    legacy_soms_esource_node_modules legacy_soms_web_integration_node_modules >/dev/null
fi

# Create the mount points as the current user, otherwise Docker creates them in the
# checkout owned by root.
mkdir -p soms/vendor soms/node_modules soms/app/js/esource/node_modules \
  soms/app/js/web-integration/node_modules soms/sessions soms/documents

compose up -d "${up_args[@]}"

# Skipped when legacy-soms isn't running (e.g. `up.sh legacy-db`).
if [[ "$(docker inspect -f '{{.State.Running}}' legacy-soms 2>/dev/null)" == true ]]; then
  # The entrypoint writes app/config/database.php, which phinx reads, before the container turns healthy.
  for _ in $(seq 1 60); do
    [[ "$(docker inspect -f '{{.State.Health.Status}}' legacy-soms)" == healthy ]] && break
    sleep 2
  done

  # The entrypoint runs as root and writes these into the checkout. Hand them to
  # www-data (uid 1000, same as the usual host user) so they stay editable.
  docker exec -w /srv/http/ctms/soms legacy-soms \
    sh -c 'chown www-data:www-data app/config/database.php scripts/client_config.php 2>/dev/null || true'

  # Bring the DB schema up to the checked-out soms branch. The baseline export lags the code,
  # and a missing column fails every document upload with a generic error.
  echo 'Running SOMS migrations...'
  if ! out="$(docker exec -u www-data -w /srv/http/ctms/soms legacy-soms vendor/bin/phinx migrate 2>&1)"; then
    printf '%s\n' "$out" >&2
    echo 'phinx migrate failed (full output above).' >&2
    exit 1
  fi
  printf '%s\n' "$out" | grep -E '^ == .*migrated|All Done' || true

  # The bundles are gitignored build output, so a fresh checkout has none.
  if [[ ! -s soms/scripts/build.min.js || ! -s soms/app/js/esource/public/esource.build.js ]]; then
    echo 'No JS bundles in soms/ yet, building them...'
    ./js.sh
  fi
fi

compose ps -a
echo "SOMS: http://localhost:${LEGACY_SOMS_PORT:-8081}/soms/ (admin / password)"
