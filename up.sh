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
unset token GITHUB_TOKEN

env_args=()
[[ -f .env ]] && env_args=(--env-file .env)
docker compose "${env_args[@]}" up -d --build "$@"
docker compose "${env_args[@]}" ps -a
echo "SOMS: http://localhost:${LEGACY_SOMS_PORT:-8081}/soms/ (admin / password)"
