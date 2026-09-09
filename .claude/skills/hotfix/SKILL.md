---
name: hotfix
description: Ship a narrow Lua fix to Draw Steel Codex clients already in the field, without a release -- cherry-pick a commit that is on main onto the exact file text the retail version runs and publish it as a version-tagged revision in the cloud code history. Use when the user says "hotfix this", "ship this fix to retail now", "patch the live version", "push a live patch for <commit or bug>", or wants a fix out before the next build.
---

# /hotfix -- live-patch the retail codex without a release

Arguments: the commit(s) to ship (sha, ref, or `A..B` range on the codex repo), and
optionally a target version and an instruction. If only a bug id or a description was
given, first find the commit that fixed it (the `/bug-fix` skill's `triage.pr`, or
`git log` on main), then continue here.

## How a hotfix works (read once)

Every codex file has a cloud revision history at `/CodeMod/{modid}/files[i].history[]`.
Each entry is `{md5, cl, engineVersion}`. A client walks that list backwards and runs the
newest entry whose `engineVersion` is at or below its own build (`CodeModFile.currentMd5`
in `CodeModManager.cs`). The in-app "Deploy Changes to Users" button appends entries
tagged with the *current* engine version, so a retail client one build behind never sees
them.

A hotfix is a new entry inserted at an **older** version tag. It is built from:

- the **base**: the exact text retail clients resolve to today, fetched by md5 from the
  cloud (never the working tree), and
- the **fix**: one or more commits on `main`, applied to that base with a three-way
  merge (`git merge-file`: parent -> commit, replayed onto the retail text).

The merged file is syntax-checked with `luac`, uploaded to `/Code/{md5}` and the GCS code
bucket, and inserted into the history at the position `CommitChanges` would use for that
version tag. The mod's `updateid` is bumped so clients re-download the record. An audit
node is written to `/CodeModHotfix/{modid}/{changelistGuid}`.

Clients pick it up **the next time they load a game** (login and game entry re-sync mods).
There is no mid-session pickup; that is deliberate.

## Script

`<S>` = this skill's `scripts/` directory (`.claude/skills/hotfix/scripts` from the codex
repo, `draw-steel-codex/.claude/skills/hotfix/scripts` from the dmhub repo).

```bash
python <S>/hotfix.py versions                       # which builds loaded a game recently
python <S>/hotfix.py status "<Mod>/<File>.lua"      # a file's history tail + what each live build runs
python <S>/hotfix.py plan  <commit...> [--target V]  # compute + show; writes NOTHING
python <S>/hotfix.py apply <commit...> [--target V]  # compute + ship
python <S>/hotfix.py revert <changelistGuid>         # take a hotfix back out
```

Credential: the MCDM Firebase service-account key (`mcdm-key.json`). It is not in any
repo. The script looks at `$DMHUB_FIREBASE_KEY`, `$DMHUB_ADMIN_DIR/mcdm-key.json`,
`~/.dmhub/mcdm-key.json`, then the known admin-tooling directories, and prints that list
if none is found. Relay the message; never move or copy the key yourself. Packages:
`pip install -r <S>/requirements.txt`.

## Procedure

1. **Identify the fix as commits on main.** Confirm with `git log` in the codex repo that
   each commit is on `origin/main` (the script refuses otherwise). If the fix only exists
   in the working tree or on a branch, it must land on main first; a hotfix that is not
   on main gets silently regressed by the next regular deploy.

2. **Check what is live.** `versions` shows builds by distinct users over the last 3 days.
   The target defaults to the most-used build. Exclude David's own uid
   (`--exclude-user 4V4KWXdW7ScFIiEyuknO4bqmQSc2`) when the numbers are close.

3. **Plan.** Run `plan <commits>` and read it in full. For every file it prints:
   - the base revision (index, md5, engineVersion) the target build resolves to;
   - where the new entry is inserted and its `engineVersion` tag. The default tag is the
     **base revision's own tag**, not the target, so every build running that base is
     patched at once. Override with `--engine-version` only if the fix needs newer engine
     features;
   - **reaches / NOT reached** lists over the live builds. A build is not reached when it
     runs a *different* base (it resolves to a newer or older revision). Each distinct base
     needs its own `plan`/`apply` with `--target` set to that build;
   - the `luac` verdict and the unified diff retail -> hotfix. The diff must contain only
     the commit's intended change. If it contains anything else, stop: the retail text and
     the commit's parent diverge and the merge pulled context along;
   - `ALREADY APPLIED` when the retail text already contains the change.
   Merge conflicts abort with the conflicted file path. Do not hand-resolve: rebase the fix
   onto the retail text as a new commit on main and hotfix that instead.

4. **Confirm with the user.** This is outward-facing: it changes what every retail player
   runs on their next game load. Show the target build, user count reached, files, and the
   diff, and get an explicit yes.

5. **Apply.** Same arguments as the plan plus `--comment` if the commit subject is not a
   good changelist line. The changelist comment is `HOTFIX <sha> for <version>: <comment>`,
   which is how it shows in the in-app Code Mod editor. The script re-reads the record
   with an ETag right before writing and aborts if the retail revision moved. It verifies by
   re-resolving the file for the target build and prints the `revert` command.

6. **Verify in the app when possible.** A dev build on the target version, or the harness,
   should show the fix after entering a game (`Sync mod: ... QUERYING FROM CLOUD` in
   `Player.log`, then the new md5). Report what was verified and what was not.

7. **Follow-up is separate.** Telling reporters (`/bug-fix ... notify` / close-out) is a
   distinct instruction; do not do it as an automatic follow-on.

## Rules and limits

- Only modifications to existing `<Mod>/<File>.lua` files. Added, deleted, or renamed files,
  merge commits, and files outside the core mod graph abort.
- Never edit the merged file by hand and never feed working-tree contents to the script.
  Reproducibility is the point: base md5 + commit sha = result.
- One base per apply. If two live builds run different revisions of the file, run the tool
  once per build with `--target`.
- Engine (C#) bugs cannot be hotfixed. A Lua workaround for an engine bug can be, but it
  must also be on main.
- The next regular in-app deploy appends at the current engine version and takes
  precedence for newer builds; nothing special is needed, as long as main has the fix.
- `revert` removes the history entries for one changelist and bumps `updateid`; it marks
  the changelist `[REVERTED]` rather than deleting it.
- Never commit the key or any secret; never print secret values.
