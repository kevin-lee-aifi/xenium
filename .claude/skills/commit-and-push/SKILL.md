---
name: commit-and-push
description: Stage, commit, and push the current changes to the remote. Use when the user wants to "commit and push", "save my work to GitHub", "push these changes", or otherwise record and upload the working-tree changes. Reviews the diff, writes a concise repo-style commit message, commits, and pushes to origin.
---

# Commit and Push

Record the current working-tree changes as a commit and push them to the
remote, matching this repo's conventions.

## Steps

1. **Inspect what changed.** Run `git status` and `git diff` (and
   `git diff --staged` if anything is already staged) to see the full picture.
   Read the actual changes — the commit message must describe what really
   changed, not what was requested.

2. **Stage the right files.** Stage the relevant changes with `git add`. Do not
   blindly `git add -A` if there are unrelated files; prefer staging the files
   this change touched. Never stage data folders that are gitignored
   (e.g. `**/csvs/`, bundles) — if they show up as untracked, leave them.

3. **Write the commit message.** Match the existing history: a single
   imperative, capitalized summary line, no trailing period, concise but
   specific (see `git log --oneline`). Example style:
   `Harden rename script: error handling, bucket safety, validation`.
   Use a body only when the change genuinely needs explanation.

   End every commit message with this trailer (blank line before it):

   ```
   Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
   ```

   Use a HEREDOC so the trailer and any body format correctly:

   ```bash
   git commit -m "$(cat <<'EOF'
   <summary line>

   Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
   EOF
   )"
   ```

4. **Push.** This repo commits directly to `main` and pushes to `origin`
   (`git@github.com:kevin-lee-aifi/xenium.git`). Push the current branch:

   ```bash
   git push
   ```

   If the branch has no upstream, use `git push -u origin "$(git branch --show-current)"`.

5. **Report.** Print the resulting commit hash/summary and confirm the push
   succeeded (or surface the error if it failed — e.g. rejected push needing a
   pull/rebase first).

## Notes

- If there is nothing to commit, say so and stop — don't create an empty commit.
- If `git push` is rejected because the remote is ahead, stop and report it;
  don't force-push.
- Don't amend or rewrite already-pushed commits unless the user explicitly asks.
