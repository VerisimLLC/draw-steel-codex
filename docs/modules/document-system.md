# Document System

The `DocumentSystem/` directory (26 files) implements a rich journal and document framework. It combines Markdown text with embedded interactive widgets -- dice rolls, images, encounters, audio, timers, and more -- all rendered inside DMHub's UI.

---

## Architecture Overview

```
MarkdownDocument            RichTag registry            Rendering
(text + embedded tags) ---> (RichImage, RichDice, ...) ---> MarkdownDisplay / MarkdownLabel
```

The system has three layers:

1. **Document model** -- `MarkdownDocument` stores Markdown text with inline `{tag}` placeholders for rich content.
2. **Rich tag registry** -- Each embedded content type registers itself as a `RichTag`, providing factory methods for display and editing.
3. **Rendering** -- `MarkdownDisplay` and `MarkdownLabel` parse the Markdown, resolve tags, and build the final `gui.Panel` tree.

---

## MarkdownDocument

Defined in `DocumentSystem/MarkdownDocument.lua`:

```lua
MarkdownDocument = RegisterGameType("MarkdownDocument", "CustomDocument")
```

The document type inherits from `CustomDocument` (the engine's base document class). It defines a Markdown style map for headings:

```lua
local g_markdownStyle = gui.MarkdownStyle {
    ["# "]  = "<size=200%><b>",   ["/# "]  = "</b></size>",
    ["## "] = "<size=180%><b>",   ["/## "] = "</b></size>",
    -- ... through ##### for five heading levels
}
```

### The RichTag Base Class

Every embeddable widget inherits from `RichTag`:

```lua
RichTag = RegisterGameType("RichTag")
RichTag.pattern = false
RichTag.hasEdit = true
```

A `RichTag` provides three key methods:

| Method | Purpose |
|---|---|
| `RichTag.Create()` | Factory -- returns a new instance with defaults |
| `RichTag:CreateDisplay(self)` | Builds the read-only `gui.Panel` for viewing |
| `RichTag:CreateEditor(self)` | Builds the editing UI panel |

Tags register themselves into `MarkdownDocument.RichTagRegistry`:

```lua
function MarkdownDocument.RegisterRichTag(info)
    MarkdownDocument.RichTagRegistry[info.tag] = info
end
```

---

## Embedded Content Types

Each `Rich*.lua` file registers one tag type. The full set:

| File | Tag | Description |
|---|---|---|
| `RichImage.lua` | Image | Embedded images with sizing and alignment |
| `RichEncounter.lua` | Encounter | Inline encounter block with creature list |
| `RichMacro.lua` | Macro | Clickable chat macro button |
| `RichDice.lua` | Dice | Inline dice roll widget |
| `RichAbility.lua` | Ability | Ability reference card |
| `RichAudio.lua` | Audio | Embedded audio player |
| `RichCheckbox.lua` | Checkbox | Interactive checkbox (for checklists) |
| `RichCounter.lua` | Counter | Numeric counter widget |
| `RichTimer.lua` | Timer | Countdown / stopwatch |
| `RichReminder.lua` | Reminder | Timed reminder notification |
| `RichScene.lua` | Scene | Scene transition link |
| `RichSetting.lua` | Setting | Game setting toggle |
| `RichParty.lua` | Party | Party roster widget |
| `RichFollower.lua` | Follower | Follower / companion card |
| `RichDrawsteel.lua` | Draw Steel | Draw Steel-specific content block |
| `RichFishing.lua` | Fishing | Fishing minigame embed |

---

## Rendering Pipeline

| File | Role |
|---|---|
| `MarkdownDisplay.lua` | Full document viewer -- parses Markdown, resolves `{tag}` placeholders, builds a scrollable panel tree |
| `MarkdownLabel.lua` | Lightweight inline label -- renders a single Markdown string without the full document chrome |
| `Bar.lua` | Horizontal rule / separator bar widget |
| `LinkResolution.lua` | Resolves cross-document and compendium links |
| `TextStorage.lua` | Persistent text storage backend |

---

## Supporting Files

| File | Purpose |
|---|---|
| `DocumentSystem.lua` | Top-level registration, document type routing, and lifecycle management |
| `DocumentNewUser.lua` | Default "getting started" document created for new users |
| `MarkdownDocCreate.lua` | Document creation dialog UI |
| `MontageDocument.lua` | Montage (multi-scene) document variant |

!!! note "Spoiler handling"
    `MarkdownDocument.lua` includes a `StripSpoilers` function that processes curly-brace delimited spoiler blocks, tracking nesting depth to correctly hide or reveal content based on the viewer's permissions.

!!! tip "Adding a new rich tag"
    1. Create a new type with `RegisterGameType("MyRichTag", "RichTag")`.
    2. Implement `Create()`, `CreateDisplay()`, and `CreateEditor()`.
    3. Call `MarkdownDocument.RegisterRichTag(info)` with a unique `tag` string.
    4. Add this code to an existing file in `DocumentSystem/` (do not create new files without module registration).
