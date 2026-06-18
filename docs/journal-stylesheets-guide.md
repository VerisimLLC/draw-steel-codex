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

- **Headings 1-6** -- size, color, weight (Regular / Bold / Black), and caps (None / Small Caps / All Caps).
- **Body** -- text color.
- **Bullet** -- the marker glyph and its color.
- **Page** -- the journal's overall background color (e.g. a cream/parchment page). When you set a light page, also set dark heading and body colors so the text reads -- the page does not auto-adjust text contrast.

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

## The MCDM stylesheet

The **MCDM** stylesheet is modeled on the printed MCDM book: **dark text on a warm parchment page**, with bronze-gold accents -- an all-caps chapter title, a bold dark heading hierarchy, gold small-caps sub-heads, gold bullets, and a gold-bordered read-aloud box. It ships with two ready-to-use classes:

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

## Good to know (current limitations)

- **Fonts:** stylesheets style size, weight, caps, spacing, and color -- but text currently renders in the journal's standard typeface. Per-element book fonts (a different face for headings vs. body) aren't applied yet; that's a known follow-up.
- **Clear to inherit:** once you set a field in the editor it stays an override. To make a field inherit again, clear it via import/code (a blank number field does clear that one value).
- **Inherited classes:** the class editor shows a stylesheet's *own* classes; to change a class it inherits from a parent, re-declare it by name.
- **Colors:** the editor uses literal colors from the picker.
- **Where it applies:** inline `{.class}` spans work in body paragraphs (not inside table cells or blockquotes), and block `:::` callouts don't nest.

---

> This page is also a demonstration: viewed with the **MCDM** stylesheet, its headings, bullets, the `{.emphasis ...}` span above, and the `:::read-aloud` box all render in the styled look they describe.
