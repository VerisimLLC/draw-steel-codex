# Journal Stylesheets

Stylesheets let you re-skin a journal's look -- heading sizes, colors, bullets, callout boxes -- without touching the journal's text. You define a *stylesheet* once, then point any journal at it. Change the stylesheet and every journal using it updates instantly.

> Tip: assign the **MCDM** stylesheet to this very page to see it rendered the way it's described. {.emphasis It styles itself.}

---

## Quick start

1. Open a journal and click **Edit**.
2. In the editor toolbar, use the **Stylesheet:** dropdown to pick a stylesheet (or **Default** for the plain look).
3. Save. The journal now renders in that style.

To build or change a stylesheet, open the **Compendium -> Journal Stylesheets**.

## Creating and editing a stylesheet

In **Compendium -> Journal Stylesheets**:

- **Add** a new stylesheet, then give it a **Name**.
- Set **Inherits from** to base it on another stylesheet -- it keeps everything from the parent and only changes what you override (see *Inheritance* below).
- Edit the **base skin** (headings, body, bullets) and add **named classes** (callouts and emphasis spans).

Every change saves immediately and any open journal using the stylesheet re-renders live.

### The base skin

The base skin controls the journal's structural typography:

- **Headings 1-6** -- font, size, color, weight (Regular / Bold / Black), and caps (None / Small Caps / All Caps).
- **Body** -- font and text color.
- **Bullet** -- the marker glyph and its color.
- **Quote** -- blockquotes can take their own font, text color/italic, a panel background, a colored left accent bar, and an inset.
- **Page** -- the journal's overall background color (e.g. a cream/parchment page), and a **margin** that insets the content from the page edges. When you set a light page, also set dark heading and body colors so the text reads -- the page does not auto-adjust text contrast.

You can pick a different **font** for headings, body, lists, quotes, and your named classes. Fonts come from the set configured for this build (book/display faces like the ones used in the printed book, plus utility faces). If you pick a font that isn't available it simply falls back to the standard face. Note: the book display faces don't include the straight typewriter apostrophe/quote, so use curly/typographic quotes in text that uses those faces, or the straight ones show as empty boxes.

You only set what you want to change. Anything you leave alone keeps inheriting -- from the parent stylesheet, or from the built-in default.

### Inheritance

A stylesheet can **inherit from** a parent. It starts as an exact copy of the parent, and any field you set overrides just that one field. This is how you keep a family of related looks in sync:

- Make a base "House Style" stylesheet.
- Make "House Style - Dark" that inherits from it and only overrides colors.
- Fix a heading size on "House Style" and *both* update.

## Named classes

Beyond the base skin, you can define **named classes** and apply them to specific pieces of text. There are two kinds.

### Inline classes -- `{.name text}`

An inline class styles a span *inside* a line. Define a class (e.g. `emphasis`) with a text color / weight / italic, then write:

```
The water is rising. {.emphasis Move quickly.}
```

Here, **Move quickly.** picks up the `emphasis` styling while the rest of the sentence stays normal. Unknown class names just render the plain text -- nothing breaks.

### Block classes -- `:::name`

A block class wraps several lines in a styled box -- perfect for read-aloud text, sidebars, or stat-block frames. Define a block class (e.g. `read-aloud`) with a background color, border, and padding, then fence your text:

:::read-aloud
The door groans open. Dust hangs in the still air, and far below, something stirs.
:::

Open the fence with `:::` followed by the class name, write your lines, and close with a bare `:::` on its own line.

## Buttons and embeds

A stylesheet can also skin a few non-text pieces:

- **Macro buttons** (the clickable buttons from `[[macro:...]]`) take a button skin -- background, border, corners, padding, and text color/weight -- with optional hover and pressed looks.
- **Embeds and content blocks** (embedded documents/monsters/maps, images, power rolls, tables, collapsible sections) can be given a frame -- background, border, and padding.

## The MCDM stylesheet

The **MCDM** stylesheet is modeled on the printed MCDM book: **dark ink text on a warm parchment page**, inset from the edges, with bronze-gold accents throughout. It uses the book typefaces -- a display face for the all-caps chapter title and the Newzald face for the rest of the heading hierarchy, with Berling for body text. The headings get gold underline rules (heaviest under the title, thinning down the hierarchy), the sub-heads are gold small-caps, and bullets are gold. Blockquotes render as a tan panel with a gold left accent bar. Power rolls, tables, rollable tables, and collapsible sections are all framed in gold-bordered cream boxes (tables use cream rows with a slightly darker alternating tint), and macro buttons get a matching gold-bordered tan look. It ships with two ready-to-use classes:

- `{.emphasis text}` -- bronze-gold, bold inline emphasis.
- `:::read-aloud` -- a gold-bordered tan callout box with dark italic text.

Assign it from the **Stylesheet:** dropdown to give any journal that look.

## Syntax cheat sheet

| You write | You get |
|---|---|
| `# Title` ... `###### Title` | Headings 1-6 |
| `- item` or `* item` | Bulleted list |
| `1. item` | Numbered list |
| `{.name text}` | Inline class span |
| `:::name` ... `:::` | Block class callout box |
| `> quoted` | Blockquote |
| `---` | Divider |
| `[[macro:...]]` | Macro button (takes the button skin) |

## Good to know (current limitations)

- **Fonts:** you can now pick a per-element font (a different face for headings vs. body, lists, quotes, and named classes), drawn from the faces configured for this build. An unavailable font falls back to the standard typeface, and the book display faces lack the straight apostrophe/quote (use curly quotes).
- **Clear to inherit:** once you set a field in the editor it stays an override. To make a field inherit again, clear it via import/code (a blank number field does clear that one value).
- **Inherited classes:** the class editor shows a stylesheet's *own* classes; to change a class it inherits from a parent, re-declare it by name.
- **Colors:** the editor uses literal colors from the picker.
- **Where it applies:** inline `{.class}` spans work in body paragraphs (not inside table cells or blockquotes), and block `:::` callouts don't nest.

---

> This page is also a demonstration: viewed with the **MCDM** stylesheet, its headings, bullets, the `{.emphasis ...}` span above, and the `:::read-aloud` box all render in the styled look they describe.
