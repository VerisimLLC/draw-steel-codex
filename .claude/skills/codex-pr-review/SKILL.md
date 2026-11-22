---
name: codex-pr-review
description: Codex PR Review. Review someone else's pull request to the draw-steel-codex (VerisimLLC/draw-steel-codex) as the senior reviewer. Fetches the PR without touching the working checkout, runs the codex-code-review correctness checklist on it (with extra weight on reusing existing functions and on Lua type checks), adds PR-level checks (repo hygiene, merge risk, player-facing text), reports to the reviewer, and drafts GitHub comments addressed to the PR author for the reviewer to post. Never posts, edits or merges anything. Use when asked to "review PR 472", "review this PR", "codex pr review", or invoked as /codex-pr-review <number>. For your own changes before a PR, use codex-code-review instead.
---

# Codex PR Review

You are helping the reviewer (the person running this) review a pull request someone
else wrote. Two audiences:

- **The report** is for the reviewer: what is wrong, how sure you are, and a verdict.
- **The drafted comments** are for the PR author, who is often newer to the codex. They
  must teach the rule, not just name the fix. The reviewer posts them; you never do.

Never post to GitHub, never push, never commit, never edit the PR's code, and never
switch the branch of the reviewer's codex checkout.

## Paths

- Codex clone (`<clone>` below): the root of the draw-steel-codex checkout this session
  is running in (`git rev-parse --show-toplevel`). Run every git command with
  `git -C <clone>`.
- The commands below assume the remote for `VerisimLLC/draw-steel-codex` is named
  `origin`. Check with `git -C <clone> remote -v`; if it has another name, use that name
  wherever `origin` appears.
- The checklist this skill builds on is `codex-code-review`. Always read it from
  `origin/main`, not the working tree, because the clone is often sitting on some other
  PR's branch whose copy may differ:

  ```bash
  git -C <clone> show origin/main:.claude/skills/codex-code-review/SKILL.md
  ```

- Work in the session scratchpad (`<scratch>` below). If there is none, ask where.

## Step 1 -- Fetch the PR

The argument is a PR number or a PR URL. If none is given, ask for one.

```bash
git -C <clone> fetch origin main "+pull/<N>/head:refs/remotes/origin/pr/<N>"
PR_SHA=$(git -C <clone> rev-parse origin/pr/<N>)
BASE=$(git -C <clone> merge-base origin/main $PR_SHA)
```

Don't use `FETCH_HEAD` here: with two refs fetched it names the first one (`main`), and
the "PR" silently becomes main with an empty diff. The `origin/pr/<N>` ref is a
remote-tracking ref, not a branch. Sanity check: `git log --oneline $BASE..$PR_SHA` must
list the PR's commits (the API's `commits` count). If it is empty, stop and say so.

Get the PR's title, description, author and base branch. Use `gh pr view <N>` if `gh`
exists; otherwise the public API (no token needed):

```bash
curl -s https://api.github.com/repos/VerisimLLC/draw-steel-codex/pulls/<N>
```

If the base branch is not `main`, use that branch instead of `origin/main` throughout.
If the PR is closed or merged, say so and ask whether to continue.

Check out the PR into a detached worktree in the scratchpad, so files can be read and
LuaLS can run without touching the reviewer's checkout. A detached worktree creates no
branch:

```bash
git -C <clone> worktree add --detach <scratch>/pr-<N> $PR_SHA
```

Remove it at the end (Step 7), even if the review stops early.

## Step 2 -- Read the codex-code-review checklist

Read `codex-code-review` (see Paths) in full. Its **Step 1** (what to review, noise
separation), **Step 2** (automatic checks) and **Step 3** (checklist A-F) are this
skill's checklist. Apply them with these changes, and ignore its Steps 4-5 (its report
and offer to edit are for the author's own changes). Its line saying it does not review
another person's PR is about that skill's own use; it does not apply here.

- "The change" means the PR: `git -C <clone> diff $BASE $PR_SHA` (three-dot equivalent).
  Use `--stat --ignore-cr-at-eol -w` and `--color-moved=zebra` exactly as it says.
  "Lines this change added or modified" means lines added or modified by the PR.
- Read files from the worktree, not the main clone.
- **Syntax.** Use `luac -p` as codex-code-review describes when that `luac.exe` exists and
  runs (Windows with a DMHub checkout). It is a Windows binary, so on macOS or Linux don't
  look for another one: LuaLS reports syntax errors too, so the type check covers it; say
  "Syntax: via LuaLS" in the report.
- **Types.** Run LuaLS the "Everyone else" way from codex-code-review, with the worktree
  as the codex root. Run it in the background. **On macOS, multi-worker LuaLS can print a
  problem to the console while writing `[]` to its result JSON**, so the report script
  says 0 when CI will fail. Save the console output, strip ANSI codes, and grep it for
  `[Warning]` and `[Error]` too. Only call types clean when both are empty.

## Step 3 -- Extra weight: reuse and types

The reviewer cares most about these two, so go beyond the base checklist:

- **Reuse (checklist B).** For *every* new function in the PR, not just the suspicious
  ones, search the codex (`Grep` in the worktree) for something that already does it:
  same folder, `DMHub Utils/Utils.lua`, methods on the type it works with, and two or
  three key words from what it does. Record what you searched for each one, so the
  report can say "searched, nothing found" rather than skip it. A found duplicate is a
  Should fix with the existing function's `file:line` and the PR code rewritten to use
  it. A new function that copies most of an existing one with small changes is a Should
  fix too: suggest a parameter on the existing one, listing its call sites.
- **Types.** Any LuaLS problem is a Must fix, including in files the PR did not touch
  (a renamed field can break another file). Also flag, as Should fix, new code that
  passes only because it is untyped: new `RegisterGameType` types without the
  `--- @class X: GameType` annotation, new functions taking or returning game types with
  no `---@param`/`---@return`, and new `---@diagnostic disable` lines without a comment
  saying why. Check against `TYPING.md` in the worktree.

## Step 4 -- PR-level checks

These look at the PR as a whole, not line by line.

### Repo hygiene

- **Line endings.** A file whose diff is whole-file with `git diff` but tiny with
  `--ignore-cr-at-eol` was renormalized. The rule: LF only, and a renormalization goes
  in its own commit, never mixed with real edits. Flag it as Should fix.
- **Generated or content files.** Edits to `Definitions/` (generated from the engine),
  `main.lua` (engine-generated index, never run), or anything under `data/` or
  `compendium/`. A changed `data` gitlink (`git diff $BASE $PR_SHA -- data` shows a
  `Subproject commit` line) means the PR moves the data submodule: say which commit it
  moves to and ask whether that was intended. Don't judge the content itself.
- **New files.** Every new `.lua` file needs registering with its mod in the cloud, or
  it never loads; the code can't show this. Make it a Note and a drafted question to
  the author.
- **Non-ASCII**, per codex-code-review, in every changed file.
- **Stray files**: logs, `.DS_Store`, editor folders, scratch scripts, personal
  `.claude/settings.local.json`.

### Merge risk

```bash
git -C <clone> rev-list --count $PR_SHA..origin/main          # commits behind main
git -C <clone> merge-tree --write-tree origin/main $PR_SHA     # exit 1 + list = conflicts
comm -12 <(git -C <clone> diff --name-only $BASE origin/main | sort) \
         <(git -C <clone> diff --name-only $BASE $PR_SHA | sort)   # files both changed
```

For each file both sides changed, look at what main changed: a function the PR calls
being renamed or re-signatured on main is a real risk even with no textual conflict.

Then check other open PRs touching the same files (public API; skip quietly if it fails
or is rate-limited, and say so in the report):

```bash
curl -s "https://api.github.com/repos/VerisimLLC/draw-steel-codex/pulls?state=open&per_page=100"
curl -s "https://api.github.com/repos/VerisimLLC/draw-steel-codex/pulls/<other>/files?per_page=100"
```

List overlaps as Notes for the reviewer (merge order), not as comments to the author
unless there is an actual conflict they need to resolve.

### Player-facing text

List every UI string the PR adds or changes: `text("key", [[...]])` lines in
`*Text.lua` registries, and literal strings in `gui.Label{ text = ... }`, tooltips,
buttons, dialog titles, chat messages. Give key (if any), `file:line` and the text.
The reviewer checks the wording; don't rate it. Flag only mechanical problems: a typo,
a hard-coded string where the file uses a text registry, non-ASCII.

## Step 5 -- Verdict

Pick one:

- **Approve**: no Must fix items. Should fix items may still be drafted as optional.
- **Request changes**: at least one Must fix.
- **Comment**: no Must fix, but questions the author must answer before you can tell
  (data gitlink bump, unclear intent).

## Step 6 -- Report

Write the report as your reply, to the reviewer:

```
## Codex PR Review: #<N> <title> (by <author>)

<one or two sentences: what the PR does, from the diff, not the description>
Verdict: Approve / Request changes / Comment

Checked: <n> Lua files, +<a> / -<r> (<n> moved or whitespace only). <n> commits,
<n> behind main.
Syntax/Types: OK / <n problems> / not run (why). ASCII: OK / <hits>.
Reuse: <n> new functions, each searched; <n> duplicates found.
Merge: clean / <n> conflicts; <n> files also changed on main; overlaps with #<x>, #<y>.

### Must fix
1. **<title>** - `File.lua:123`
   What / Why it matters / Suggested fix

### Should fix
(grouped: Reuse, Types, One-off functions, Names, Comments, Clarity, Hygiene)

### Notes for you
(merge order, overlaps, data gitlink, things to ask the author, old code the PR sits
next to that has the same problem: "not part of this PR")

### Player-facing text
| Key | File:line | Text |

### Drafted comments
```

Same rules as codex-code-review's report: one numbering sequence across all sections,
every finding has a `file:line` and a concrete fix, only report what you checked, group
repeats, leave out empty sections, and don't invent findings.

**Drafted comments.** After the report, give one ready-to-paste comment per Must fix and
Should fix item, plus any question from Notes the author needs to answer, then one
summary comment for the review body. Number them to match the findings. Each:

```
**#<n>** `File.lua:123` (Must fix / Suggestion / Question)
> <comment text, in a fenced block if it has code>
```

Writing them:

- Address the author directly, plainly and kindly. Say what you noticed, why it matters
  in this codebase (the rule and the reason, briefly), and the fix. They should learn
  the rule, not just apply a patch.
- Mark optional ones as suggestions. Don't pile on: if one function has five naming
  problems, it's one comment.
- Use GitHub ```` ```suggestion ```` blocks only when the fix is a drop-in replacement of
  exactly the commented lines; otherwise a normal `lua` block.
- No praise padding, no "great job but". If something is genuinely well done, the
  summary comment can say so in one line.
- These are written in the reviewer's voice, so keep them short and unlike AI prose:
  no headings, no bullet lists of three, no "I hope this helps".

End with one plain question, e.g. "Want any comments reworded, merged or dropped?" Do
not use `AskUserQuestion` for it; the reviewer has to read the report first.

## Step 7 -- Clean up

Remove the worktree when the report is written (and if the review stops early):

```bash
git -C <clone> worktree remove --force <scratch>/pr-<N>
```

If the reviewer asks for a second pass after the author pushes, fetch again and review
only what changed since `PR_SHA`, noting which earlier findings were fixed.
