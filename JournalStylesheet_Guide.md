# Journal Stylesheet Guide

How to create, apply, and author **journal stylesheets** in the Draw Steel codex
for DMHub. A journal stylesheet is a reusable, CSS-like skin that controls how a
journal/document renders: page background, heading and body typography, lists,
blockquotes, dividers, embeds, content blocks (power rolls, tables, collapses),
and your own named callout/inline classes.

Everything in this guide is keyed to the live renderer in
`DocumentSystem/MarkdownDocument.lua`. Where a field is defined in the data model
but not yet drawn by the renderer, it is called out explicitly as **reserved**.

---

## 1. Concepts at a glance

- A stylesheet is a `JournalStylesheet` record stored in the `journalStyles`
  data table. It has three parts:
  - **`name`** -- display name.
  - **`base`** -- the skin: per-element style sections (page, body, headings,
    lists, quote, rule, link, embed, blocks).
  - **`classes`** -- named **block** and **inline** classes you invoke from
    markdown (`::: name` and `{.name text}`).
  - **`parentId`** (optional) -- another stylesheet to inherit from.
- A stylesheet is **resolved** by merging it onto the built-in **default skin**,
  walking up the `parentId` chain (root ancestor first, your sheet last). Child
  values win; anything you do not set is inherited.
- **The default skin is a visual no-op.** A journal with no stylesheet, or a
  stylesheet that overrides nothing, renders exactly as an unstyled journal. You
  only ever *add* deviations; you never have to redeclare the defaults.
- A journal is wired to a stylesheet by its **`styleSheetId`**. Unset (`false`)
  means "use the default skin."

---

## 2. Quick start

### Create a stylesheet (editor UI)

1. Open the **Compendium**.
2. Choose **Journal Stylesheets** in the content-type list.
3. Click **+ / Create New** to add a sheet (or select an existing one to edit).
4. Edit fields in the form on the left; the **preview pane** on the right
   re-renders a showcase document live as you change values.
5. Give it a clear **name**.

### Apply it to a journal

1. Open the journal/document in its editor.
2. In the toolbar, find the **`Stylesheet:`** dropdown.
3. Pick your stylesheet. The document re-renders immediately and remembers the
   choice (it stores the sheet's id as the document `styleSheetId`).

That's it for the common path. The rest of this guide is the full vocabulary so
you can build a sheet that matches a printed look -- and the data-model route for
power users who want to author the whole thing directly.

---

## 3. The two authoring routes

**Editor UI** -- the form exposes the most common fields per section, with a live
preview. Best for iterating visually. Block classes show their invoke syntax as
`:::name`; inline classes show `{.name ...}`.

**Data model (Lua / direct)** -- the editor intentionally does not surface every
field. To use the *full* vocabulary in this guide, edit the record directly. The
shape is:

```lua
local s = JournalStylesheet.CreateNew()   -- or JournalStylesheet.Create()
s.name     = "My Sheet"
s.parentId = false                        -- or another sheet's id to inherit
s.base = {
    page     = { ... },
    body     = { ... },
    headings = { [1] = { ... }, [2] = { ... }, ... },   -- levels 1..5 (6 = body)
    bullet   = { ... },
    ordered  = { ... },
    quote    = { ... },
    rule     = { ... },
    link     = { ... },                   -- reserved (see section 8)
    embed    = { box = { ... } },
    blocks   = {
        powerRoll     = { box = { ... }, inner = { ... } },
        table         = { box = { ... }, inner = { ... } },
        rollableTable = { box = { ... }, inner = { ... } },
        collapse      = { box = { ... }, inner = { ... } },
    },
}
s.classes = {
    note      = { kind = "block",  box = { ... }, text = { ... } },
    keyword   = { kind = "inline", text = { ... } },
}
local id = dmhub.SetAndUploadTableItem(JournalStylesheet.tableName, s)
```

Only include the keys you want to override -- every absent key inherits.

> **ASCII only.** Like all source in this repo, keep stylesheet string values to
> plain ASCII (no curly quotes, em dashes, or ellipses) if you author them in
> Lua. Hex colors and field names are ASCII already.

---

## 4. Inheritance and the cascade

- Resolution order is **default skin -> root ancestor -> ... -> parent -> your
  sheet**. Later wins.
- `parentId = false` (or unset) means "inherit only from the default skin."
- Most sections **merge per field**: set `body.color` on a child and it overrides
  only the color, keeping the parent's `lineHeight`, `align`, etc.
- **Headings merge per level** (1..6 independently) and per field within a level.
- **Classes merge by name**; within a class the `text` and `box` sub-tables merge
  field-by-field over the parent's same-named class.
- **`embed.box` merges as a unit**: a child that sets `embed.box` replaces the
  whole box rather than overriding one field of it. (Block-type boxes under
  `blocks.*` *do* merge per field.)
- Cycles in `parentId` are detected and broken safely (logged once).

Use inheritance to keep a family of sheets consistent: make a base "house style"
sheet, then create variants that set `parentId` to it and override just a few
things (a different page color, a tighter rhythm, an extra callout class).

---

## 5. Shared value vocabularies

These value types appear across many fields.

### Colors
Any field named `color`, `bgcolor`, `borderColor`, `altcolor`, `barColor`
accepts:
- a **hex string**: `"#8a6a2e"` (and alpha hex where supported), or
- a **theme color token** (e.g. `"@fg"`), resolved against the active theme.
- `false`, `nil`, or `""` means "no override" (inherit / none).

### Weight
`"regular"` (no bold), `"bold"`, or `"black"`. Note: `bold` and `black` both
render as bold in the current font catalog (there is no separate black face yet).

### Caps
`"allcaps"` (uppercases the text) or `"smallcaps"` (TMP small caps). Unset = as
written.

### Align
`"left"`, `"center"`, `"right"`, or `"justify"`. Applies per element
(headings per level, body, bullet, ordered). Unset = left/as-authored. Setting
any align on any text element also widens block text labels so even short
isolated lines (like a lone centered heading) align correctly.

### Tracking
Letter-spacing in InDesign units (1/1000 em). Example: `-20` tightens by
`-0.02em`. `0` = none.

### The box frame (used by `embed.box`, `blocks.*.box`, and block classes)
A `box` draws a framed container. Fields:

| Field          | Meaning                                              |
|----------------|------------------------------------------------------|
| `bgcolor`      | Fill color (paints a solid panel background).        |
| `bgimage`      | Background image path (advanced; overrides the solid fill image). |
| `border`       | Border thickness in px.                              |
| `borderColor`  | Border color.                                        |
| `borderImage`  | Border image path (advanced).                        |
| `cornerRadius` | Rounded-corner radius in px.                         |
| `pad`          | Inner padding in px (auto-enables border-box sizing).|

An empty `box = {}` draws nothing (clears to no frame) -- which is exactly why an
unset frame is backward-safe.

---

## 6. Page and text sections

### `page`
| Field     | Type   | Effect                                             |
|-----------|--------|----------------------------------------------------|
| `bgcolor` | color  | Page/background color behind the document. `false` = none. |

Embedded documents inherit the host page's background, so a page color flows into
embeds automatically (frame them separately with `embed.box`).

### `body`
Applies to ordinary paragraph text.
| Field             | Type    | Effect                                                      |
|-------------------|---------|-------------------------------------------------------------|
| `color`           | color   | Body text color.                                            |
| `lineHeight`      | percent | Line height as a percent of font size (e.g. `120`). `100`/unset = no change. |
| `paragraphSpacing`| px      | Height of the gap rendered for a blank line between paragraphs (vertical rhythm). |
| `firstLineIndent` | px      | Positive indents the first line; negative is a hanging indent. |
| `align`           | align   | Paragraph alignment.                                        |

> The default-skin table also lists a `font` key, but **font selection is not
> emitted** (custom faces are blocked pending the engine font work). Leave it.

### `headings`
A map keyed by level. **Levels 1..5 are styled headings**; a level-6 line
(`######`) renders with **body** styling, not heading styling.

Per-level fields:
| Field         | Type    | Effect                                                    |
|---------------|---------|-----------------------------------------------------------|
| `sizePct`     | percent | Size as a percent of body (e.g. `210`). `100`/unset = body size. |
| `weight`      | weight  | `regular` / `bold` / `black`.                             |
| `color`       | color   | Heading color.                                            |
| `caps`        | caps    | `allcaps` / `smallcaps`.                                  |
| `tracking`    | number  | Letter spacing (1/1000 em).                              |
| `align`       | align   | Heading alignment.                                        |
| `spaceBefore` | px      | Blank gap rendered above the heading.                    |
| `spaceAfter`  | px      | Blank gap rendered below the heading (see rule note).    |
| `rule`        | table   | A horizontal rule line under the heading (see below).    |

#### Heading rules (underlines)
`headings[n].rule` draws a thin horizontal line beneath the heading -- the classic
book "section underline."
| Field    | Type  | Effect                                                          |
|----------|-------|-----------------------------------------------------------------|
| `weight` | px    | **Required, must be > 0** to enable the rule. Line thickness.   |
| `color`  | color | Rule color. If unset, falls back to the heading's own `color`.  |
| `offset` | px    | Gap between the heading text and the rule line.                 |
| `indent` | px    | Horizontal inset on each side (the rule becomes `100% - 2*indent` wide). |

When a level has a rule, its `spaceAfter` is moved to *below the rule line* (so
the rule hugs the heading and the body sits below the rule). Rules are supported
on levels 1..5.

Example -- a 3px bronze underline under H1, 2px under H2:
```lua
headings = {
    [1] = { sizePct = 300, caps = "allcaps", color = "#8a6a2e", weight = "black",
            rule = { weight = 3, color = "#8a6a2e", offset = 6 } },
    [2] = { sizePct = 210, color = "#241f17", weight = "black",
            rule = { weight = 2, color = "#8a6a2e", offset = 4 } },
}
```

### `bullet` (unordered lists: `- ` / `* `)
| Field    | Type   | Effect                                                       |
|----------|--------|--------------------------------------------------------------|
| `glyph`  | string | Replacement bullet character. `false`/`nil`/`""` keeps the authored marker. |
| `color`  | color  | Color applied to the bullet glyph.                           |
| `indent` | px     | Indent the whole item.                                       |
| `align`  | align  | Item alignment.                                              |

### `ordered` (numbered lists: `1. `, `2. ` ...)
| Field    | Type  | Effect                          |
|----------|-------|---------------------------------|
| `color`  | color | Color applied to the `N.` marker.|
| `indent` | px    | Indent the whole item.          |
| `align`  | align | Item alignment.                 |

### `quote` (blockquotes: `> `)
Currently rendered fields:
| Field    | Type  | Effect                |
|----------|-------|-----------------------|
| `color`  | color | Quote text color.     |
| `italic` | bool  | Italicize quote text. |

> `quote.bold`, `quote.justify`, `quote.barColor`, `quote.inset`, `quote.font`
> exist in the data model but are **reserved** -- not currently drawn by the
> renderer.

### `rule` (horizontal divider: `---`)
| Field       | Type | Effect                          |
|-------------|------|---------------------------------|
| `thickness` | px   | Divider line height.            |

> `rule.color`, `rule.image`, `rule.margin` are **reserved** (the engine rejected
> setting them on the divider's style in the original spike); only `thickness`
> applies today. Do not confuse this `---` divider with heading **rules** above.

### `link`
The `link` section (`color`, `underline`) is defined for forward compatibility
but is **reserved** -- the renderer does not currently restyle link text from it.

---

## 7. Embeds and content blocks

### `embed.box`
Draws a frame (the box vocabulary from section 5) around **embeds**:
- content embeds (`[:document:id]`, `[:monster:id]`, `[:map:id]`), and
- **standalone** rich-tag embeds: `encounter`, `image`, `party`, `follower`,
  `scene`, `map`.

Inline widgets that sit next to text (dice, counter, checkbox, bar, macro, timer,
sound, reminder, setting, fishing) are **never** framed. Unset/empty `embed.box`
= no frame (existing journals unchanged).

```lua
embed = { box = { bgcolor = "#efe8d6", border = 2, borderColor = "#8a6a2e",
                  cornerRadius = 4, pad = 8 } },
```

### `blocks`
Four block types, each with a `box` (outer frame) and an `inner` (interior fill):
`powerRoll`, `table`, `rollableTable`, `collapse`.

- **`box`** -- the box frame vocabulary (section 5), drawn around the whole block.
- **`inner`** for `powerRoll` / `collapse`:
  | Field     | Effect                                   |
  |-----------|------------------------------------------|
  | `bgcolor` | Interior panel background color.         |
  | `color`   | Interior text color.                     |
- **`inner`** for `table` / `rollableTable` (table rows are theme-driven, so the
  interior is set via the table's own row styles):
  | Field      | Effect                                       |
  |------------|----------------------------------------------|
  | `bgcolor`  | Row / header background.                      |
  | `color`    | Cell text color.                              |
  | `altcolor` | Alternating (even-row) background.            |

```lua
blocks = {
    powerRoll = { box = { bgcolor = "#efe8d6", border = 1, borderColor = "#8a6a2e",
                          cornerRadius = 3, pad = 8 },
                  inner = { bgcolor = "#f3edde", color = "#241f17" } },
    table     = { box = { border = 1, borderColor = "#8a6a2e" },
                  inner = { bgcolor = "#efe8d6", altcolor = "#e6dcc4",
                            color = "#241f17" } },
},
```

---

## 8. Classes (callouts and inline spans)

Classes are reusable, named styles you invoke from markdown. Each class has a
`kind`: `"block"` or `"inline"`.

### Block classes -- shaded/bordered callouts
Define a block class with a `box` (frame) and optional `text` (applied to the
whole inner content):
```lua
classes = {
    aside = { kind = "block",
              box  = { bgcolor = "#efe8d6", border = 1, borderColor = "#8a6a2e",
                       cornerRadius = 4, pad = 10 },
              text = { italic = true, color = "#3a3026" } },
}
```
Invoke it in markdown by fencing a run of paragraphs:
```
::: aside
This entire run of text -- as many lines and
paragraphs as you like -- renders inside the aside box.
:::
```
This is the ergonomic way to shade or border an arbitrary block of body text
without needing a table or collapse wrapper.

### Inline classes -- styled spans
Define an inline class with a `text` block, then wrap a span:
```lua
classes = {
    keyword = { kind = "inline", text = { weight = "bold", color = "#8a6a2e" } },
}
```
```
A {.keyword Power Roll} resolves the action.
```
Unknown class names (or a kind mismatch) fall through to plain text -- the literal
`{...}` markers are never left visible.

### The `text` markup vocabulary (block and inline classes)
| Field      | Type    | Effect                                  |
|------------|---------|-----------------------------------------|
| `size`     | percent | Font size as a percent (e.g. `90`).     |
| `weight`   | weight  | `regular` / `bold` / `black`.           |
| `italic`   | bool    | Italic.                                 |
| `underline`| bool    | Underline.                              |
| `strike`   | bool    | Strikethrough.                          |
| `tracking` | number  | Letter spacing (1/1000 em).            |
| `mark`     | bool    | Highlight (marker) behind the text.     |
| `color`    | color   | Text color.                             |
| `caps`     | caps    | `allcaps` / `smallcaps`.                |

(`font` in a class `text` block is intentionally not emitted yet.)

---

## 9. Markdown authoring cheat-sheet

What each markdown token produces and which section styles it:

| Markdown                                  | Renders as            | Styled by                |
|-------------------------------------------|-----------------------|--------------------------|
| `# ` ... `##### `                         | Headings, levels 1-5  | `headings[1..5]` (+ rule)|
| `###### `                                 | Body text             | `body`                   |
| plain line                                | Body paragraph        | `body`                   |
| blank line                                | Vertical gap          | `body.paragraphSpacing`  |
| `- item` / `* item`                       | Bulleted item         | `bullet`                 |
| `1. item`                                 | Numbered item         | `ordered`                |
| `> text`                                  | Blockquote            | `quote`                  |
| `---`                                     | Horizontal divider    | `rule.thickness`         |
| `::: name` ... `:::`                      | Block class callout   | `classes[name]` (block)  |
| `{.name text}`                            | Inline class span     | `classes[name]` (inline) |
| `\|A\|B\|` + `\|---\|---\|`               | Table                 | `blocks.table`           |
| `\|Name: Characteristic` + `\| tier...`   | Power roll            | `blocks.powerRoll`       |
| `\|Name: NdM` + `\| row...`               | Rollable table        | `blocks.rollableTable`   |
| `+ Title` + content                       | Collapsible section   | `blocks.collapse`        |
| `[:document:id]` / `[:monster:id]` / `[:map:id]` | Content embed  | `embed.box`              |
| `[[image:...]]`, `[[encounter:...]]`, ... | Rich-tag embed/widget | `embed.box` (standalone only) |

---

## 10. A worked example (book-style sheet)

A compact sheet approximating the printed Draw Steel look: parchment page, ink
body, bronze display headings with underlines, framed power rolls and tables, and
a couple of callout classes.

```lua
local s = JournalStylesheet.CreateNew()
s.name = "Book Style"
s.parentId = false
s.base = {
    page = { bgcolor = "#f3edde" },
    body = { color = "#241f17", lineHeight = 120, paragraphSpacing = 6 },
    headings = {
        [1] = { sizePct = 300, caps = "allcaps", color = "#8a6a2e", weight = "black",
                tracking = -20, rule = { weight = 3, color = "#8a6a2e", offset = 6 } },
        [2] = { sizePct = 210, color = "#241f17", weight = "black", tracking = -20,
                rule = { weight = 2, color = "#8a6a2e", offset = 4 } },
        [3] = { sizePct = 185, color = "#241f17", weight = "bold", tracking = -10 },
        [4] = { sizePct = 150, caps = "smallcaps", color = "#8a6a2e", weight = "black" },
        [5] = { sizePct = 130, color = "#241f17", weight = "bold" },
    },
    quote = { color = "#3a3026", italic = true },
    rule  = { thickness = 2 },
    embed = { box = { bgcolor = "#efe8d6", border = 2, borderColor = "#8a6a2e",
                      cornerRadius = 4, pad = 8 } },
    blocks = {
        powerRoll = { box = { bgcolor = "#efe8d6", border = 1, borderColor = "#8a6a2e",
                              cornerRadius = 3, pad = 8 },
                      inner = { bgcolor = "#f3edde", color = "#241f17" } },
        table     = { box = { border = 1, borderColor = "#8a6a2e" },
                      inner = { bgcolor = "#efe8d6", altcolor = "#e6dcc4",
                                color = "#241f17" } },
    },
}
s.classes = {
    aside   = { kind = "block",  box = { bgcolor = "#efe8d6", border = 1,
                borderColor = "#8a6a2e", cornerRadius = 4, pad = 10 },
                text = { italic = true } },
    keyword = { kind = "inline", text = { weight = "bold", color = "#8a6a2e" } },
}
local id = dmhub.SetAndUploadTableItem(JournalStylesheet.tableName, s)
```

To make a variant -- say a tighter, frameless version -- inherit and override:
```lua
local v = JournalStylesheet.CreateNew()
v.name = "Book Style (compact)"
v.parentId = id
v.base = { body = { paragraphSpacing = 2, lineHeight = 110 } }
dmhub.SetAndUploadTableItem(JournalStylesheet.tableName, v)
```

---

## 11. Tips and gotchas

- **Start from the default and add only deviations.** You never have to redeclare
  defaults; the cascade fills them in. This keeps sheets small and diff-able.
- **`######` is body, not a heading.** Only levels 1-5 are styled headings.
- **A rule needs `weight > 0`** to appear; `color` is optional (it inherits the
  heading color).
- **Heading `spaceAfter` moves below the rule** when that level is ruled -- so the
  underline stays tight to the heading.
- **`embed.box` replaces as a unit** on inheritance; `blocks.*.box` merge per
  field. Set the whole embed box in the sheet that needs it.
- **Tables are theme-driven inside.** Use `blocks.table.inner`
  (`bgcolor`/`altcolor`/`color`), not an outer paint, to color rows.
- **Reserved/not-yet-rendered:** custom `font` faces, the `link` section, most
  `quote` fields beyond color/italic, and `rule` fields beyond `thickness`.
  Setting them does no harm; they simply have no visible effect today.
- **Preview before going live.** When tuning a production sheet, copy it to a
  scratch sheet, eyeball the preview pane (or a test journal), then port the
  changes back. The preview re-renders live as you edit.
- **ASCII only** for any values you hand-author in Lua.
