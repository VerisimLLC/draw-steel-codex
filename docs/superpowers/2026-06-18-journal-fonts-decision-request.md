# Decision request: per-element fonts in journal rich text

**Date:** 2026-06-18
**For:** Senior engineer (DMHub engine)
**From:** Journal Stylesheets work (Lisa)
**Status:** Feature shipped without this; this is a fidelity follow-up. Not urgent, but I'd like your read before I invest in a rework.

## The one question

Can we apply a **font per text-run** inside a journal's rich text (e.g. a Newzald heading immediately above Berling body, in the same paragraph block)? Inline `<font="...">` markup appears to be a no-op in our text renderer (evidence below). If that's expected, is the right path to render each markdown block in its own label, or is there a mechanism I'm missing?

## Context (what's built)

We added a **journal stylesheet** system (4 plans, merged to `main`, all in `DocumentSystem/MarkdownDocument.lua` + a Compendium editor). A stylesheet re-skins a journal's typography; a journal references one by `styleSheetId`. It already works for: heading sizes, weight (bold), small/all-caps, letter-spacing, colors, bullet/list/blockquote/divider treatment, and named inline `{.class}` / block `:::class:::` callouts. Live re-render on edit. There's an editor under Compendium -> Journal Stylesheets and a picker in the journal editor.

**How it renders (this is the crux):** a journal's text is tokenized; each text token is rendered into a **single `gui.Label`** with `markdown = true`. The stylesheet works by **injecting inline TMP markup** into that label's text string -- `<size>`, `<b>`, `<color>`, `<cspace>`, `<smallcaps>` -- via `ApplySkinToText` before assignment. (We pivoted to this after confirming a per-document `gui.MarkdownStyle` swap does NOT restyle headings/bullets.)

Code anchors (`DocumentSystem/MarkdownDocument.lua`):
- `ApplySkinToText` (the inline-markup transformer): line 629; the `Skin*Markup` helpers: lines 486-627.
- The single per-text-token label: `local textPanel = ... or gui.Label{ ... markdown = true, markdownStyle = g_markdownStyle, ... }` at line 2145.
- The wire-in: `textPanel.text = ApplySkinToText(ApplyInlineClasses(text, resolvedClasses), resolvedSkin)` at line 2296.

## The blocker: fonts

The book ("Red Road" / MCDM) uses three faces, and the engine already has matches in `gui.availableFonts`:

| Book face | Used for | In engine | We'd use |
|---|---|---|---|
| Newzald | headings | yes (`newzald`) | `newzald` |
| MCDM | chapter title / drop cap | no | `gothville` (closest display face) |
| Berlingske Slab | body | no | `berling` (closest serif) |

The stylesheet schema HAS a per-element `font` field (headings, body, classes), but the renderer never emits it -- because inline `<font>` doesn't work for us.

### The spike (evidence)

Rendered four labels with `fontSize = 30`, identical except the inline font tag:

```lua
gui.Label{ markdown=true, text = '<font="gothville">CHAPTER ONE</font>' }
gui.Label{ markdown=true, text = '<font="newzald">Heading Text</font>' }
gui.Label{ markdown=true, text = '<font="berling">Body paragraph text.</font>' }
gui.Label{ markdown=true, text = 'Default face for comparison' }
```

**Result:** all four rendered in the **same default face**. The `<font="...">` tag is consumed (no literal tag text shows) but the typeface does not change. By contrast, `<color>` and `<size>` inline tags DO render correctly in the same path.

So: within a single label, we cannot switch to these fonts via inline markup. Since headings and body share one label per text token, per-element book fonts aren't reachable through the mechanism the whole stylesheet layer is built on.

(What this is NOT: not a missing-asset problem -- `newzald`/`gothville`/`berling` are all in `gui.availableFonts` and work fine as the `fontFace` *property* on a label. It's specifically inline-tag font switching that no-ops.)

## What "Default" looks like today (without fonts)

I authored a "Default" stylesheet from the Red Road IDML values (heading hierarchy, weights, small/all-caps, negative tracking, Pantone-873 gold accent, gold callout box), adapted for our light-on-dark journals. It captures the book's **structure and identity** -- gold all-caps chapter title, bold heading hierarchy, gold small-caps sub-heads, gold bullets, a gold-bordered read-aloud box -- but the **type is the journal's default face**, not Newzald/Berling. (Screenshot available.)

## Options + costs

| Option | What | Cost | Limitation |
|---|---|---|---|
| **A. Whole-journal `fontFace`** | Set the text label's `fontFace` property to one book face (e.g. `berling`). | Small (one property). | One face for the WHOLE journal -- headings and body both `berling`, not Newzald-for-heads + Berling-for-body. |
| **B. Per-element labels** | Render each markdown block (heading vs body) in its own `gui.Label`, so each carries its own `fontFace` from the stylesheet's `font` field. | Medium-large rework of the text-token render in `DisplayPanel`. | Risk: `MarkdownDocument.lua` is a ~4k-line core file used app-wide; want to avoid regressing inline flow / layout / perf. |
| **C. Status quo** | Ship the structural match; no per-element fonts. | Zero. | Type is the default face. |

## What I'd value your read on

1. **Is inline `<font="...">` expected to no-op** in our TMP setup? Do these font assets need registering/aliasing in a TMP font-asset fallback table (or a different tag form) to switch inline -- i.e., could Option B-via-inline become cheap?
2. **Is the single-label-per-text-token design load-bearing** (perf / inline rich-text flow / link handling), or is rendering each block as its own label (Option B) reasonable? Any landmines in `DisplayPanel` I should know about?
3. **Faces:** are `newzald` / `gothville` / `berling` the intended stand-ins, or are the actual book faces (MCDM, Berlingske Slab) importable as engine assets?

## My confidence

- **High:** the structural styling (sizes/weights/caps/tracking/colors/callouts) is solid and shipped; inline `<color>`/`<size>` work; inline `<font>` empirically no-ops here.
- **Low (your domain):** *why* inline font no-ops, whether there's a supported per-run font path, and whether Option B is safe in the journal renderer. That's the gap this note is asking you to close.
