---
name: theme-engine-discipline
description: Use when working on Draw Steel Codex UI/theming — applying the new ThemeEngine, picking selectors, deciding inline-vs-class, or migrating a panel onto theme classes. Keeps me from drifting back into ad-hoc inline styling and from polluting DefaultStyles with component-specific rules.
---

# Theme Engine Discipline

## Mission

Standardize the Draw Steel Codex UI on `ThemeEngine` selectors. Third parties must be able to swap in their own theme/color scheme and have the entire UI follow. Every time I add inline styling, I am chipping away at that goal.

The core rule: **the default theme provides the vocabulary; inline styling only when a use case is genuinely a one-off.** Each deviation requires the user's explicit, in-the-moment approval.

## Files that own the vocabulary

- `draw-steel-codex/DMHub Core UI/ThemeEngine.lua` — engine itself: `@name` resolver, registries, `MergeStyles` / `ResolveStyles` / `GetStyles`, `OnThemeChanged`.
- `draw-steel-codex/DMHub Core UI/DefaultStyles.lua` — canonical color scheme + default theme. Holds **only** generic widget vocabulary (panel, label, button, input, dropdown, formRow, dialog, modalDialog, framedPanel, modalTitle, modalMessage, …). Component-specific selectors (e.g. `dt-icon-button`, `imbuement-foo`, `negotiation-something`) NEVER go here — stop and ask the user before adding anything that names a feature instead of a widget primitive.

## Decision flow when styling any element

1. Find an existing selector in `DefaultStyles.lua` that fits → apply it via `classes = {...}` and add nothing else.
2. Need a small theme-aware tweak local to one panel → `ThemeEngine.MergeStyles{ extras }` at the cascade root, or `ThemeEngine.ResolveStyles{ extras }` at a downstream panel that already has a themed ancestor. Use `@token` references, never raw hex.
3. Genuinely unique one-off → inline `selfStyle`, but **stop and ask the user first** with a one-line justification of why it can't reuse a class. Do not assume the answer.

Layout values (positions and sizes that are unique to a particular construction site — `halign`, `valign`, `width`, `height`, `flow`, `margin` between siblings) are fine inline as direct panel fields. Visual properties (colors, fonts, borders, hover/press states, button sizes from the size vocabulary) belong in the theme.

## Hard rules

- **`gui.PrettyButton` is being removed.** Use `gui.Button` with a theme button-size class (`btnSm` / `btnMd` / `btnLg`) for every button, including modal Okay/Cancel buttons. When I encounter a `gui.PrettyButton` callsite in code I'm editing, migrate it. The `prettyButton` / `prettyButtonLabel` rules in `DefaultStyles.lua` are deprecated — do not add new dependencies on them.
- Use `bgimage = true` for paintable surfaces (signals "I just need a surface for color/border"). Inline `bgimage` without `bgcolor` renders invisible.
- `floating = true` and its `x`/`y` partners are structural — must be inline, the cascade ignores them.
- Don't put `ThemeEngine.MergeStyles`/`GetStyles` inside primitive `gui.*` widgets; the caller surface owns the cascade.
- Use `@fg` / `@fgStrong` / `@fgMuted` / `@fgPending` / `@fgInverse` / `@accent` / `@accentHover` / `@bg` / `@bgAlt` / `@border` / `@disabled` / `@success` / `@info` / `@warning` / `@danger`. Never raw hex in theme rules unless the value is intentionally scheme-independent (e.g. `"white"` for image-tint-neutral, `"clear"` for transparent).
- Token names that don't exist resolve to magenta (`#FF00FF`) and log a warning. If you see `THEME_ENGINE:: unresolved color reference: @something` in the log, fix the rule that produced it — don't register a new token.
- One property per line in style tables.
- Lua strings use double quotes.
- Read scope: only files the user names + files matching the current task + files that contain `ThemeEngine`. Ask before reading anything else.

## Anti-patterns to flag immediately

- Any new `gui.PrettyButton{...}` call, or any existing one left untouched in code I'm editing.
- Inlined hex colors that duplicate `@bg`/`@fg`/etc.
- `selfStyle` blocks that re-declare what a class already provides (e.g. `fontSize`, `color`, `bgcolor`, `borderColor` on a label that has a class which already sets them).
- New rules added to `DefaultStyles.lua` whose selector names a feature rather than a widget primitive.
- `@token` references where the token isn't registered (e.g. `@text` instead of `@fgStrong`/`@fg`).
- Wrapping `ThemeEngine.MergeStyles{...}` around extras that contain only layout values — those belong on the panel itself, not in the cascade.

## Reference patterns

- Themed modal frame: `draw-steel-codex/DMHub Game Hud/ModalDialog.lua` — `classes = {"framedPanel"}` + `styles = ThemeEngine.GetStyles()` + `dialogTitle` label + `gui.Button{ classes = {"btnLg"} }` for buttons.
- Themed message dialog: `Hud:ModalMessage` in `draw-steel-codex/DMHub Core UI/Hud.lua` — title gets `{"modalTitle"}`, message gets `{"modalMessage"}`, Okay button gets `gui.Button{ classes = {"btnLg"} }`. Zero inline styling on those three elements; only the outer dialog panel carries layout values.
- Local theme extras with `MergeStyles`: the `mergeTestExtras` block at the bottom of `DefaultStyles.lua` (`devmode` Theme Test panel) shows the smallest valid pattern — one custom rule that resolves `@danger` and follows scheme switches.

## Workflow checklist before claiming a UI change is done

1. Did I add any inline styling? If yes, can it be expressed as a class — and did I ask the user before keeping it inline?
2. Did I add anything to `DefaultStyles.lua`? If yes, is the selector a generic widget primitive, or did it sneak in feature-specific naming?
3. Did I leave any `gui.PrettyButton` calls in files I touched?
4. Did I introduce any `@token` reference that isn't in the scheme's color/gradient/font tables?
5. Switched the color scheme (Default ↔ Warm Gold via the devmode Theme Test panel) — does the change track?
