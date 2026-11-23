#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$dir"

env_args=()
[[ -f .env ]] && env_args=(--env-file .env)
exec docker compose "${env_args[@]}" down --remove-orphans "$@"
