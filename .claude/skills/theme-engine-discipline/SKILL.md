---
name: theme-engine-discipline
description: Use when working on Draw Steel Codex UI/theming — applying the new ThemeEngine, picking selectors, deciding inline-vs-class, or migrating a panel onto theme classes. Keeps me from drifting back into ad-hoc inline styling and from polluting DefaultStyles with component-specific rules.
---

# Theme Engine Discipline

## Mission

Standardize the Draw Steel Codex UI on `ThemeEngine` selectors. Third parties must be able to swap in their own theme/color scheme and have the entire UI follow. Every time I add inline styling, I am chipping away at that goal.

The core rule: **the default theme provides the vocabulary; inline styling only when a use case is genuinely a one-off.** Each deviation requires the user's explicit, in-the-moment approval.

## Canonical reference

For the API and intended usage of ThemeEngine itself (`GetStyles` / `MergeStyles` / `MergeTokens` / `ResolveTokens`, `@token` syntax, `requireConfirm` on delete buttons, deprecated-controls table), read `draw-steel-codex/ThemeEngine.md`.

For the catalog of color tokens, gradient tokens, and the class vocabulary registered by `DefaultStyles.lua` — including prescriptive "which token / class do I reach for?" guidance for every widget family — read `draw-steel-codex/DefaultStyles.md`. Consult it before authoring a custom style block: usually a class already exists.

This skill assumes both docs and adds the project-specific discipline on top.

## Files that own the vocabulary

- `draw-steel-codex/DMHub Core UI/ThemeEngine.lua` — engine itself: `@name` resolver, registries, `MergeStyles` / `MergeTokens` / `GetStyles` / `ResolveTokens`, `OnThemeChanged`.
- `draw-steel-codex/DMHub Core UI/DefaultStyles.lua` — canonical color scheme + default theme. Holds **only** generic widget vocabulary (panel, label, button, input, dropdown, formRow, dialog, modalDialog, framedPanel, modalTitle, modalMessage, …). Component-specific selectors (e.g. `dt-icon-button`, `imbuement-foo`, `negotiation-something`) NEVER go here — stop and ask the user before adding anything that names a feature instead of a widget primitive.

## Decision flow when styling any element

`ThemeEngine.md` describes the three tiers (`GetStyles` → `MergeStyles` → `MergeTokens`). The discipline this skill adds:

1. **Prefer an existing selector** in `DefaultStyles.lua` over writing custom styles. Apply via `classes = {...}` and add nothing else.
2. **`MergeStyles` / `MergeTokens` extras** are for theme-aware tweaks local to one panel. Use `@token` references, never raw hex. Don't wrap them around extras that contain only layout values.
3. **Inline `selfStyle` is a last resort.** Stop and ask the user first with a one-line justification of why it can't reuse a class. Do not assume the answer.
4. **Text-markup colors go through `ThemeEngine.ResolveTokens(text)`.** TextMeshPro markup (`<color=...>`) baked into a string is invisible to the rule cascade. If a status color belongs in a markup tag, write `<color=@danger>` (or `@success`, etc.) and pass the whole string through `ResolveTokens` so the active scheme's hex is substituted at format time. Never hardcode `<color=red>` / `<color=#XXXXXX>` for status semantics.

Layout values (positions and sizes unique to a particular construction site — `halign`, `valign`, `width`, `height`, `flow`, `margin` between siblings) are fine inline as direct panel fields. Visual properties (colors, fonts, borders, hover/press states, button sizes from the size vocabulary) belong in the theme.

## Hard rules

- **`gui.PrettyButton` is being removed.** Use `gui.Button` with a theme size class (`sizeXs` / `sizeS` / `sizeM` / `sizeL` / `sizeXl` / `sizeXxl`) for every button, including modal Okay/Cancel buttons. When I encounter a `gui.PrettyButton` callsite in code I'm editing, migrate it. The `prettyButton` / `prettyButtonLabel` rules in `DefaultStyles.lua` are deprecated — do not add new dependencies on them.
- Use `bgimage = true` for paintable surfaces (signals "I just need a surface for color/border"). Inline `bgimage` without `bgcolor` renders invisible.
- `floating = true` and its `x`/`y` partners are structural — must be inline, the cascade ignores them.
- Don't put `ThemeEngine.MergeStyles`/`GetStyles` inside primitive `gui.*` widgets; the caller surface owns the cascade.
- Use `@fg` / `@fgStrong` / `@fgMuted` / `@fgPending` / `@fgInverse` / `@accent` / `@accentHover` / `@bg` / `@bgAlt` / `@border` / `@disabled` / `@success` / `@info` / `@warning` / `@danger`. Never raw hex in theme rules unless the value is intentionally scheme-independent (e.g. `"white"` for image-tint-neutral, `"clear"` for transparent).
- **`@tokens` are NEVER inline panel fields.** They only resolve inside style rule tables routed through `ThemeEngine.GetStyles` / `MergeStyles` / `MergeTokens`, or inside text markup passed through `ThemeEngine.ResolveTokens`. Writing `gui.Panel{ bgcolor = "@bg" }` ships the literal string "@bg" to the renderer and breaks. If you reach for an inline `@token`, stop: pick an existing default-theme class instead, and only fall back to a `MergeStyles` block (with the user's approval) when no class fits.
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
- Hardcoded color names or hex values inside text markup (`<color=red>`, `<color=#FF0000>`) instead of `<color=@danger>` + `ThemeEngine.ResolveTokens(...)`.

## Reference patterns

- Themed modal frame: `draw-steel-codex/DMHub Game Hud/ModalDialog.lua` — `classes = {"framedPanel"}` + `styles = ThemeEngine.GetStyles()` + `dialogTitle` label + `gui.Button{ classes = {"sizeL"} }` for buttons.
- Themed message dialog: `Hud:ModalMessage` in `draw-steel-codex/DMHub Core UI/Hud.lua` — title gets `{"modalTitle"}`, message gets `{"modalMessage"}`, Okay button gets `gui.Button{ classes = {"sizeL"} }`. Zero inline styling on those three elements; only the outer dialog panel carries layout values.
- Local theme extras with `MergeStyles`: the `mergeTestExtras` block at the bottom of `DefaultStyles.lua` (`devmode` Theme Test panel) shows the smallest valid pattern — one custom rule that resolves `@danger` and follows scheme switches.

## Popups re-root the cascade — strongly prefer `popupsInheritStyles`

Setting `element.popup = gui.Panel{...}` promotes the popup into the application's popup overlay layer. It does **not** inherit the opener's panel-tree cascade by default — even if the opener's root has `styles = ThemeEngine.GetStyles()`, the popup root sees an empty cascade, and theme classes on the popup's children (`{bordered}`, `{bg}`, `{fgStrong}`, `{dropdownOption}`, etc.) silently no-op.

**Default to `popupsInheritStyles`.** Set `element.popupsInheritStyles = true` on the **parent of the popup** (the element you're about to assign `element.popup = ...` to) **before** assigning the popup. The popup then inherits the parent's cascade automatically — no `styles` arg on the popup root, no separate `OnThemeChanged` subscription, theme switches propagate through the existing parent's subscription.

Reference: `draw-steel-codex/DocumentSystem/RichImage.lua:60` — the settings gear sets `element.popupsInheritStyles = true` immediately before assigning `element.popup = gui.Panel{ classes = {"bordered", "bg"}, ... }`, and the bordered/bg cascade resolves correctly without a popup-level `styles` block.

Order matters: `popupsInheritStyles` must be set on the parent **before** the `element.popup = ...` assignment. Setting it after has no effect.

**Only reach for explicit `styles = ThemeEngine.GetStyles()` on the popup root if** the popup is a self-contained modal/dialog whose lifetime is independent of the opener (e.g. it survives after the opener is destroyed, or it has its own theme-reactivity requirements). For 95% of popups — settings popovers, manual dropdowns, context-menu wrappers, info popouts — `popupsInheritStyles = true` on the parent is the correct answer.

## Workflow checklist before claiming a UI change is done

1. Did I add any inline styling? If yes, can it be expressed as a class — and did I ask the user before keeping it inline?
2. Did I add anything to `DefaultStyles.lua`? If yes, is the selector a generic widget primitive, or did it sneak in feature-specific naming?
3. Did I leave any `gui.PrettyButton` calls in files I touched?
4. Did I introduce any `@token` reference that isn't in the scheme's color/gradient/font tables?
5. Switched the color scheme (Default ↔ Warm Gold via the devmode Theme Test panel) — does the change track?
