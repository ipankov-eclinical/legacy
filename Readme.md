# Legacy SOMS local stack

Runs SOMS on its own, without eISF: MariaDB 10.6 plus a SOMS image built from
your local `soms/` checkout. eDocs are served by SOMS itself
(`documents.eisf_enabled = 0`).

| Service       | Container     | URL / port                                         |
| ------------- | ------------- | -------------------------------------------------- |
| `legacy-soms` | `legacy-soms` | http://localhost:8081/soms/ (`admin` / `password`) |
| `legacy-db`   | `legacy-db`   | `127.0.0.1:3307`, database `soms`                  |

The ports don't clash with the eISF stack (8080 / 3306), so you can run both at
the same time.

## Prerequisites

- Docker with Compose v2 and `buildx` (the build uses BuildKit secrets).
- SSH access to `RealTime-Software-Solutions/soms` on GitHub.
- A GitHub token (`GITHUB_TOKEN`) that can read **both**
  `RealTime-Software-Solutions/phpcommon` and
  `RealTime-Software-Solutions/soms-libs-mirror`. `composer install` needs both
  during the image build. Access to `soms-libs-mirror` is granted separately
  from `phpcommon`.
- A gzipped baseline SQL dump (with no `CREATE DATABASE` / `USE` statements).
  It isn't part of this repo. Point `LEGACY_BASELINE` at it (see step 3).

## 1. Clone this repo

```bash
git clone https://github.com/ipankov-eclinical/legacy.git
cd legacy
```

## 2. Clone SOMS

Clone SOMS into `soms/` inside this repo. The directory is gitignored, and the
build expects it at that path.

```bash
git clone git@github.com:RealTime-Software-Solutions/soms.git soms
cd soms
git checkout <branch>        # e.g. main, develop, release/v4.50.0
cd ..
```

Using HTTPS instead of SSH:

```bash
git clone https://github.com/RealTime-Software-Solutions/soms.git soms
```

You don't need a recursive clone: `composer install` fetches `phpcommon`
during the image build.

## 3. Configure

```bash
cp .env.example .env
```

Then edit `.env`:

| Variable           | Default                             | Meaning                                                                    |
| ------------------ | ----------------------------------- | -------------------------------------------------------------------------- |
| `GITHUB_TOKEN`     | (empty)                             | Token for the build. If empty, `up.sh` falls back to `../.env`, then `../eisf/docker/.env`. |
| `LEGACY_BASELINE`  | `../eisf/docker/db/baseline.sql.gz` | Dump to seed the DB from, absolute or relative to this repo. The default only works when this repo sits next to an `eisf/` checkout that has the dump. |
| `LEGACY_SOMS_PORT` | `8081`                              | Host port for SOMS.                                                        |
| `LEGACY_DB_PORT`   | `3307`                              | Host port for MariaDB (bound to 127.0.0.1).                                |

To check that the token can read the second private repo (a 404 means it can't):

```bash
curl -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/RealTime-Software-Solutions/soms-libs-mirror
```

## 4. Start

```bash
./up.sh
```

`up.sh` writes the token to `docker/secrets/composer_auth` and
`docker/secrets/design_system_token` (both gitignored), builds the SOMS image,
starts both containers, runs the SOMS Phinx migrations and prints their status.
Extra arguments are passed through to `docker compose up`.

The SOMS image is built in two steps. `legacy-soms-base` is the unmodified
image from `soms/.docker/pr-image/Dockerfile` and is never started.
`docker/soms/Dockerfile` then adds the document tools uploads need:
LibreOffice, Ghostscript, qpdf, poppler, msgconvert and PEAR `Mail_mimeDecode`
for `.msg` files. It also creates the paths SOMS hardcodes,
`/home/realtime/bin/gs` and `/usr/local/bin/msgconvert`. This way uploads work
whichever `soms` branch is checked out.

**Migrations run on every `up.sh`.** The baseline export is older than recent
`soms` branches, and a missing column makes every document upload fail with a
generic error. `up.sh` brings the schema up to the checked-out branch. Some
migrations drop columns, so after migrating for a newer branch an older one
may break until you re-seed with `./down.sh -v`.

**The first start is slow.** MariaDB imports the baseline before it reports
healthy, and SOMS waits for that. The import skips `auditGeneric` /
`auditFormData` rows, which are most of the dump (the tables are still
created). After the import, `002-local-setup.sql` resets `admin` to `password`
and turns eISF off. The seed runs only when the DB volume is empty.

Follow the progress with:

```bash
docker compose --env-file .env logs -f legacy-db legacy-soms
```

Then open http://localhost:8081/soms/ and log in as `admin` / `password`.

## Day-to-day

**PHP / JS changes**: the SOMS code is **baked into the image**, not mounted.
Run `./up.sh` again to rebuild after you edit or switch branches:

```bash
cd soms && git checkout <other-branch> && cd ..
./up.sh
```

**Stop**:

```bash
./down.sh        # stop, keep the DB, sessions and uploaded documents
./down.sh -v     # stop and drop the volumes; the next start re-seeds from the baseline
```

**Logs**: the SOMS application log is inside the container:

```bash
docker exec legacy-soms tail -f /srv/http/ctms/soms/logs/all.log
```

**Database**:

```bash
mysql -h 127.0.0.1 -P 3307 -u soms -psoms_pass soms   # app user
mysql -h 127.0.0.1 -P 3307 -u root -proot soms        # root
```

## Troubleshooting

- **The build fails with a generic composer auth error**: the token most likely
  can't read `soms-libs-mirror`. Use the `curl` check above.
- **The build fails at `yarn-install-private`**: SOMS branches that include
  EDOCS-1448 (#6979) install `@realtime/design-system` from the private
  `RealTime-Software-Solutions/rt-design-system` repo. `up.sh` passes the same
  `GITHUB_TOKEN` as the `design_system_token` secret, so the token needs read
  access to that repo too.
- **An upload fails with "An unexpected error was encountered"**: check
  `logs/all.log` in the container. `[Returned 127]` means a converter binary is
  missing from the image. `Unknown column` means migrations haven't run, so run
  `./up.sh` again.
- **SOMS connects to the wrong DB or path**: gitignored local config in your
  `soms/` checkout (`scripts/client_config.php`, `app/config/database.php`,
  `app/config/session.php`) is copied into the image and wins over what the
  entrypoint generates. Remove it, or point it at `legacy-db` / `soms` /
  `soms_pass`.
- **The DB never turns healthy**: check `docker compose --env-file .env logs
  legacy-db`. The baseline must be gzipped and must not contain `CREATE
  DATABASE` / `USE` statements.
