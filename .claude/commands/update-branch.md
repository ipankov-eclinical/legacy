---
description: Merge the branch's origin base into the current branch, resolve conflicts, and check what the incoming changes mean for the current work
argument-hint: "[soms] [base-branch]  (empty = this repo, soms = soms/ repo; base defaults to the branch this one was made from)"
allowed-tools: Skill, Read, Edit, Write, Glob, Grep, AskUserQuestion, Bash(git status:*), Bash(git branch:*), Bash(git log:*), Bash(git diff:*), Bash(git show:*), Bash(git rev-parse:*), Bash(git rev-list:*), Bash(git merge-base:*), Bash(git for-each-ref:*), Bash(git ls-files:*), Bash(git remote:*), Bash(git fetch:*), Bash(git merge:*), Bash(git add:*), Bash(git commit:*), Bash(git -C soms status:*), Bash(git -C soms branch:*), Bash(git -C soms log:*), Bash(git -C soms diff:*), Bash(git -C soms show:*), Bash(git -C soms rev-parse:*), Bash(git -C soms rev-list:*), Bash(git -C soms merge-base:*), Bash(git -C soms for-each-ref:*), Bash(git -C soms ls-files:*), Bash(git -C soms remote:*), Bash(git -C soms fetch:*), Bash(git -C soms merge:*), Bash(git -C soms add:*), Bash(git -C soms commit:*), Bash(openspec:*), Bash(docker exec:*), Bash(docker ps:*)
---

You are bringing the current branch up to date with the origin branch it was made from, and then working out what the incoming changes mean for the work on this branch. Always adhere to any rules or requirements set out in any CLAUDE.md files. In particular, this setup is SOMS only: judge and report everything on SOMS alone.

User input: $ARGUMENTS

Running this command is an explicit request to create **one merge commit** in the chosen repo. It is not permission to push, rebase, amend, reset, stash, switch branches, or commit anything else. Code or plan fixes that the analysis suggests are proposals: make them only when the user asks.

## Step 1. Pick the repo and the base

Run all commands from the workspace root. Split `$ARGUMENTS` on whitespace:

- If the first word is `soms`, the repo is `soms/`: run git as `git -C soms <cmd>` and read files under `soms/`. The next word, if any, is the base branch.
- Otherwise the repo is the workspace root (`git <cmd>`) and the first word, if any, is the base branch.
- More than two words, or a base that does not exist as `origin/<base>` after the fetch in Step 2 → stop and print `Error: unknown base "<base>". Pass a branch that exists on origin, e.g. /update-branch soms release/SOMS-2027.1.0.0.`

Stop with a one-line explanation if any of these holds: the repo has no `origin` remote; HEAD is detached; a merge, rebase or cherry-pick is in progress; the current branch is itself the base.

If no base was given, find the branch this one was made from, in this order, and use the first that answers:
1. Earlier merges of a base into this branch: `git log --first-parent --merges --format=%s HEAD`, matching `Merge (remote-tracking )?branch '(origin/)?<base>' into <current>`.
2. The OpenSpec change for this branch: the active change under `openspec/changes/` whose ticket matches the branch's ticket, and the branch its `tasks.md` says the code targets (e.g. "on `release/SOMS-2027.1.0.0`").
3. The nearest candidate: for each of `origin/release/*`, `origin/develop`, `origin/main`, `origin/master`, count `git rev-list --count $(git merge-base HEAD <candidate>)..HEAD`. The lowest count wins. If two are tied or within a few commits of each other, ask the user with AskUserQuestion which one to use.

Announce the repo, the current branch and the base, and how the base was found. If it came from rule 3 without a tie, still say so plainly so the user can stop you.

## Step 2. Prepare

1. `git status --short`. If anything is modified, staged or untracked (other than files ignored by git), stop: list it and tell the user to commit it first (e.g. `/commit-changes [soms]`). Never stash.
2. Record the undo point: `PRE=$(git rev-parse HEAD)`. Report it at the end.
3. `git fetch origin <base>`.
4. If `origin/<base>` is already an ancestor of HEAD (`git merge-base --is-ancestor origin/<base> HEAD`), say the branch is up to date with `origin/<base>` and stop.
5. Record what the branch itself changed before the merge, as "our work":
   - `BASE_BEFORE=$(git merge-base $PRE origin/<base>)`
   - `git diff --name-only $BASE_BEFORE $PRE` and `git log --oneline --no-merges $BASE_BEFORE..$PRE`
   - the classes, methods, routes, tables and config keys that diff adds, changes or relies on
   - the OpenSpec change for this branch, if there is one: read its `proposal.md`, `design.md`, `specs/**` and `tasks.md`, especially the invariants the change protects and the targets named in unchecked tasks.

## Step 3. Merge

`git merge --no-ff --no-commit origin/<base>`.

If it reports no conflicts, go to Step 4.

For each conflicted file (`git diff --name-only --diff-filter=U`):
1. Read the whole conflict, both sides and the merge base (`git show :1:<file>`, `:2:` ours, `:3:` theirs), and the incoming commits that touched it (`git log --oneline $PRE..MERGE_HEAD -- <file>`). Understand what each side meant to do before editing.
2. Resolve so both intents survive. Never take a whole side of a file, or drop an incoming change, without having read it.
   - **Mechanical** (adjacent edits, imports, reordering, code that moved): resolve it yourself.
   - **Incoming change inside code this branch rewrote or removed**: port the incoming change into this branch's version, so it is not lost.
   - **Semantic** (the two sides want different behavior, or the resolution needs a product or design choice): ask the user with AskUserQuestion before resolving, giving both sides and a recommendation.
   - **Files this branch did not mean to change** (lock files, generated bundles, vendored code): take theirs.
3. Check the result: no conflict markers left (`git diff --check`, and grep for `^<<<<<<<|^=======$|^>>>>>>>`), and PHP files still parse (`docker exec -u www-data -w /srv/http/ctms/soms legacy-soms php -l <file>` for `soms`, when the stack is up).
4. `git add` each resolved file.

If the user decides not to merge, run `git merge --abort` and stop.

## Step 4. Verify before committing the merge

For `soms`, with the local stack up (`docker ps` shows `legacy-soms`; if it is down, say so, skip the runs, and list them as still to do):
- The tests our work added or changed (from Step 2.5), and the tests of every conflicted file that has them.
- `phpstan` on our changed PHP files and the conflicted ones.

If a test fails because of a conflict resolution, fix the resolution and re-run. If it fails for another reason, do not fix it here: note it for Step 6.

Then conclude the merge with the default message: `git commit --no-edit`. If a hook fails, show its output and stop; do not use `--no-verify`.

## Step 5. Analyse the incoming changes

Incoming = what the merge brought in: `git log --oneline --no-merges $PRE..HEAD^2` (group by ticket key) and `git diff --stat $PRE HEAD`.

Check each of the following, and keep the evidence (file, method, line, commit) for every finding:

1. **Direct impact.** Incoming changes to files, methods or routes our work changed, or that unchecked OpenSpec tasks name.
2. **Indirect impact.**
   - Incoming code that calls what we changed, or that we call (signature, return-value or behavior changes).
   - New code that reads or writes the same tables or models, and whether it respects the invariants our change protects. For example, a new hard delete on a table we now soft-delete, or a new read without the filter we added.
   - Changes to shared foundations we rely on: base model and `Record`, test bootstrap and helpers, auth and session, config defaults.
   - Migrations that touch our tables or columns.
3. **Overlap.** Incoming commits with the same ticket key or a related one, and incoming work that already does, duplicates or supersedes part of ours (including a new helper or service we should reuse instead of our own).
4. **Plan drift**, if there is an OpenSpec change: whether the methods, routes and files named in unchecked tasks still exist where the plan says, and whether `design.md` line references moved. Line drift alone is not blocking; report it and offer to refresh it.
5. **Local environment** (for `soms`):
   - New Phinx migrations not applied locally. Offer to run them; do not run them unasked.
   - Changes to `composer.json`/`composer.lock`, `package.json`/`yarn.lock` or the Docker files mean `./up.sh --build`.
   - JS source changes in a bundle mean `./js.sh`.
   - New keys in `app/config/*.default.php`/`*.dist.php` that the gitignored local configs lack.
   - `php-common` or submodule bumps.
6. **Tests and checks.** For `soms`, run the unit suite (`vendor/bin/phpunit --testsuite Unit` in the container), and `yarn test` if JS changed on either side. Sort each failure into one of three groups:
   - caused by our work, if the failing test or its subject is in our diff;
   - came with the merge, if it is in incoming files only;
   - environment, if it needs a service, DB or config that is missing locally.

   Call a failure pre-existing only with evidence, such as an earlier run of the same suite or the same failure on `origin/<base>`.

## Step 6. Ask

Ask only about findings that need the user. If there are none, say so and skip the questions. Use AskUserQuestion, at most four questions per call, each standing on its own with the evidence and a recommendation.

- **Spec changes.** For each finding that makes the OpenSpec change wrong, incomplete or stale (a new path that breaks an invariant, a task target that moved or vanished, upstream work that covers a task, a design decision an incoming change contradicts), propose the revision and why. Make the agreed revisions through the `openspec-update-change` workflow, never by editing artifacts directly in this command.
- **Merge decisions.** Semantic conflicts resolved by a choice, incoming behavior that conflicts with ours, duplicated work (keep ours, adopt theirs, or merge the two), failures that came with the merge, and environment steps (migrations, rebuilds) you offered to run.

## Step 7. Output

End with a short report:
- The repo, the branch, the base, the merge commit (`git log --oneline -1`), and the undo point: `git reset --hard <PRE>`, to be run only by the user, and only while the merge is unpushed.
- The incoming commits, by ticket, in one or two lines.
- How each conflict was resolved, one line each.
- Impact findings, most serious first, each with its evidence. Write "none" for a category with no findings.
- Test and check results, with failures in their groups.
- Environment steps still to do.
- The decisions the user made in Step 6, and what is still open.
- How far the branch is now ahead of its own remote (`git rev-list --count @{upstream}..HEAD`, if it has one). Pushing is the user's call.
