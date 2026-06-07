# Patreon Status in Settings -> Account (Codex) - Design

**Date:** 2026-06-07
**Status:** Approved - ready for implementation plan
**Repo:** draw-steel-codex (Lua mod for DMHub)

## Goal

Surface the user's DMHub Patreon membership in the codex desktop app under
**Settings -> Account**, and give non-patrons a one-click way to start linking
their Patreon account. Reuse the existing engine plumbing rather than
re-implementing any OAuth or tier logic in the client.

## Background / why this is decoupled

Per the prior brainstorm (`dmhubclient/docs/superpowers/specs/2026-06-01-patreon-account-linking-notes.md`),
the architecture is:

- **Linking (the Patreon OAuth round-trip) happens in the web companion**
  (`codex.mcdm.com`), where the browser session is already authenticated
  (Steam OpenID / handoff) and redirects are natural.
- **The desktop/codex app only reflects the resulting tier.** The engine
  monitors `/Patrons/{uid}` in Firebase RTDB and exposes the result to Lua as
  `dmhub.patronTier` (number; `0` = not a patron).

Consequence: the codex client never touches OAuth secrets or Firebase. It only
(a) reads `dmhub.patronTier` for status and (b) opens a URL for the connect
action. This holds even though the companion's connect page may not be wired up
on every branch yet - the codex side is forward-compatible.

## Scope

- **In scope:** DMHub Patreon campaign status + a "Connect Patreon" entry point
  in Settings -> Account.
- **Out of scope:** the companion OAuth connect page and Cloud Functions
  (`patreonLink` / `patreonWebhook` / `patreonReconcile`); MCDM dual-campaign
  display (blocked on the MCDM partnership); any unlink flow (browser-side).

## Location

Inside the existing `SettingGroup{ group = "Account" }` in
`DMHub Titlescreen/SettingsScreen.lua` (around line 664), added as a new
vertical subsection after the Subscription block (~line 759). It mirrors the
Subscription block's structure and styling for consistency: plain `gui.Label` /
`gui.Button`, no new DefaultStyles rules, no ThemeEngine migration of the
surrounding section.

## Data source

`dmhub.patronTier`. Read live via a `think` handler with `thinkTime = 0.1`,
exactly like the existing Subscription label (`SettingsScreen.lua:733`), so the
section updates the instant the browser link completes and the engine's
`/Patrons/{uid}` monitor pushes a new tier value. No polling of Firebase, no
secrets in the client.

## Tier label map

Mirrors the companion's source of truth (`draw-steel-companion/src/account/patronTier.js`)
so both surfaces label tiers identically. Defined as a local table in
`SettingsScreen.lua`:

| `patronTier` | Label |
|---|---|
| 1 | Whelp |
| 2 | Goblin |
| 3 | Hobgoblin |
| 4 | Bugbear |
| > 4 (unknown) | "Tier N" |
| 0 / invalid | not linked (see states) |

## States

| `dmhub.patronTier` | Display |
|---|---|
| `> 0` | Heading **"DMHub Patreon"**; line *"Patron tier: <Name>"* in an accent color; a muted "Manage on Patreon" link -> `https://www.patreon.com/c/dmhub`. |
| `0` | Heading **"DMHub Patreon"**; line *"Link your Patreon account to unlock patron benefits."*; a **"Connect Patreon"** button -> `dmhub.OpenURL("https://codex.mcdm.com/more/account")`; a "Support us on Patreon" link -> `https://www.patreon.com/c/dmhub`. |

## Connect action

`dmhub.OpenURL("https://codex.mcdm.com/more/account")` - the same `dmhub.OpenURL`
already used for the ToS / Privacy links (`SettingsScreen.lua:708`). The browser
performs the authenticated OAuth link; the desktop app reflects the result
automatically through `dmhub.patronTier`.

## Constraints honored

- **No new Lua files** - edit `DMHub Titlescreen/SettingsScreen.lua` only
  (DMHub module loading requires registration; new files will not auto-load).
- **ASCII-only** source (no em dashes, curly quotes, or ellipses).
- **Forward-declare** any self-referencing panel locals before assigning, so
  event closures (`click`, `think`) can reference them.

## Known limitation

Until the companion's `/more/account` page exposes the Patreon connect control,
the "Connect Patreon" button opens that page but the user will not yet see a
connect action there. The codex implementation is correct and needs no change
when that ships.

## Open questions

None blocking. (MCDM-campaign display and the companion connect page are
tracked in the 2026-06-01 notes and are out of scope here.)
