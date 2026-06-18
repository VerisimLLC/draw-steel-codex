# Discord Account Linking — Design

**Date:** 2026-06-14
**Status:** Approved (brainstorm), pending spec review
**Repos:** companion (`draw-steel-companion`, frontend) + backend (`dmhubclient/cloud-functions`)
**Firebase project:** `mcdm-385cf`

## Goal

Let a signed-in Codex user link their Discord account from the Account page. On
link: add them to the Draw Steel Discord server (if not already a member), grant
a single "linked" role, and show their Discord handle + avatar. On unlink:
remove the role and clear the stored link.

This is the same "connect an external account" shape as the existing Patreon and
Shopify links — it slots in beside them with no new infrastructure.

## Scope (v1)

**In:**
- OAuth link / unlink flow (`identify` + `guilds.join` scopes).
- Auto-add the user to the configured guild on link.
- Grant one configured "linked" role; remove it on unlink.
- Show Discord display name + avatar on the Account page when linked.

**Explicitly out (designed to bolt on later, not built now):**
- Tier-based roles (Patreon tier → role mapping). The role is a flat "linked".
- Notifications (DMs / channel posts).
- Live presence / online status (would need a privileged gateway intent and an
  always-on bot connection — none of v1 needs the gateway).
- Login-with-Discord (Steam remains the sole identity anchor; this only *links*).

## Key design decision: who holds which token

The **user's** OAuth access token is used **once, server-side, inside the
callback** — passed in the body of the "add guild member" call so Discord adds
them to the guild on their own behalf (`guilds.join`). The **bot's** token does
the role assignment. Both happen within `discordAuthCallback`, so:

- No token ever reaches the browser.
- We **never persist the user's OAuth tokens.** `/discordLinks/{uid}` is pure
  profile data. (This is leaner than the Patreon record, which stores
  access/refresh tokens because it has a reconcile job; v1 Discord has none.)

## Architecture

### Frontend (companion)

Mirrors the Patreon/Shopify connect UI exactly.

- **`src/auth/discord.js`** — near-copy of `src/auth/patreon.js`:
  - `startDiscordLink()` — POST the Firebase ID token to the start Function, then
    `window.location.assign(data.authorizeUrl)`.
  - `unlinkDiscord()` — POST the ID token to the unlink Function.
  - Both read their Function URLs from `import.meta.env`.
- **`src/account/useDiscordLink.js`** — live RTDB subscription to
  `/discordLinks/{uid}` (modeled on `usePatronTier` / `useShopLink`). Returns
  `{ linked, displayName, avatarUrl, loading }`. Builds the CDN avatar URL from
  `discordUserId` + `avatar` hash (falls back to the default-avatar CDN path when
  the hash is null).
- **`src/account/ConnectDiscordSection.jsx`** — a section component modeled on
  `ConnectShopifySection.jsx`, rendered in `AccountPage.jsx` after
  `<ConnectShopifySection />`. States:
  - not `codex-user` → "Link your Codex account to connect Discord."
  - loading → "Checking Discord connection…"
  - linked → avatar + `@displayName` + **Disconnect** (per-action busy state).
  - not linked → **Connect Discord** (primary button).
  - Reads the `?discord=linked|error` return param once on mount and clears it
    from the URL (same one-shot pattern as `PatreonSection`).
- **Config gate** — a `discordConfigured` boolean (both `VITE_DISCORD_*_FN_URL`
  set), mirroring `patreonConfigured`: until the backend URLs exist, the
  connect/disconnect buttons are hidden so production never shows a button that
  errors on click. This makes the frontend **safe to merge before the backend
  is deployed.**
- **Env vars (companion build):** `VITE_DISCORD_AUTH_START_FN_URL`,
  `VITE_DISCORD_UNLINK_FN_URL`. These are the *only* Discord values in the
  bundle — client id/secret and bot token stay server-side.

### Backend (`dmhubclient/cloud-functions/functions`)

New self-contained ESM module **`functions/discord.js`**, sitting beside
`patreon.js` / `shopify.js`. Re-exported from `functions/index.js`:

```js
export { discordAuthStart, discordAuthCallback, discordUnlinkWeb } from "./discord.js";
```

It re-uses the same small helper shapes as `patreon.js` (its own copies, to keep
the module self-contained per the existing convention): `splitList`, `setCors`,
`bad`, `b64url`, `signState` / `verifyState` (HMAC-SHA256 over
`{uid, origin, iat, n}`, 10-min max age), `pickRedirectOrigin`, `uidFromBody`
(verifies the Firebase ID token → uid).

**Secrets** (`firebase functions:secrets:set <NAME>`):
- `DISCORD_CLIENT_ID`
- `DISCORD_CLIENT_SECRET`
- `DISCORD_STATE_SECRET`
- `DISCORD_BOT_TOKEN`

**Params** (`firebase functions:params:set <NAME>="…"`):
- `DISCORD_CALLBACK_URL` — the registered OAuth redirect URI (this Function).
- `DISCORD_APP_ORIGIN` — default post-auth redirect origin.
- `DISCORD_ALLOWED_ORIGINS` — comma list for `pickRedirectOrigin`.
- `DISCORD_GUILD_ID` — the Draw Steel server id.
- `DISCORD_LINKED_ROLE_ID` — the "linked" role id.

**Functions:**

- **`discordAuthStart`** (`onRequest`, POST, CORS) — `uidFromBody` → build the
  Discord authorize URL and return `{ ok, authorizeUrl }`:
  - `https://discord.com/oauth2/authorize?response_type=code`
    `&client_id=…&redirect_uri=…&scope=identify%20guilds.join`
    `&state=signState(uid, origin, DISCORD_STATE_SECRET)`.

- **`discordAuthCallback`** (`onRequest`, GET — Discord's redirect target).
  `back(status)` = `res.redirect(302, ${appOrigin}/more/account?discord=${status})`.
  1. `verifyState` → uid (bad state → `back('error')`, write nothing).
  2. `exchangeCode` at `https://discord.com/api/oauth2/token` (form body:
     `grant_type=authorization_code`, `code`, `redirect_uri`, `client_id`,
     `client_secret`) → `{ access_token, … }`.
  3. `fetchDiscordUser(access_token)` → `GET https://discord.com/api/users/@me`
     with `Authorization: Bearer …` → `{ id, username, global_name, avatar }`.
  4. **Add to guild:** `PUT https://discord.com/api/guilds/{guild}/members/{userId}`
     with `Authorization: Bot {DISCORD_BOT_TOKEN}` and JSON `{ access_token }`.
     201 = added, 204 = already a member; both are success.
  5. **Grant role:** `PUT …/guilds/{guild}/members/{userId}/roles/{roleId}` with
     bot auth (204; idempotent).
  6. Write the link, then `back('linked')`:
     ```
     /discordLinks/{uid} = {
       discordUserId, username, globalName, avatar, // avatar hash or null
       linkedAt: ServerValue.TIMESTAMP, updatedAt: ServerValue.TIMESTAMP
     }
     ```
  - **Atomicity:** the link is written **only after the role grant succeeds.**
    Any step failing → log + `back('error')`, write nothing. Steps 4–5 are PUTs
    (idempotent), so a retried link is safe.

- **`discordUnlinkWeb`** (`onRequest`, POST, CORS) — `uidFromBody` → read
  `/discordLinks/{uid}` for the `discordUserId`, `DELETE …/members/{userId}/roles/{roleId}`
  with bot auth (leaves them in the server — just drops the role), then
  `update({ '/discordLinks/{uid}': null })`. Modeled on `patreonUnlinkWeb`.

**Discord prerequisites (operator, outside code):**
- A bot application exists (confirmed). Its token → `DISCORD_BOT_TOKEN`.
- The bot is a member of the guild with the **Manage Roles** permission, and the
  "linked" role is positioned **below** the bot's highest role (Discord won't let
  a bot assign a role above its own).
- The OAuth app's redirect list includes `DISCORD_CALLBACK_URL`.
- Adding members via `guilds.join` needs no gateway connection or privileged
  intent — all calls are plain REST.

## Data model

`/discordLinks/{uid}` — `{ discordUserId, username, globalName, avatar, linkedAt, updatedAt }`.
No tokens. Same record family as `/patreonLinks/{uid}` and `/shopLinks/{uid}`.

**No `/discordBindings` reverse index in v1** (deliberate YAGNI — nothing consumes
it without a webhook/reconcile job). Consequence: two different Codex accounts
could each link the same Discord account and each toggle the flat "linked" role;
disconnecting one removes the role even if the other is still linked. Accepted
for a cosmetic v1 role; revisit (add the binding + a one-Discord-one-uid guard)
when tier sync arrives.

## Security rules

Add to the RTDB rules (same shape as `patreonLinks`): `/discordLinks/{uid}`
readable only by the owning uid (`auth.uid === $uid`), not client-writable —
only the Admin SDK (Functions) writes it.

## Codex-safety

The Account page is already a shared surface (it hosts the Patreon + Shopify
sections), and a player linking Discord is fine, so this is **Codex-safe** — no
`App.jsx` route-allowlist change. The section is gated on `status === 'codex-user'`
like its siblings.

## Error handling

| Failure | Behavior |
| --- | --- |
| Start/unlink Function error or network | Surfaced in the section's error line via the shared `run()` helper. |
| User denies consent / bad `state` | Callback `back('error')`; section shows "Discord connection failed."; nothing written. |
| Guild-join 403 (e.g. user banned) or role-grant failure | Logged; `back('error')`; nothing written. |
| Retried link | Idempotent (PUTs) — safe. |
| Function URLs unset (pre-deploy) | `discordConfigured` false → buttons hidden, read-only status only. |

## Testing

- **Backend (`discord.test.js`, TDD — mirrors `patreon.test.js` / `shopify-*.test.js`):**
  `signState`/`verifyState` round-trip + tamper/expiry rejection; `fetchDiscordUser`
  parse; add-guild-member treats 201 and 204 as success; role grant idempotency;
  callback writes nothing on a failed step; unlink builds the correct null-update.
  All pure helpers take an injected `fetchImpl` (as Patreon does) so no network.
- **Frontend:** unit tests for `useDiscordLink` (not-linked / linked / loading)
  and `ConnectDiscordSection` (the four states + connect/disconnect busy states),
  mirroring the Shopify link tests.
- **Playwright (per repo convention):** from the Account page as a codex-user,
  click **Connect Discord** → asserts navigation to `discord.com/oauth2/authorize`
  with the expected `client_id` and `scope=identify guilds.join`; after a stubbed
  `?discord=linked` return, the section shows **Connected** with the handle.

## Build / deploy sequence

1. Backend: implement `discord.js` + tests in `dmhubclient/cloud-functions`,
   export from `index.js`, set the secrets + params, deploy. **Deploy gotcha:**
   `firebase deploy --only functions:a,b` silently deploys only the first target
   — repeat the `functions:` prefix per function or deploy individually, and
   verify each in the UpdateFunction audit log.
2. Discord side: confirm bot Manage-Roles + role position, register the callback
   redirect URI, create/identify the "linked" role.
3. Frontend: build `discord.js` + `useDiscordLink` + `ConnectDiscordSection`,
   wire into `AccountPage`, add the two `VITE_DISCORD_*_FN_URL` env vars to the
   DO (and Cloudflare, if Codex should see it) builds. Merge to `main`.
4. Verify live (Playwright walkthrough + a real link round-trip).
