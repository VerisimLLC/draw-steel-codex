---
name: comment-audit
description: Harshly audit the non-luadoc comments in a NAMED set of Lua files and delete every one that does not earn its place, rewriting the survivors to a single line. Use on "audit the comments in X", "comment pass over X", "clean up the comments in X", "are these comments earning their keep", "strip the noise comments from X". Requires an explicit file/folder scope -- never run it repo-wide or on files the user did not name.
---

# Comment Audit

## Mission

A comment is a liability until it proves otherwise. It costs a reader's
attention on every pass, and it rots silently while the code around it moves.
The audit's default verdict is **delete**. A comment survives only by naming a
constraint that a competent developer, making a plausible edit, would otherwise
break.

Expect to delete 60-80% of the non-luadoc comment lines in a mature file. If
you are keeping more than a third, you are not being harsh enough.

## Step 0 -- Scope gate (blocking)

**This skill does not start without a stated scope.** The user must name the
files, the folder, or the module. If they did not, ask in one sentence and
stop.

Do not widen. A named file means that file, not its neighbours; a named module
means the `.lua` files in that directory, not the baseline codex around it.
Never sweep the whole repo.

## What is in scope

- **In scope:** every `--` comment that is not luadoc. Block banners
  (`--=====`, `-- Section`) count and almost never survive.
- **Out of scope:** every `---` luadoc comment. Do not touch, retitle or
  shorten them, even when they are verbose. They are the API surface.
- **Out of scope:** the code itself. This is not a refactor. The only
  permitted code-adjacent edit is collapsing a blank line your own deletion
  orphaned.

## The three tests

Ask these in order. The first `yes` on 1 or 2, or a `no` on 3, deletes the
comment outright.

**1. Does it restate the code?** Delete. This is the biggest bucket by far.
Tells: it narrates a layout property (`"takes what the rows above leave"` over
a `100% available`), names what a memo or cache is for, describes what a
condition tests, or reads as a section header for the lines beneath it.

**2. Does it narrate history?** Delete. Tells: "rather than what we had",
"used to", "was previously", "now that", "originally", or any defence of a
decision against an alternative nobody is proposing any more. Git has this.

**3. Does it name a WHY that a competent developer could not infer?** If no,
delete. The operational form of this test: *would a plausible edit break
something this comment prevents?* If you cannot name the edit, the comment is
decoration.

## Three more that also delete

**4. Is it duplicated?** The same rationale guarding the same trap in two
places: keep the first occurrence, delete the rest. Prefer keeping it at the
site where the trap is easiest to fall into.

**5. Is it now false?** Code moved and the comment did not. Delete it. Do not
silently repair it into a claim you have not verified; if the corrected fact
is worth keeping, verify it first, then write the corrected one line.

**6. Is the same point already in the luadoc above it?** Delete the inline
one. Dedupe toward luadoc, never away from it.

## What actually survives

Almost everything worth keeping is one of these. If a survivor does not fit a
category here, look at it again.

- **Engine or API traps.** Calling this accessor CREATES the thing it looks
  for. This property cannot be assigned after construction. This raises rather
  than returning nil. An empty list here wipes the defaults.
- **Ordering constraints.** This must land before that, and the consequence if
  it does not. These are invisible in the code and are re-broken by anyone
  tidying a function.
- **Deliberate omissions.** Code a reader will expect and not find. A comment
  is the only way absent code can speak.
- **Cross-file couplings.** A class used as a lookup marker by another file, an
  id deliberately matched to another module's vocabulary.
- **A value that looks arbitrary or wrong.** Why 99, why the same asset under
  two names, why this magic string.
- **Not the obvious call.** Why the helper you would reach for is the wrong one
  here. These prevent the exact regression they describe.

## Rewriting a survivor

One line. One sentence. No wrap. Lead with the operative fact, not the story.

- `--Not FieldsFor: it CREATES the bag, mutating the document outside a change.`
- `--Must land before the request, or the roll dialog beats the curtain to the screen.`
- `--hover cannot be re-assigned, so the tooltip is patched instead.`

Match the file's local convention exactly: this codebase writes `--Text` with
no space after the dashes inside functions, and preserves the surrounding
indentation. Keep the comment directly above the line it guards.

## Procedure

1. **Inventory.** Per file:
   `grep -nE '(^|[^-])--([^-]|$)' <file>`
   Known false positive: a `---` luadoc line containing an inline ` -- ` will
   match. Skip those; they are luadoc.
2. **Judge every hit** against the six tests before editing anything. Decide
   delete / rewrite for each, with the replacement text and its indentation.
3. **Apply.** `sed` addresses refer to input lines, so one invocation per file
   handles every deletion and range-replacement regardless of order:
   `sed -i -e '120,122c\    --One line.' -e '98,99d' <file>`
   Work descending anyway; it keeps the diff readable if you re-run.
4. **Verify** before reloading:
   - No blank run your deletion created:
     `awk 'BEGIN{b=0} /^[[:space:]]*$/{b++;next} {if(b>1) print FILENAME" "NR; b=0}' <file>`
     Collapse ones you caused. Leave pre-existing ones alone.
   - No comment left dangling immediately above an `end` or `}` unless it is
     deliberately documenting an omission.
   - Re-run the inventory grep and read the survivors as a set.
5. **Reload and check the log.** `POST /reload` on every running client, then
   confirm each touched file appears as `CodeMod: Loaded <Mod> : <File>` in
   `Player.log` with no `attempt to` / `Lua error` after it. A parse error from
   a mangled `sed` range shows up here and nowhere else.

## Reporting

Give the before/after comment-line count, then the categories you deleted and
why. Call out individually:

- any comment deleted for being **false**, and what the code actually does now;
- any **duplicate** pair and which site you kept;
- anything you kept that you were tempted to cut, so the user can overrule it.

Do not list every deletion. The user reads the diff for that.
