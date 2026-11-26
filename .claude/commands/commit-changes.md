---
description: Commit current changes with a one line message from /commit-message
argument-hint: "[soms]  (empty = this repo, soms = soms/ repo)"
allowed-tools: Skill, Read, Glob, Grep, Bash(git status:*), Bash(git branch:*), Bash(git log:*), Bash(git diff:*), Bash(git rev-parse:*), Bash(git add:*), Bash(git commit:*), Bash(git -C soms status:*), Bash(git -C soms branch:*), Bash(git -C soms log:*), Bash(git -C soms diff:*), Bash(git -C soms rev-parse:*), Bash(git -C soms add:*), Bash(git -C soms commit:*)
---

You are committing the uncommitted work in one repo of this workspace, using the message that `/commit-message` writes. Always adhere to any rules or requirements set out in any CLAUDE.md files.

User input: $ARGUMENTS

## Step 1. Write the message

Invoke the `commit-message` skill with the Skill tool, passing `$ARGUMENTS` unchanged as its `args`, and follow it to the end. It validates the argument, picks the repo, and writes the one-line message.

- If it printed the unknown-repo error, or reported nothing to commit, stop here. Do not run any other command.
- Otherwise keep its message and its repo choice: `git <cmd>` for the current repo, `git -C soms <cmd>` for `soms`. Its "do not run `git commit`" rule covers writing the message only; this command does the commit in Step 2.

## Step 2. Commit

In the chosen repo:

1. **Stage.** If something was already staged, commit exactly that and stage nothing more — the message describes only the staged changes. Otherwise stage the whole working tree with `git add -A`.
   - Before `git add -A`, look at the untracked files in `git status --short`. If any likely holds secrets (`.env*`, `*.pem`, `*.key`, `credentials*`, `.claude/settings.local.json`, and the like), do not stage anything: list them and stop, so the user can stage by hand.
2. **Commit** with the message as a single line and nothing else: `git commit -m "<message>"`. No body, no trailer. Quote the message safely for the shell.
3. If a hook fails, show its output and stop. Do not retry with `--no-verify` and do not amend.

Do not push, do not create or switch branches, and do not amend earlier commits.

## Step 3. Output

Print the commit in one line, `git log --oneline -1` in the chosen repo, followed by one short line naming the repo and branch.
