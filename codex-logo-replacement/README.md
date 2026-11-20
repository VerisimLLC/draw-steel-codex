# Codex logo replacement (engine asset swap)

Handover for `ENGINE_REQUEST_CODEX_LOGO.md` at the repo root. Read that first: it says what to change, why it is an engine change, and how to check it.

| File | What it is |
|---|---|
| `codex_app_icon.svg` | The official app icon art, the source of everything else here. |
| `codex-logo-<size>.png` | The SVG rendered exactly, 8x supersampled, transparent background, on a square canvas. Sizes 1024, 512, 256, 128, 64, 32, 16. |

Use **`codex-logo-256.png`**, saved over the engine's `codex-logo.png`.

Delete this folder and `ENGINE_REQUEST_CODEX_LOGO.md` once the swap ships.
