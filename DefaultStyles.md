# DefaultStyles — UI authoring guide

**IMPORTANT:** This is a work in progress. Additional styles are sure to be added as we work through the voluminous Codex UI.

A usage guide to the color tokens, gradient tokens, and class vocabulary registered in `DMHub Core UI/DefaultStyles.lua`. The goal here is prescriptive: when you sit down to build a new panel, this should tell you which token to reach for and which class to put on which element. For cascade mechanics see `ThemeEngine.md`; for general layout/spacing rules see `UI_BEST_PRACTICES.md`.

## 1. Color tokens

Tokens are referenced as `"@tokenName"` in style rules and resolved by the active color scheme. Always reach for a semantic token rather than a literal hex; that is the only way a panel will track scheme changes.

### Surfaces

- **`bg`** — the primary canvas. Default `bgcolor` for panels, inputs, dropdowns, button rests, dock frame fills. Use this for the "back wall" of any region.
- **`bgAlt`** — the secondary surface used to set a region apart from its parent without using a border. Reach for it on: card bodies inside a panel, odd-row striping in tables, the selected dock tab container, the closed dropdown control. Rule of thumb: if you want the eye to read "this is nested," `bgAlt` is the right answer.
- **`bgInverse`** — the inverted surface. Used as the hover/selected fill on text buttons, dropdown options, and modal dialogs. Pair with `fgInverse` for text on top.

### Foreground / text

- **`fg`** — default text and glyph color. The right answer for body labels, button text at rest, dropdown text, tooltip body, icon-button tints.
- **`fgStrong`** — escalated text. Reach for it when the label needs to feel like a heading: form-row labels, modal titles, default `label` color (so most labels already get this for free).
- **`fgMuted`** — de-emphasized text. Use for disabled labels, tab rest state (non-selected tab text), placeholder-feeling content. Don't use for "ordinary" body text.
- **`fgPending`** — pending / not-yet-applied state. Reserved for the `{label, pending}` variant; reach for it when a value is provisional and should read as "not committed."
- **`fgInverse`** — text color on `bgInverse` surfaces. Pair them; never use one without the other on the same element.

### Borders

- **`border`** — default frame. Use on input borders, button borders at rest, card frames, dialog frames, table separators.
- **`borderInverse`** — frame for inverse-state surfaces (button hover frame, faded inputs). Pair with `bgInverse`.

### Accent + interactive

- **`accent`** — the link / "click me" color. Used by `{label, link}`, `hasTooltip` indicators, and `drag-target` highlights. Reach for it on text or glyphs that should advertise interactivity. Note: this is **not** the generic hover color for buttons — most controls hover via `bgInverse`/`fgInverse`. Accent is for things that look like links or drag affordances.
- **`accentHover`** — hover variant of accent. Pair with `accent` whenever you author a hover rule for a link-like element.

### Status

These four are kept consistent across schemes by convention so callers get reliable signal — don't redefine them in a new scheme unless they're unreadable on its surfaces.

- **`success`** — healthy / good / completed. Also signals a healthy stamina state.
- **`info`** — neutral information / highlight. Used for table-row highlight and the drag-ghost rest color.
- **`warning`** — winded / caution / not-yet-broken. Use for "things are getting bad but not critical."
- **`danger`** — destructive / dying / bad. The right answer for delete buttons on hover, the multiselect-chip remove indicator, drag-deleting state.

The status tokens have ready-made classes — `{success}`, `{bgInfo}`, `{borderDanger}`, etc. — covered in section 4. Reach for those before authoring a one-off rule.

### Disabled

- **`disabled`** — the disabled fill. Used as the `bgcolor` of disabled buttons. Don't use it for foreground text directly; use `fgMuted` for muted text or opt into the explicit `{fgDisabled}` / `{borderDisabled}` classes when you specifically want the disabled token.

### Implementation status

- **`implStatus0..4`** — reserved for the ability/feature implementation indicators (the colored dots on compendium entries). Authors building scheme variants should leave these alone unless one is unreadable on the new surface palette.

## 2. Gradient tokens

Referenced via `gradient = "@name"` on a panel. Always pair a gradient with `bgimage = true` and `bgcolor = "white"` (image-tint-neutral) so the gradient paints in its natural colors.

- **`surfaceLinear`** — diagonal sheen from top-left light to bottom-right dark. Already used by `{panel, dialog}`, `{framedPanel}`, `{contextMenu}`, and `{tabContainer}`. Reach for it when you need a surface that feels lit from one corner — dialogs, framed read-only displays.
- **`surfaceRadial`** — center-bright vignette. Use for full-bleed surfaces that benefit from a focal "spotlight" — large content panels, hero areas. Apply via `{panel, surfaceRadial}`.
- **`barTrack`** — left-to-right horizontal track. **Used in the application title bar** — change this token with care; it propagates to chrome the user sees constantly. Reach for it when you're authoring a new horizontal track that should match title-bar styling.
- **`maskHorizontal` / `maskVertical`** — alpha-fade utilities (transparent at the edges, opaque in the middle). Use as a `gradient` to soft-fade the edges of a list or scroll region.

## 3. Class catalog

Classes are listed roughly in the order they appear in `DefaultStyles.lua`. State classes (`hover`, `press`, `selected`, `focus`, `disabled`, `~disabled`) compose with the base classes below; size classes (`sizeXxs..sizeXxl`) compose where called out. Engine-emitted class names — those the DMHub engine writes onto sub-elements automatically — must match the file verbatim and are flagged as such.

### Section 1 — BASICS

#### Panel

`{panel}` is the base for every container. Its rest state paints `bgcolor = @bg` and uses `@fgMuted` for the scroll handle.

Compose with a gradient overlay when you want a non-flat surface:

- `{panel, surfaceLinear}` — diagonal sheen surface.
- `{panel, surfaceRadial}` — vignette surface.
- `{panel, barTrack}` — horizontal-track surface.

Specialized variants:

- `{panel, image}` — for image-displaying panels. `bgcolor = "white"` (image-tint-neutral); the panel does **not** apply a border, so you set `borderWidth`/`borderColor` per call.
- `{portraitImage}` — fixed-size compendium portrait (196x294, 2px `@border` frame). Reach for this on Race / Class / Career portrait sidebars.
- `{panel, dicePreview}` — marker class for live-dice render targets. The `bgimage = "#DicePreview"` render hookup and `bgcolor = "white"` **must** stay inline at the call site — the engine's render-target rendering doesn't honor cascade properties.
- `{panel, buttonIcon}` — auto-emitted child of `gui.Button{ icon = ... }`. Tints to `@fg` and brightens on hover; you don't apply this class manually.

#### Label

`{label}` is the base; default is 14pt `@label` font (Berling), color `@fgStrong`, auto-sized.

- **Sizes** — compose `sizeXxs..sizeXxl` (10pt..28pt) to override the font size on a label without authoring a one-off rule.
- `{label, number}` — switches to the `@number` font (Newzald). Reach for it on numeric displays where you want the heavier numerals.
- `{label, pending}` — `@fgPending` color. Reach for it when a value is provisional.
- `{label, link}` — `@accent` color, hover to `@accentHover`, dim on press. Reach for it whenever a label is clickable text.

#### Button

`{label, button}` is a text button — 31x129 default (size M), `@bg` rest fill, `@border` frame, `@fg` text. The hover rule swaps the body to inverse (`@bgInverse` / `@fgInverse` / `@borderInverse`); the press rule dims by 70% and plays `Mouse.Click`.

- **Sizes** — `sizeXxs..sizeXxl` set both width/height and font size in one go.
- `{button, hasIcon}` — icon-only button: square (100% height), no border, transparent fill, hover restores `@bg`. The `gui.Button{ icon = ... }` factory composes this for you.
- `{button, disabled}` — `@disabled` fill. The hover rule excludes disabled via `~disabled`, so disabled buttons stop reacting.
- `{button, selected}` — sticky inverse styling for "currently chosen" buttons (e.g. tab-like toggles).
- `{button, focus}` — keyboard-focus frame.

#### Input / SearchInput / ColorPicker

- `{input}` — default text input. 14pt, `@bg` fill, `@border` frame; `focus` swaps to `@fg` border.
- `{inputFaded}` — alternate input style with a faded `@borderInverse` frame. Reach for it when you want an input to read as secondary or quiet.
- `{searchInput}` — borderless 16pt bold search field. Surfaces that want a bordered search input add the border via their own `MergeStyles` extras, not here.
- `{searchInputIcon}` — auto-emitted magnifying-glass child of `gui.SearchInput`. Tinted to `@fg`. **The `floating = true` and `x = -20` positioning stay inline at the call site** — `floating` is structural, the cascade ignores it.
- `{colorPicker}` — main button of `gui.ColorPicker`. The widget sets `selfStyle.bgcolor` to the current swatch at runtime; this class owns the frame only.

#### Dropdown

`{dropdown}` is the closed control. The rest of the dropdown anatomy is **engine-emitted** — match these names verbatim:

- `{dropdownLabel}` — text shown in the closed control. Composes `parent:hover` to invert on parent hover.
- `{dropdownTriangle}` — the indicator glyph; tints to `@fg`, inverts on parent hover.
- `{dropdownBorder}` — open-state container that wraps the option list. Variants: `vcenter`, `top`, `detached` for different open positions.
- `{dropdownMenuSub}` — submenu container; hidden by default, revealed on parent hover.
- `{dropdownOption}` — individual option row; `hover` and `searchfocus` give it distinct fills, `disabled` dims to `@fgMuted`.
- `{submenuArrow}` — submenu indicator on options that open a sub-popup.

Compose `{dropdown, expandedTop}` / `{dropdown, expandedBottom}` to adjust the border when the popup opens up vs. down.

#### Multiselect chip

`gui.Multiselect` renders selected items as removable chips. The structure:

- `{panel, multiselectChip}` — the chip body. Rest fill `@bg`, `@border` frame.
- `{label, multiselectChipText}` — chip text.
- `{panel, multiselectChipRemove}` — small X button, hidden until parent chip is hovered. Carries a `@danger` border (no fill) to signal the destructive action.
- `{label, multiselectChipRemove}` — the X glyph itself. Color is `@fg` (not `@danger`) — the parent's red border carries the warning, the X just needs to be readable.

#### Slider

Two distinct widgets share this section:

- `gui.Slider` — emits `{sliderHandleBorder}` and `{sliderHandleInner}` on its handle. `{sliderNotch}` and `{sliderFill}` style the track.
- `gui.EnumeratedSliderControl` — `{enumSlider}` is the row container, `{enumSliderOption}` is each option. Compose `{enumSliderOption, selected}` / `{enumSliderOption, hover}` for state.

The widget's Lua only applies classes — all visual styling lives here so themes/schemes own it.

#### Checkbox

- `{checkbox}` — outer row container, transparent fill (the row itself just lays out children).
- `{checkBackground}` — the box. `@bg` fill, `@border` frame; desaturates on `disabled`.
- `{checkMark}` — the tick glyph; tinted to `@fg`, desaturates on `disabled`.
- `{checkboxLabel}` — the row label. Compose `rightAlign` to right-align, `disabled` to mute.

#### Tab / TabBar

- `{tab}` — a tab-strip tab. Rest is `@bg` fill / `@fgMuted` text; `hover` brightens; `selected` swaps to `@bgAlt` fill, `@fgStrong` bold text, `@fg` border.
- `{tabBar}` — horizontal container holding tabs.

Distinct from the dock-chrome `{dockTab}` in section 6 — don't conflate.

#### Tooltip

Engine-emitted — match verbatim:

- `{label, tooltipLabel}` — tooltip body text. Compose `title` for the tooltip title (bold, larger).
- `{icon, tooltipIcon}` — the small icon hint shown when a widget has an attached tooltip. `bgcolor = "white"` (image-tint-neutral).
- `{hasTooltip}` — applied to the host widget; tints to `@accent` at rest, `@accentHover` on hover.

#### Icon button

`{iconButton}` is the small accent-able click target — 24x24 default (size M), tinted to `@fg`. Hover brightens, press dims.

- **Sizes** — `sizeXxs..sizeXxl` (12x12 .. 58x58).
- **State color variants** — `withSuccess`, `withInfo`, `withWarning`, `withDanger` recolor the **hover** state to the matching status token. Reach for these when a button has a semantic outcome (a `withDanger` icon-button reads as destructive without you having to author a hover rule).
- **Kind variants** — each registered `gui.iconButtonClasses` kind carries its own bgimage:
  - `addButton`, `closeButton`, `copyButton`, `deleteButton` (auto-applies `withDanger`-equivalent hover), `settingsButton`.
- `{iconButton, flipped}` — mirror horizontally.

`gui.Button{ icon = ... }` (no `text`) returns a panel with `{iconButton}` automatically.

#### Triangle

`{triangle}` is the expand/collapse arrow. Defaults to "closed" (rotated to point right); compose `{triangle, expanded}` to rotate to point down with a short transition. Hover brightens.

#### Menu

Horizontal menu strip used by the title bar:

- `{menuItem}` — clickable item; transparent rest, `@fg` fill on hover (and `@bg` text via `parent:hover`).
- `{menuLabel}` — item label.
- `{menuItemIcon}` — leading icon glyph; tints with parent state.

#### Context menu

Right-click popup:

- `{contextMenu}` — popup panel itself; `surfaceLinear` gradient surface with `@fg` frame.
- `{contextMenuItem}` — row; transparent rest, `@fg` fill on hover.
- `{label, contextMenuLabel}` — row label; `disabled` mutes.
- `{contextMenuBind}` — keyboard-shortcut hint label.
- `{contextMenuIcon}` — leading icon glyph.
- `{contextMenuCheck}` — checkmark glyph for toggleable items.
- `{contextMenuDiv}` — horizontal divider line.
- `{contextMenuArrow}` — submenu indicator. Triangle bgimage stays inline at construction.

#### Table primitives

The engine emits `oddRow` / `evenRow` / `highlight` for striped tables; callers apply `headerRow` to the first row.

- `{label, tableLabel}` — cell text.
- `{row}` — base row.
- `{row, headerRow}` — header row; bolds the labels within via the `parent:headerRow` rule.
- `{row, evenRow}` / `{row, oddRow}` — striping pair.
- `{row, highlight}` — `@info` fill for highlighted rows.

### Section 2 — FORMS

The form pattern: a row container takes `formRow` (full-width) or `formPanel` (compact). **Every child** in that row — label, input, dropdown, multiselect, custom widget — takes the single namespace class `form`. The cascade then conjuncts `form` with each child's primitive class to pick the right rule. Children without a primitive-specific rule fall through to the bare `{form}` catch-all.

- `{formRow}` — full-width horizontal row (98% wide).
- `{formPanel}` — compact horizontal row (auto width). Used by compendium feature editors.
- `{label, form}` — form label. 18pt, `@fgStrong`, min-width 140 so labels align across rows.
- `{input, form}` / `{input, form, multiline}` — form input. 180x26 default; multiline aligns text top-left.
- `{dropdown, form}` — form dropdown. 240x30.
- `{form}` — catch-all for any form child without a primitive-specific rule (multiselect, custom widgets).
- `{formValue}` — read-only display label paired with a form input. 180x30, right-aligned.

#### Stacked forms (label-above-control)

Same pattern, vertical layout:

- `{formStackedRow}` — vertical row container (70% width).
- `{label, formStacked}` — bold label that sits above the control (98% width).
- `{input, formStacked}` / `{dropdown, formStacked}` — 98%-width controls, 30 tall, 18pt to match.
- `{formStacked}` — catch-all for stacked-form children without a primitive-specific rule.

The compound selectors on input/dropdown rules exist so the size beats any surface-specific `{input}` / `{dropdown}` sizes that callers might add via `MergeStyles` extras.

### Section 3 — CARDS

Used by class / race / background / kit feature editors:

- `{featureCard}` — outer frame; `@bgAlt` fill so the body shows through. 70% width, vertical flow.
- `{featureCardNested}` — slight width/margin tweak for cards rendered inside another card's option list.
- `{featureCardHeader}` — top strip (30 tall) holding the expand triangle, name display, and delete button. Border on all four sides; the bottom edge separates header from body. Transparent fill so the card's `@bgAlt` shows through.
- `{featureCardBody}` — body region. Border on left/right/bottom only (top edge is the header's bottom border). `@bgAlt` fill so card reads as one continuous surface.

### Section 4 — DIALOGS

#### Plain dialog

Engine-emitted around `gui.Dialog` — match verbatim:

- `{panel, dialog}` — dialog body. `surfaceLinear` gradient, `@border` frame, 4px corner radius.
- `{panel, launchablePanel}` — root panel for content registered via `LaunchablePanel.Register`. **Stays transparent** — the launchable host paints its own frame and chrome around our content.
- `{label, dialogTitle}` — centered title.
- `{dialogPanel}` — engine-emitted dialog wrapper using `panels/InventorySlot_Background.png`. `bgcolor = "white"` (image-tint-neutral). Compose `fadein` for the open animation.
- `{dialogBorder}` — engine-emitted border element; hidden by default (we draw the frame ourselves on `{panel, dialog}`).

#### Modal dialog

- `{modalDialog}` — modal body. `@bgInverse` fill, `@bg` frame, 8px corner radius.
- `{label, modalTitle}` — centered, 28pt bold, `@fgStrong`.
- `{label, modalMessage}` — 18pt body text.

#### Framed panel

- `{framedPanel}` — read-only framed surface. `surfaceLinear` gradient, `@fg` frame.
- `{framedPanel, toplevel}` — borderless 98% opacity variant for top-level windows.
- `{framedPanel, create}` — plays `UI.WindowOpen` sound on creation (excluded for hidden/collapsed).

### Section 5 — UTILITIES

#### Visibility / animation

- `{hidden}` — hide the element (no layout space removed beyond the engine's behavior for `hidden`).
- `{collapsed}` — collapse the element (removes layout space).
- `{collapseAnim}` — collapse with a 0.2s vertical scale-down animation.
- `{hideForPlayers, player}` — hide for the player role; the cascade only fires when the `player` class is also present.

#### Color composition utilities

Use these to opt a panel/label into a token without authoring a one-off rule. Naming convention:

- **Surface tokens** (`bg`, `bgAlt`, `bgInverse`) — set `bgcolor`.
- **Foreground tokens** (`fg`, `fgStrong`, `fgMuted`, `fgPending`, `fgInverse`) — set `color`.
- **Border tokens** (`border`, `borderInverse`) — set `borderColor`.
- **Accent tokens** — `{accent}` / `{accentHover}` set `color`; the `bg`-prefixed and `border`-prefixed variants (`bgAccent`, `borderAccentHover`, etc.) set the alternate property.
- **Disabled tokens** — explicit picks: `{fgDisabled}`, `{bgDisabled}`, `{borderDisabled}`.
- **Implementation status** — `{implStatus0}..{implStatus4}` set `color`.

Reach for a class when the styling is purely a token swap. Reach for a one-off rule in `MergeStyles` extras when you also need size, padding, or other layout properties.

#### Status accents

- `{success}`, `{info}`, `{warning}`, `{danger}` set `color`.
- `{bgSuccess}`, `{bgInfo}`, `{bgWarning}`, `{bgDanger}` set `bgcolor`.
- `{borderSuccess}`, `{borderInfo}`, `{borderWarning}`, `{borderDanger}` set `borderColor`.

Use to highlight a single label or panel without authoring a rule.

#### Shape / weight

- `{bordered}` — adds a 1px `@border` frame and `bgimage = true` so the border renders. Compose with anything that needs a quick frame.
- `{bold}` / `{noBold}` — flip weight. Both carry `priority = 5` so they beat the base rule.

#### Token image

Built by `gui.CreateTokenImage`:

- `{tokenImage}` — outer 60x60 container.
- `{tokenImagePortrait}` — portrait child; `bgcolor = "white"` (image-tint-neutral).
- `{tokenImageFrame}` — overlay frame.

The factory also emits the legacy kebab-case names alongside these so existing non-themed consumers (Styles.lua) keep rendering.

### Section 6 — DOCKABLE PANELS

Visual cascade for dock chrome. The dock framework wires drag/resize/minimize behavior in event handlers; this section provides the visuals those handlers toggle classes on.

- `{dock, offscreen, left}` / `{dock, offscreen, right}` — slide-in/out animation (364px matches `DockablePanel.DockWidth`).
- `{dockFrame}` — surface beneath each dock column. Compose `~uiblur` for the `@bg` fill, `parent:empty` to collapse when the dock has no panels.
- `{dockablePanel}` — inner content area of a dockable panel.
- `{tabContainer}` — header gradient strip across the top of each panel/tab group. `surfaceLinear` gradient.
- `{buttonContainer}` — per-tab clickable container; `selected` swaps to `@bgAlt` fill; `mono` removes borders for single-tab groups.
- `{dockTab}` — tab icon container, 20x20. `bgcolor = "white"` (image-tint-neutral) so the icon (set inline as `bgimage = p.data.icon`) renders at true colors. **Note: class is `dockTab`, NOT `tab`** — avoids collision with the form-style `{tab}` rule in section 1.
- `{tabLabel, crowded, ~selected}` — collapses non-selected tab labels when a tab strip has 3+ tabs; the selected tab keeps its label.
- `{dragGhost}` — drag preview. Rest is invisible `@info`; `dragging` brings it to 0.5 opacity; `dragging, deleting` swaps to `@danger`.
- `{verticalDragInvisibleHandle}` / `{verticalDragDivider}` — top-of-panel resize handles between stacked panels.
- `{dockHandle}` / `{dockHandleImage}` — side-dock close handle. `bgcolor = "white"` is image-tint-neutral (then desaturated/brightened by the rule). Compose `left` / `right` to flip and position; `parent:empty` collapses when there's nothing to dock. Hover slides toward the screen edge.
- `{minimizeArrow, lastExpanded}`, `{collapseArrow, ~minimizeArrow, minimizeSet}`, `{minimizeArrow, maximized}` — chevron visibility rules for per-panel minimize/maximize arrows.

### Section 7 — DRAG & DROP

The engine uses **kebab case** for these — match verbatim:

- `{drag-target}` — applied to a valid drop zone while a drag is in progress. `@accent` fill, `@fgInverse` text.
- `{drag-target-hover}` — hovered drop zone; adds `@accent` border and brightens to `@accentHover`.
- `{parent:drag-target}` and `{parent:drag-target-hover}` — child rules that retint text inside the drop zone to `@fgInverse` so labels stay legible against the accent fill.

All four carry `priority = 5` to beat the base rules they override.

## 4. Theme variants

`default-rounded` is the canonical example of "inherit colors + theme, override only what changes." It registers under a different theme id but shares the `default` color scheme, and its `styles` table contains nothing but `cornerRadius` overrides — 10px on panel-class surfaces, 5px on interactive controls, and asymmetric values on `featureCardHeader` / `featureCardBody` and `tab` to round only the outer corners. Use this pattern when you want to ship a stylistic variant: keep the colors, override the small set of properties that distinguish your variant.

## 5. Authoring conventions

These are the rules currently scattered across inline comments — the things that bite you if you don't know them:

- **`bgcolor = "white"` is image-tint-neutral.** Set it on any bgimage-bearing surface that should paint at native colors: portraits, dock-tab icons, render textures, dialog panels with PNG art. Without it, the surface inherits the cascade's `@bg` tint and your art comes out wrong.
- **Inline-only properties.** Some properties are structural and the cascade ignores them — they must live inline at the construction site:
  - `floating = true` and its `x` positioning partner.
  - Render-target hookups (`bgimage = "#DicePreview"`, etc.).
  - Sub-element bgimages that depend on construction-site data (e.g. context-menu submenu arrow image).
- **State-cascade properties stay out of inline.** If a `hover` / `press` / `drag-target-hover` rule flips a property, the resting value for that property must live in styles, not inline. Inline always wins over styles, and you'll get a dead state.
- **Engine-emitted class names match verbatim.** Dropdown sub-elements, slider handle parts, tooltip parts, dialog wrappers, and the kebab-case drag-target classes are written by the engine itself. Don't rename them.
- **`priority = 5`** is the convention for size and state overrides that need to beat the base rule. Use it on size variants, status accents, bold/noBold flips.
- **No component-specific selectors here.** `DefaultStyles.lua` holds only the generic theme vocabulary. Component-specific rules belong in the component's own `MergeStyles` extras, not in this file. (See the feedback memory `feedback_default_styles_scope.md` — this is a hard line.)
- **Reach for a class before authoring a rule.** Before adding `bgcolor = "@danger"` inline, check if `{bgDanger}` already exists. Before adding a 16pt size override, check if `{sizeM}` composes onto your widget. The composable utilities exist precisely to keep one-off rules out of the cascade.
