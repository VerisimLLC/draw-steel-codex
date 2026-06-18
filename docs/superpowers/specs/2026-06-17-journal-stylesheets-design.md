# Journal Stylesheets - Design Spec

Date: 2026-06-17
Status: Design approved, pending spec review

## Problem

Journals in the Codex (`MarkdownDocument`) render through a single hardcoded style
map (`g_markdownStyle` in `DocumentSystem/MarkdownDocument.lua:7`) that only sizes
markdown headings `#`-`#####`. There is no way to:

- re-skin a journal's structural typography (heading sizes/fonts, bullets, numbered
  lists, blockquotes, dividers, body spacing) to match the printed MCDM books, or
- define reusable, named styles (callout boxes, read-aloud panels, emphasis runs)
  that authors can apply to spans/blocks of journal content.

The goal is a CSS-like system that lives *outside* journals, that journals
*reference*, and that can get the Codex's journal rendering close to the print
version of the books -- without multi-column layout (explicitly out of scope).

## Goals

- A reusable, named **Journal Stylesheet** stored centrally; a journal references one.
- A **base skin** that drives structural typography (the centerpiece): headings 1-6,
  body, unordered/ordered lists, blockquote, divider, link.
- **Named classes** authors apply to content: `inline` (rich-text runs) and `block`
  (wrapping panels / callouts).
- **Inheritance** (`parentId`) with diff-merge down to a built-in default, mirroring
  how Theme Engine color schemes "specify only differences from default."
- Property vocabulary that is a **superset of the Theme Engine** (deliberate print
  fidelity), not bounded by it. `@tokens` remain available for scheme-following colors.
- Graceful fallthrough: unknown class / missing stylesheet / missing asset never errors.

## Non-Goals

- Multi-column body text.
- A general WYSIWYG layout engine. We map to two fixed compile targets only
  (TextMeshPro rich text, and gui panels).
- Shipping the full "Draw Steel Print" asset pack (fonts + ornamental PNGs) as part of
  the engine work. The code ships independent of assets; a faithful print stylesheet
  fills in incrementally as assets land.

## Source of Truth: the IDML

Derived from `Red Road.idml` (MCDM Crows playtest, same design language), unpacked and
parsed from `Resources/Styles.xml`, `Resources/Fonts.xml`, `Resources/Graphic.xml`.
It contains 116 paragraph styles and 69 character styles grouped exactly along the lines
of our schema: `Heads:`, `Body:`, `Sidebar:`, `Pull Quote:`, `Statblock:`,
`Chapter and Section Start:Drop Cap`, `Story and Lore:Fiction`, etc.

Key insight: nearly every style exists as a **Black/White pair** (e.g.
`Heading 1 - Black` / `Heading 1 - White`) -- identical typography, different fill color
for light vs dark pages. This is precisely the `parentId` diff-merge model: define
`Heading 1` once, override only `color` in a variant. The book is built on a cascade.

### Concrete values pulled from the IDML (defaults for the built-in skin)

Fonts: **MCDM** (display / chapter / drop cap), **Newzald** (headings),
**Berlingske Slab** (body). Custom bullet = Unicode codepoint **165** in a bullet font.

| Style | Font | Size/Leading | Weight | Caps | Tracking | SpaceAfter |
|---|---|---|---|---|---|---|
| Heading 0 (chapter) | MCDM | 24 / 24 | Book | AllCaps | -20 | 4.5 |
| Heading 1 | Newzald | 16 / 16 | Black | - | -20 | 4.5 |
| Heading 2 | Newzald | 14 / 14 | Bold | - | -10 | 4.5 |
| Heading 3 | Newzald | 11 / 11 | Black | SmallCaps | -10 | 4.5 |
| Heading 4 | Newzald | 10 / 10 | Bold | - | -10 | 4.5 |
| Heading 5 | Newzald | 9 / 9 | Bold | - | -10 | - |
| Body | Berlingske Slab | 7.5 / 11 | - | - | - | 4.5 |
| Body Bulleted | (Body) | first-line -9, left +9 | - | - | - | - |
| Pull Quote Body | Newzald | 16 / 22 | Black | - | - | center, 3 |
| Sidebar Heading | Newzald | 9 / 9 | Bold | - | - | center |
| Sidebar Body | Berlingske Slab | 7.5 / 7.5 | - | - | left/right +9 | - |
| Drop Cap | MCDM | 24 / 24 | Book | - | center, Paper color | - |

Brand colors (named swatches): **Gold Accent** = Pantone 873 C, CMYK 42/50/74/20;
**Paper** = CMYK 0/0/3/0 (cream); plus monster-role colors (Ambusher, Artillery, Brute,
Controller, Defender, Harrier, Hexer, Mount, Support, Solo, Leader). These convert to
hex for the stylesheet (CMYK->RGB during authoring).

These confirm three schema requirements that a naive CSS port would miss:
`tracking` (letter-spacing), `caps` (small/all-caps), and a bullet `glyph` expressed as
`{codepoint, font}` rather than an ASCII character.

## Architecture

### New game type + data table

Registered in `DocumentSystem/MarkdownDocument.lua` (alongside the existing RichTag
plumbing -- honoring the no-new-files rule):

```
JournalStylesheet = RegisterGameType("JournalStylesheet")
  .tableName = "journalStyles"     -- dmhub.GetTable("journalStyles")
  .name      = "New Stylesheet"
  .parentId  = nil                  -- inheritance; nil = inherit from built-in default
  .base      = { ... }              -- only overridden keys (see Base Skin)
  .classes   = { [name] = JournalStyleClass }   -- only added/overridden classes
```

`MarkdownDocument` gains one field: `styleSheetId` (nil -> built-in default skin).
Stored in the existing markdown-doc record so it round-trips through compendium
export/import like the rest of the document.

### Base skin schema (the centerpiece)

Every key optional; unspecified keys inherit parent -> built-in default.

```
base = {
  headings = { [1..6] = { size, font, color, weight, caps, tracking,
                          spaceBefore, spaceAfter } },
  body     = { font, color, size, lineHeight, paragraphSpacing, firstLineIndent },
  bullet   = { glyph = { codepoint, font }, color, indent, hangingIndent, spacing },
  ordered  = { color, indent, hangingIndent, spacing },
  quote    = { font, color, weight, italic, justify, barColor, inset },
  rule     = { image | color, thickness, margin },
  link     = { color, underline },
}
```

### Named class schema

```
JournalStyleClass
  .kind = "inline" | "block"
  .text = { color, size, font, weight, italic, caps, tracking, underline, strike,
            mark }                       -- both kinds; compiles to TMP rich text
  .box  = { bgcolor, bgimage, bgslice, gradient, borderImage, border, borderColor,
            cornerRadius, beveledcorners, pad, inset }   -- block only; gui.Panel props
```

`text` is shared by both kinds; `box` is block-only. Colors accept literal hex or
`@token` (resolved via `ThemeEngine.ResolveTokens` so scheme-following colors recolor
live). Fonts validated against `gui.availableFonts`; misses fall back to closest +
log-once (same pattern as `ThemeEngine` `_validateFontFace`).

### Resolution / cascade

`Resolve(stylesheetId)` walks `parentId` to the root (built-in default), merging
child-over-parent per key (base keys and class entries both diff-merge). Result is
**memoized per stylesheetId**, invalidated when the `journalStyles` table changes.
`parentId` cycles are broken with a visited-set and logged once.

## Rendering / compile path

In `MarkdownDocument` (`DisplayPanel` render path):

1. Resolve `self.styleSheetId` -> merged stylesheet (memoized).
2. **Base skin -> per-document `gui.MarkdownStyle`** built from resolved `base`
   instead of the module-level `g_markdownStyle` constant. Headings become
   data-driven; today's constant becomes the built-in default's heading values.
3. **Bullets / ordered lists / blockquote / rule** are currently rendered by display
   logic, NOT via the style map (only headings flow through it today). This is net-new
   work: expose knobs in `base` and thread them into the list/quote/rule rendering.
   The implementation plan must trace the exact list-rendering code first.
4. **Inline `{.class text}`** -> new branch in the existing brace tokenizer, beside the
   `{!`, `{#`, `{:lang:` cases (`MarkdownDocument.lua:92-110`). Looks up the class,
   emits its `text` rich-text tags, runs `ResolveTokens` for `@token` colors.
5. **Block `:::class ... :::`** -> registered **RichTag** (same rail as
   `RichImage`/`RichReminder`). Tokenizes the fence, renders inner markdown into a
   wrapping `gui.Panel` carrying the class's `box` props + inner `text` style.

No change to how documents are stored or synced -- purely a render-time interpretation
layer plus one new id field on the document.

## Editor UI

A stylesheet editor panel hosted in an existing DocumentSystem panel file (plan picks
the exact host -- no new files). Lists stylesheets in `journalStyles`; selecting one
shows:

- name + `parentId` picker (inheritance source),
- base-skin sections (headings 1-6, body, bullet, ordered, quote, rule, link) with
  only-override semantics,
- a list of named classes, each toggling inline/block and exposing the relevant
  property fields,
- a live preview pane rendering sample markdown through the resolved stylesheet.

The journal editor gains a stylesheet picker that sets `MarkdownDocument.styleSheetId`.

## Print-fidelity scope (v1)

Per direction: **structural typography fidelity, no columns.** v1 exposes the full
property vocabulary with safe fallbacks; a faithful "Crows/Draw Steel Print" stylesheet
is authored incrementally as fonts and ornamental assets are imported.

Two effects flagged uncertain until prototyped (do NOT block schema on them):

- **Drop cap with text wrap-around** (oversized first letter is safe; 3-line wrap may
  not be supported by the layout engine). The book uses a real Drop Cap style, so this
  is worth a spike.
- Any decorative **borderImage 9-slice frame** at journal scale -- verify it renders
  crisply before committing the "framed sidebar" class.

## Dependencies & open items

- **Font availability -- VERIFIED 2026-06-17 against the live engine.** `gui.availableFonts`
  returns 12 faces: `berling, book, colvillain, courier, display, drawsteelglyphs,
  drawsteelpotencies, gothville, liberationsans, metallord, newzald, tengwar`.

  | Book font | Used for | Engine status | Plan |
  |---|---|---|---|
  | Newzald | all headings H1-H5 | PRESENT (`newzald`) | use directly -- exact match |
  | Berlingske Slab | body | MISSING | substitute `berling` (related serif; engine default fallback). Optionally import the real slab later. |
  | MCDM | chapter title / drop cap (display, AllCaps) | MISSING | substitute **`gothville`** (chosen 2026-06-17 by visual comparison of `display`/`metallord`/`gothville`/`colvillain` rendered live in-engine; gothville reads as the most title-like heavy display caps). Import the real MCDM face later if licensed. |

  Custom bullet glyph (codepoint 165) and inline iconography -> `drawsteelglyphs` /
  `drawsteelpotencies` are the engine's icon fonts; confirm the bullet glyph's codepoint
  in `drawsteelglyphs` rather than reusing the book's 165.

  Net: the most prominent face (Newzald headings) is an exact match, body has a usable
  substitute already wired as the default, and only the chapter/drop-cap display face is
  a judgment call. Fonts do NOT block v1. The built-in default skin should ship using
  `newzald` + `berling` so it renders faithfully on stock installs; the "Print" stylesheet
  swaps in imported faces if/when licensed.
- **Ornamental assets** (frame PNGs, parchment textures, bullet-glyph font) are content
  deliverables authored separately; classes referencing missing assets fall back safely.

## Testing

- Resolution unit checks: diff-merge correctness across 2-3 inheritance levels;
  cycle defense; missing-stylesheet/unknown-class fallthrough.
- Render checks: a journal with the built-in default looks identical to today; a
  journal with a custom skin shows changed heading sizes, bullets, blockquote, divider;
  inline `{.class}` and block `:::class:::` render expected rich text / panel.
- Font fallback: a class referencing a missing font logs once and renders in fallback.
- Round-trip: `styleSheetId` and a `journalStyles` entry survive compendium
  export/import.

## File touch list (no new files)

- `DocumentSystem/MarkdownDocument.lua` -- `JournalStylesheet` type + table, resolution,
  per-document `MarkdownStyle` build, inline `{.class}` tokenizer branch, block
  `:::class:::` RichTag, `styleSheetId` field, list/quote/rule knob threading.
- An existing DocumentSystem panel file -- stylesheet editor + journal-editor picker
  (plan picks the host).
