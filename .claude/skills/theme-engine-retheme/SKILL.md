---
name: theme-engine-retheme
description: Use when re-theming / migrating an EXISTING Draw Steel Codex source file onto ThemeEngine -- taking a legacy or partially-themed file to full GetStyles() compliance: removing custom colors, custom button styles, deprecated controls, and legacy classes wholesale. For authoring NEW themed UI or picking selectors, use theme-engine-discipline instead. Triggers on "re-theme this file", "migrate X to ThemeEngine", "convert this panel/dialog to the theme engine", "get rid of the custom styling in X".
---

# Theme Engine Re-Theming Playbook

## Mission

Take one existing source file from ad-hoc / legacy / partial styling to **full
ThemeEngine compliance**: every visual goes through `ThemeEngine.GetStyles()`
and theme classes, zero custom colors, zero custom button styles, zero
deprecated controls, zero legacy style classes -- without breaking layout or
behavior.

## Relationship to theme-engine-discipline

This skill is the **procedure**. `theme-engine-discipline` is the **rulebook**
(vocabulary, inline-vs-class decisions, `@token` rules, popup cascade,
DefaultStyles scope, the canonical `ThemeEngine.md` / `DefaultStyles.md` /
`CreatingThemes.md` references). Assume that skill is in force; do not restate
its rules here. This skill only adds the ordered migration workflow.

## The unit is the whole file

Surgical edits convert only touched lines. A re-theme converts **every**
qualifying occurrence in the file. That is the defining difference -- if you
leave one deprecated control or one raw hex behind, the file is not re-themed.

## Step 0 -- Cascade root: the question that comes first

Theme classes (`formStacked`, `bordered`, `iconButton`, ...) resolve **only**
under an ancestor that ran `styles = ThemeEngine.GetStyles()`. Before
converting anything, classify the file:

- **Owns its root** (modal / dialog / standalone panel): it must get
  `styles = ThemeEngine.GetStyles()` plus a paired
  `ThemeEngine.OnThemeChanged(mod, function() ... end)` guarded with `.valid`.
- **Child of a themed host** (anything inside a `DockablePanel` -- see
  `DMHub Core UI/DockablePanel.lua:629`): it already inherits the cascade. Do
  **not** add a second root; just convert classes.
- **Child of a legacy host** (e.g. Compendium content panels): converting
  classes is a silent no-op until a root exists. Surface this -- it changes
  scope and may need its own decision.

Getting this wrong produces invisible no-op work. This is the highest-leverage
step.

## Step 1 -- Blast-radius gate

If the file is a **shared** surface (one editor/builder feeding many content
types -- e.g. a shared `CreateEditor`), a whole-file re-theme restyles all of
them. Stop, state the blast radius explicitly, get approval, and default to a
written before/after plan. Stage large files (e.g. A: cascade roots + dialog
chrome, B: form rows, C: renames + cleanup sweep + verification).

## Step 2 -- Conversion sweep (entire file)

- Legacy style globals: `Styles.Default` / `Styles.Panel` / `Styles.textColor`
  / `Styles.*` -> drop; rely on `GetStyles()`.
- Deprecated controls (full table in `ThemeEngine.md`) -> the
  `gui.Button{ classes / icon }` equivalents. `gui.DeleteItemButton` is not in
  that table -> `gui.Button{ classes = {"deleteButton"} }`; add
  `requireConfirm = true` only if the original confirmed (verify, do not
  assume).
- Hand-rolled controls: `gui.Panel{ classes = {"clickableIcon"}, bgimage,
  press }` -> `gui.Button{ icon = ... }`; triangle/expando panels ->
  `gui.ExpandoArrow`.
- Legacy form classes `formPanel` / `formLabel` / `formInput` /
  `formDropdown` -> `formStackedRow` / `formStacked` (or `formRow` / `form`).
  These never resolved under ThemeEngine anyway.
- Raw colors (`#RRGGBB`, `"white"`, `"red"`) inline or in ad-hoc
  `styles` / `selfStyle` blocks -> theme classes. Runtime
  `element.selfStyle.color = ...` -> `element:SetClass("danger"/..., true)` and
  clear it on the opposite branch.
- Inline `fontSize` -> size classes (`sizeXxs..sizeXxl`); inline
  `bold` / `bgcolor` / `borderColor` / `cornerRadius` / `borderWidth` that
  duplicate a class -> the class (`{bordered}`, `{bold}`, ...). Clickable
  surfaces that need a hover affordance -> compose `{hoverable}` rather than a
  custom hover rule.

## Step 3 -- The collapse-rename trap

Legacy `collapsed-anim` -> `collapseAnim`. This MUST change at **both** the
class list **and** every runtime `:SetClass("collapsed-anim", ...)` call site,
or the toggle silently dies. Grep both before declaring done. The same
"rename the class AND its SetClass call sites together" rule applies to any
state class you rename.

## Step 4 -- Deliberate keeps (do NOT convert)

Converting these breaks layout or behavior:

- Layout: `width` / `height` / `halign` / `valign` / `flow` / `margin` /
  `pad` stay inline.
- Structural: `floating`, `x` / `y`, render-target `bgimage`
  (e.g. `#DicePreview`).
- `bgcolor = "white"` (image-tint-neutral) or the `{image}` class;
  `bgcolor = "clear"`.
- Data-driven colors (e.g. an effect's stored display color).
- Behavior props: `multiline`, `swallowPress`, `characterLimit`,
  `dragAndDropExtensions`, and `minFontSize` autoshrink floors (a size class
  sets the base; `minFontSize` stays).
- Checkboxes do not form-stack (single control, not a label/control pair).

When in doubt whether something is a "keep," say so and ask -- do not silently
strip behavior chasing purity.

## Step 5 -- Verification (definition of done)

The file is re-themed only when **all** of these grep clean (no matches) over
the file:

- `Styles\.Default|Styles\.Panel|Styles\.textColor`
- `gui\.(PrettyButton|CloseButton|AddButton|CopyButton|DeleteButton|DeleteItemButton|IconButton|HudIconButton|PagingButton|SimpleIconButton|SettingsButton|FancyButton|Border|PrettyBorder|SetEditor)`
- `color = "white"|color = "red"|bgcolor = "#|borderColor = "#`
- `#[0-9a-fA-F]{6}` (excluding documented scheme-independent keeps)
- `formPanel|formInput|formLabel|formDropdown`
- `collapsed-anim`
- `clickableIcon`

Plus a manual smoke test: switch Default <-> a variant scheme (devmode Theme
Test panel) and confirm the file's UI re-colors (proves the root +
`OnThemeChanged`, or the inherited host cascade, is wired).

## Report honestly

State every deliberate keep and why (image-tint-neutral, data-driven,
autoshrink, behavior). State the blast radius for shared surfaces. If a
verification grep is non-empty for a justified reason, say so explicitly
rather than hiding it.
