# Journal Stylesheets - Whole-Journal Page Background

Date: 2026-06-18
Status: Design approved, pending spec review
Extends: the journal stylesheets feature (Plans 1-4, merged). See
`2026-06-17-journal-stylesheets-design.md`.

## Problem

A stylesheet can re-skin a journal's typography and add callout boxes, but it
cannot set the **journal's overall page background**. Journals always render on
the app's theme background (dark). The printed MCDM books are dark-on-cream, so
matching them is impossible without a page background -- and without it,
stylesheets are stuck adapting to the dark theme rather than reproducing the
book's actual colors.

## Goal

Add a single **page background color** to the base skin, applied to the journal's
content container at render time, editable in the stylesheet editor. This lets a
stylesheet render a journal on cream/parchment (or any color) so an author can
then use dark-on-light text the way the book does.

## Non-Goals

- Background **image / texture** (parchment). Natural next step, but needs an
  imported asset (like the deferred fonts). The schema field name leaves room
  (`page.bgcolor` now; `page.bgimage` later). Out of scope for v1.
- Auto-choosing text colors for contrast. The author sets heading/body text
  colors themselves (those fields already exist). We do NOT guess.

## Feasibility (verified by live spike)

Setting the journal content panel's own `bgcolor` (with `bgimage =
"panels/square.png"` so it paints) DOES render a page background behind the
content -- confirmed on a real `DisplayPanel`, not just a wrapper. The spike also
confirmed the contrast coupling: light heading text was nearly invisible on a
cream page, which is why text colors are the author's responsibility (below).

## Design

### Schema (base skin)

Add one optional base-skin section:

```
base.page = { bgcolor = <hex or @token, or unset> }
```

Unset (the default) = no page background (today's transparent/theme look). Only
this one field in v1. Merges/inherits exactly like the other base sections
(diff-merge down the `parentId` chain).

### Render

When the resolved base skin has `page.bgcolor`, paint the journal's content
container at render: `bgimage = "panels/square.png"`, `bgcolor = SkinColor(...)`.
When it is unset, CLEAR those properties (set to nil) before applying, so a
reused panel does not keep a stale background and the default skin stays a visual
no-op. Apply this in the same render path that already computes `resolvedSkin`,
so it re-applies live when the stylesheet changes (the existing
`journalStyles`-table monitor already drives re-render).

### Editor

Add a **"Page background"** color row to the base-skin section of the stylesheet
editor (near the Body row), using the existing `JSE_ColorRow` helper (which now
correctly converts the picked Color to a hex string). Override semantics match
the rest of the editor: it displays the resolved value and writes only this
sheet's own `base.page.bgcolor`.

### Contrast (documented, not automated)

A light page needs dark text. The author sets heading and body **text colors**
via the existing color fields. The guide and a one-line note near the Page
background control call this out. No auto-contrast logic.

## Testing

- Pure/logic: a resolved skin with `page.bgcolor` set carries it through;
  unset/inherited cases behave (diff-merge); unknown/no-stylesheet -> no page bg.
- Render (screenshot): a journal with a page-background stylesheet shows the
  color behind its content; toggling it off (clear the field) removes it live;
  the default skin (no page bg) renders identical to today.
- Editor (screenshot): the "Page background" row appears and sets the color;
  the journal updates live.

## Files (no new files)

- `DocumentSystem/MarkdownDocument.lua` -- the `page` skin field default in
  `g_defaultSkin` (unset/false), the render-time application in the
  DisplayPanel/refresh path, and the editor "Page background" row in
  `JournalStyleEditor_BuildForm`.
