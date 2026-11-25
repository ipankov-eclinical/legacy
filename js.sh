#!/usr/bin/env bash
# Build the SOMS JS bundles inside the running legacy-soms container. The output lands in
# the bind-mounted soms/ checkout (all of it gitignored), so no restart is needed.
#
#   ./js.sh                       production build of main + esource (what the image builds)
#   ./js.sh esource               only the given targets: main, esource, web-integration
#   ./js.sh --dev [targets...]    development build (faster, unminified)
#   ./js.sh --watch <target>      webpack --watch for one target (Ctrl-C to stop)
set -euo pipefail

mode=build
targets=()
for arg in "$@"; do
  case "$arg" in
    --dev) mode=dev ;;
    --watch) mode=watch ;;
    -h|--help) sed -n '2,8s/^# \{0,1\}//p' "$0"; exit 0 ;;
    main|esource|web-integration) targets+=("$arg") ;;
    *) echo "Unknown argument: $arg (see ./js.sh --help)" >&2; exit 1 ;;
  esac
done
[[ ${#targets[@]} -eq 0 ]] && targets=(main esource)
if [[ "$mode" == watch && ${#targets[@]} -ne 1 ]]; then
  echo '--watch takes exactly one target: main, esource or web-integration.' >&2
  exit 1
fi

if [[ "$(docker inspect -f '{{.State.Running}}' legacy-soms 2>/dev/null)" != true ]]; then
  echo 'legacy-soms is not running. Start it with ./up.sh.' >&2
  exit 1
fi

tty_args=()
[[ -t 0 && -t 1 ]] && tty_args=(-it)

for target in "${targets[@]}"; do
  case "$target" in
    main) path=. ;;
    esource) path=app/js/esource ;;
    web-integration) path=app/js/web-integration ;;
  esac
  workdir="/srv/http/ctms/soms/$path"
  if ! docker exec legacy-soms test -d "$workdir/node_modules/.bin"; then
    echo "No node_modules for $target in the image. Rebuild it with ./up.sh --build." >&2
    exit 1
  fi
  echo "==> $target: yarn $mode"
  # As www-data (uid 1000) so the output in the checkout is owned by the host user.
  docker exec "${tty_args[@]}" -u www-data -w "$workdir" legacy-soms yarn "$mode"
done
