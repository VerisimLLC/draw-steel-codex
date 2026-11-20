# Engine request: replace the Codex logo with the app icon art

**Requested by:** Ricky, 2026-11-19. **Status:** open. **Needs:** an engine (Unity asset) change; the Lua side needs nothing.

## The ask

Replace the engine's in-app Codex logo, `ui-icons/codex-logo.png`, with the official app icon art: a d20 inside a thick orange hexagon frame, with sage, teal and navy facets. The source is `codex-logo-replacement/codex_app_icon.svg`.

## Every Codex Callout box must pick it up

All Codex Callout boxes draw the logo through that one path, so a single asset swap changes all of them. There is nothing to change per callout.

- **Movement tooltip callouts**, drawn by `GameHud.CreateCodexCalloutsPanel` (`DMHub Game Hud/GameHud.lua`). This covers every note that reaches the tooltip as a Codex Callout:
  - "Hold Ctrl while moving to teleport."
  - the mounted-creature dismount note ("To dismount: Click the lock on ...")
  - any Reminder Text modifier in the movement domain set to the **Codex Callout** colour, which is how **Shadow's Cinder Step** carries its note (`ModifierMovementText.lua`, `MovementCodexCallout`)
- **Codex Note callouts in the character builder** (`Draw Steel Character Builder/ChoicesDetail.lua`, `_codexNoteCallout`).

The same asset is also used by four other screens, which will change with it: the title bar (`CodexTitleBar.lua`), map pack browser (`MapPackBrowser.lua`), create map dialog (`CreateMapDialog.lua`) and PDF viewer (`JournalPDFViewer.lua`).

## Why it needs the engine

Lua refers to the logo as `ui-icons/codex-logo.png`. That path is a Unity asset baked into the client build (`sharedassets0.assets`), not a file the codex mod can override. `bgimage` also does not accept an SVG or a file path: tested in a running DMHub on 2026-11-19, the SVG and a PNG given by absolute path drew nothing, while the engine path drew.

What is there now (read from the Mac Steam build, 2026-10-14): Texture2D `codex-logo`, **64 x 64**, DXT5, 7 mips, with a Sprite of the same name (100 pixels per unit, pivot 0.5). It is an older piece of art, mostly blue with a thin orange rim.

## Proposed change

1. In the Unity project, find the `codex-logo` texture under the folder that resolves `ui-icons/...`.
2. Overwrite it with **`codex-logo-replacement/codex-logo-256.png`**, keeping the file name `codex-logo.png` so every Lua reference still resolves and the asset GUID and sprite references survive. 256 is recommended over 64: it stays crisp in the title bar and at high UI scale, and the mipmaps handle the small callout size.
3. Import settings: Texture Type *Sprite (2D and UI)*, Alpha Is Transparency on, Generate Mip Maps on, Wrap Mode Clamp, Filter Bilinear. If Pixels Per Unit (100) was tuned for 64 px, recheck the title bar and map pack browser; panels set explicit width and height, so this is normally fine.

The PNGs are the SVG rendered 8x supersampled on a **square** transparent canvas (the 16:19 hexagon centred), because every usage draws the logo in a square slot. A non-square image would stretch. Sizes: 1024, 512, 256, 128, 64, 32, 16.

## Acceptance

- A movement-tooltip Codex Callout shows the new art: hover a move with the mounted-creature note, or with the "Hold Ctrl" note (any creature that can teleport).
- Shadow's Cinder Step's callout shows the new art.
- A Codex Note in the character builder shows the new art (any Animal-keyword creature in the bestiary).
- The title bar, map pack browser, create map dialog and PDF viewer show it, undistorted.

Delete `codex-logo-replacement/` once the swap ships.
