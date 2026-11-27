# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git: never commit or push unless told to

**Do not commit or push unless the user explicitly asks you to.** Finishing a task, passing tests or completing an OpenSpec task is not permission. Stage, commit and push only on an explicit request, and only in the repo the request names.

Three slash commands in `.claude/commands/` handle git. Each takes an optional repo argument: empty means this repo, `soms` means the `soms/` repo.
- `/commit-message [soms]` writes a one-line message, `TICKET-123: <imperative summary>`, taking the ticket from the branch name. It never stages or commits.
- `/commit-changes [soms]` runs `/commit-message`, then commits: it uses what is staged, or `git add -A` if nothing is. It refuses to stage likely-secret files, never pushes and never amends. Running it counts as an explicit request to commit, but not to push.
- `/update-branch [soms] [base]` merges `origin/<base>` into the current branch: by default, the branch it was made from. It resolves conflicts, then checks how the incoming changes affect the branch's work and its OpenSpec change, and asks about any spec changes or merge decisions. Running it counts as an explicit request for that one merge commit. It never pushes, rebases or stashes, and it makes follow-up fixes only when asked.

## What this workspace is

`legacy/` is its own git repo (`main`). It holds:
- the local SOMS-only Docker stack: `docker-compose.yml`, `up.sh`, `down.sh`, `js.sh`, `docker/` (see `Readme.md`);
- OpenSpec planning for SOMS work: `openspec/changes/<change>/` (proposal, design, specs, tasks);
- the slash commands above.

`soms/` is a **separate git repo** (gitignored here) with its own branches. Run git commands for it as `git -C soms <cmd>` and check which repo you are in before any git command. The OpenSpec tasks name the SOMS branch they target, e.g. `release/SOMS-2027.1.0.0`.

## Scope: SOMS only

This setup is legacy SOMS on its own. SOMS serves eDocs itself, and nothing else runs alongside it. Work here as if SOMS were the whole system:
- Don't mention eISF, or any SOMS ↔ eISF integration, in code, comments, tests, commit messages, OpenSpec artifacts or docs written in this setup. Don't plan or verify anything against eISF here.
- Don't let eISF factor into decisions here: design choices, scope and trade-offs are judged on SOMS alone.
- The parent folder (`../`) has a different setup where SOMS and eISF run together. Its CLAUDE.md describes that setup, and it doesn't apply in `legacy/`.

## Local stack

- SOMS: http://localhost:8081/soms/ (`admin` / `password`). MariaDB: `127.0.0.1:3307`, database `soms`, user `soms` / `soms_pass`, root password `root`.
- `soms/` is **bind-mounted**, so PHP edits are live with no rebuild. `vendor/` and the `node_modules/` directories live only in Docker volumes and are not on the host, so run PHP and JS tooling inside the `legacy-soms` container.
- `./up.sh` starts the stack. It rebuilds the image only when dependency files change (`--build` forces a rebuild) and runs Phinx migrations on every start. `./down.sh` stops it, and `./down.sh -v` also drops the DB so the next start re-seeds. `./js.sh [--dev|--watch] [main|esource|web-integration]` rebuilds the JS bundles.
- The app log is `soms/logs/all.log`.

Running SOMS checks in the container (the stack must be up):
```bash
docker exec -u www-data -w /srv/http/ctms/soms legacy-soms vendor/bin/phpunit --testsuite Unit
docker exec -u www-data -w /srv/http/ctms/soms legacy-soms vendor/bin/phpunit --filter testMethodName tests/php/Path/To/SomeTest.php
docker exec -u www-data -w /srv/http/ctms/soms legacy-soms vendor/bin/phpstan analyze --memory-limit=2G
docker exec -u www-data -w /srv/http/ctms/soms legacy-soms vendor/bin/phpcs --standard=PSR12 <files>
docker exec -u www-data -w /srv/http/ctms/soms legacy-soms yarn test        # jest
```
These map to the `soms` scripts `composer test:unit`, `composer analyze`, `composer phpcs` and `npm test`. Integration tests under `tests/php/Integration/` need the DB and are excluded from CI.

---

## soms (legacy PHP CTMS)

Composer project `ctms/ctms`, PHP 7.4. Two code eras coexist:
- Legacy: top-level `inc_*.php` / `report_*.php` procedural includes, driven by `index.php`.
- Newer: `app/` MVC layer — `app/controllers/*.php` (route registration via a custom `CTMS\Lib\Application`, matching `$_GET['action']` against `:param`-style regex routes), `app/models/*.php` (~250 ActiveRecord-style models over raw SQL via `lib/Record.php` — no PDO/Doctrine, tables like `tblUser`), `app/views/*.php`, and `app/comp/*.jsx` (React components embedded in server-rendered views, bundled with Webpack/Babel).
- Config is a `StdClass` assembled in `app/config/config.php` from per-concern files (`database.php`, `session.php`, etc.), each with a `.default.php`/`.dist.php` fallback — check which one is actually loaded when debugging config issues.
- Migrations via Phinx (`app/migrations/phinx`, `phinx.php`).

**Setup**: `php util/provision.php` (generates config, installs deps, symlinks). Clone with `git clone --recursive` — pulls in the `php-common` submodule. Update it with `composer update rt/phpcommon:dev-develop`. (For this repo's Docker stack, follow `Readme.md` instead: a plain clone is enough, and the image build fetches `phpcommon`.)

### Where PHP logic belongs (team convention — follow this in new/edited code)

Helpers are **not** a place for business logic. `app/helpers/` is for genuinely trivial things: micro-converters, formatters, small pure utility functions with no branching over business rules and no orchestration. If a helper starts making decisions, talking to several models, or growing branches, it's in the wrong place.

Business logic goes in **`app/Service/`**:
- Top-level classes there use namespace `CTMS\Services\` (PSR-4 maps `CTMS\Services\` → `app/Service`); subdirectories use `CTMS\App\Service\<Subdir>\` (e.g. `CTMS\App\Service\PdfSigner`, `CTMS\App\Service\Calendar`). Match the neighbours in whichever directory you're adding to. (`app/services/` lowercase is a separate legacy tree — cache/core/sso only; don't add feature logic there.)
- Anything non-trivial is **split into multiple small classes**, not one fat service. Give each class one responsibility and let the service compose them.

Prefer explicit patterns over long conditional chains. The canonical example the team calls out: for file conversion supporting multiple formats, first a **format-identifier/detector class** decides what the input is, then a **strategy** (one class per format, behind a shared interface) does the conversion, with a small selector/factory mapping detector result → strategy. Adding a format then means adding a class, not editing a branch.

This applies only when you need to **add or expand** logic. Don't refactor existing helpers just because they violate the rule — leave working code alone. But if a change would mean growing the logic inside a helper, put the new logic in a service instead of extending the helper, and leave a thin helper delegating to it if callers depend on the old entry point.
