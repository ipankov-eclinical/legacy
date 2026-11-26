---
description: Create one line commit message for current changes
argument-hint: "[soms]  (empty = this repo, soms = soms/ repo)"
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(git branch:*), Bash(git log:*), Bash(git diff:*), Bash(git rev-parse:*), Bash(git -C soms status:*), Bash(git -C soms branch:*), Bash(git -C soms log:*), Bash(git -C soms diff:*), Bash(git -C soms rev-parse:*)
---

You are writing a single-line commit message for the uncommitted work in one repo of this workspace. Always adhere to any rules or requirements set out in any CLAUDE.md files.

User input: $ARGUMENTS

## Step 1. Pick the repo

The workspace root and `soms/` are independent git repos (`soms/` is gitignored by the root one), so every git command must run against the right one. Run all commands from the workspace root.

Trim `$ARGUMENTS` and match it exactly:

- **empty** → the current repo (the workspace root). Run git commands as `git <cmd>`.
- **`soms`** → the repo in `soms/`. Run git commands as `git -C soms <cmd>`, and read files under `soms/`.
- **anything else** → stop. Print only this, and run nothing else:

  ```
  Error: unknown repo "<argument>". Use no argument for the current repo, or "soms" for the soms/ repo.
  ```

## Step 2. Read the changes

In the chosen repo:

- `git rev-parse --abbrev-ref HEAD`
- `git status --short`
- `git diff --staged` and `git diff` — read the actual changes, not just the file list. If something is staged, describe **only** the staged changes. Otherwise describe the whole working tree, including the untracked files `git status` lists (read them).
- If there is nothing to commit, say so in one line naming the repo and stop.
- Read surrounding code where the diff alone does not tell you what the change is for.
- `git log --oneline -15` to match the repo's current phrasing.

## Step 3. Write the message

One line. Nothing else — no body, no bullet list, no trailer.

Format: `TICKET-123: <summary>`

- Take the ticket from the branch name (e.g. `feature/EDOCS-1211-...` → `EDOCS-1211`). If the branch carries no ticket, look at the recent commits on it; if there is still none, drop the prefix and write just the summary.
- Summary in the imperative, starting lowercase: "route the sign redirect by DocumentID", not "Routed..." or "Routes...".
- Aim for 72 characters total, and never exceed 100.
- Say what the change does, not which files moved. Prefer the behavior or the reason over the mechanism — `fix cart grouping for pending signatures` beats `update CartService.php and 3 other files`.
- When one change dominates, name only that; mention a second only if the commit genuinely does two things, joined with ", and".
- Do not invent a rationale the diff does not support. If the change is a pure refactor, say so plainly.

## Step 4. Output

Print the message on its own, in a fenced code block, so it can be copied straight into `git commit -m`. Nothing after it except one short line naming the repo and branch you read.

Do not run `git commit` or stage anything — this command only writes the message. Committing is done by `/commit-changes`, which calls this command first.
