# Patreon Account Linking System - Cross-Repo Design

**Date:** 2026-06-07
**Status:** Approved in brainstorm - ready for implementation plans (build SP2 first)
**Scope:** DMHub Patreon campaign only (MCDM campaign deferred - still partnership-blocked)
**Repos touched:** `draw-steel-codex` (Lua), `dmhubclient/cloud-functions` (Node/Firebase Functions), `draw-steel-companion` (React)

Supersedes the codex-only spec `2026-06-07-patreon-account-settings-design.md` by extending it into the full link/unlink lifecycle. Builds on the paused notes `dmhubclient/docs/superpowers/specs/2026-06-01-patreon-account-linking-notes.md`.

---

## 1. Goal

Let a user link their Patreon account so that their DMHub-campaign membership tier grants in-app patron status (`dmhub.patronTier`), keep that tier correct as the membership changes (upgrade / downgrade / lapse), and let the user unlink. The desktop codex app only ever *reflects* the tier; all OAuth and entitlement writes happen server-side.

## 2. Why DMHub-only is unblocked

The 2026-06-01 blocker was reliable tier data for a campaign we do NOT own (MCDM). We own the DMHub campaign, so:
- The Patreon `identity` scope returns the user's entitled tier **for our own campaign** at link time (confirmed: "If you request memberships and DON'T have the `identity.memberships` scope, you receive data about the user's membership to *your* campaign"). No partnership needed.
- The owned-campaign `/campaigns/{id}/members` endpoint (creator token, `campaigns.members` scope) is the authoritative reconcile source.

MCDM-campaign display stays deferred.

## 3. Architecture

Three planes, split by who can do what:

- **Browser (companion)** owns the OAuth round-trip - it has an authenticated session and can host redirects. Calls `patreonAuthStart`, navigates the user to Patreon, returns to a callback.
- **Backend (Cloud Functions)** owns secrets + all entitlement writes (Admin SDK; `/Patrons/{uid}` is admin-write-only). Owns the OAuth code exchange, identity read, webhook ingest, and daily reconcile.
- **Desktop (codex)** only reads `dmhub.patronTier` (engine-synced from `/Patrons/{uid}`) and can trigger an unlink via `net.Post` (auth auto-injected). It never holds tokens or writes entitlement.

Two cloud-function auth schemes already exist in this codebase, split by caller - the spec uses each in its correct place:
- **Browser-called** functions verify a Firebase **idToken** in the POST body (`uidFromBody` -> `verifyIdToken`), pattern from `shopify.js`.
- **Desktop-called** functions trust `net.Post`'s auto-injected `{ userid, secretid }` and validate via `verifySecretId(userid, secretid)` (`cloud-functions/functions/index.js:182`), pattern from `redeem` / `steamPurchase*`.

## 4. Data schema (Firebase RTDB)

Mirrors existing Steam/Shopify shapes. All paths are Admin-SDK-write-only.

| Path | Value | Purpose |
|---|---|---|
| `/patreonLinks/{uid}` | `{ patreonUserId, tier, campaignId, patronStatus, accessToken, refreshToken, tokenExpiresAt, linkedAt, updatedAt }` | Forward link, keyed by uid (like `/shopLinks/{uid}`). Stores the user's rotating OAuth tokens for refresh, and the last-known tier/status. |
| `/patreonBindings/{patreonUserId}` | `uid` (string) | Reverse index (like `/steamBindings/{steamid}`). Lets webhooks + reconcile resolve a Patreon user id -> our uid. |
| `/Patrons/{uid}/tier` | number | The authoritative tier the engine + companion already read as `dmhub.patronTier`. Exists today. Written by connect / webhook / reconcile; cleared by unlink. |

Token storage note: OAuth tokens live under `/patreonLinks/{uid}` which is admin-write-only and not client-readable in a way the desktop uses (the desktop reads only `dmhub.patronTier`). Never expose tokens to any client. (Optionally store tokens under a separate `/patreonTokens/{uid}` node to keep them off any path a client might read - decide during SP2 implementation; default is inside `/patreonLinks/{uid}` since that node is already admin-only.)

## 5. Tier mapping

`currently_entitled_tiers` returns Patreon **tier ids** (durable strings). Maintain a static map `PATREON_TIER_TO_LEVEL = { <patreonTierId>: <integerLevel> }` in the backend, where integer levels are the existing companion map (`draw-steel-companion/src/account/patronTier.js`): 1=Whelp, 2=Goblin, 3=Hobgoblin, 4=Bugbear. At link/webhook/reconcile time, take the **highest** mapped level among the member's entitled tiers; empty entitled-tiers or `patron_status != "active_patron"` -> level 0 (not a patron).

**Required input from the campaign owner:** the actual DMHub-campaign tier ids and which integer level each maps to (see Section 11).

## 6. SP2 - Backend (build first): `cloud-functions/functions/patreon.js`

New module `patreon.js` (mirrors `shopify.js`), exported from `index.js`. All Patreon API facts below are verified against docs.patreon.com (2026-06).

### Secrets (`defineSecret`, like `SHOPIFY_*`)
`PATREON_CLIENT_ID`, `PATREON_CLIENT_SECRET`, `PATREON_CREATOR_ACCESS_TOKEN`, `PATREON_CREATOR_REFRESH_TOKEN`, `PATREON_WEBHOOK_SECRET`, `PATREON_STATE_SECRET` (HMAC key for signing OAuth `state`, like `SHOPIFY_STATE_SECRET`).
**Migration:** move these out of the companion `.env` `VITE_PATREON_*` vars (VITE_ vars are bundled into the browser - a client_secret there is a latent leak) into Functions secrets. The companion never needs the secret.

### 6a. `patreonAuthStart` (browser-called)
`POST { idToken } -> { ok, authorizeUrl }`. Mirrors `shopifyAuthStart`.
- `uid = uidFromBody(req)` (verify idToken).
- Build `https://www.patreon.com/oauth2/authorize?response_type=code&client_id=...&redirect_uri=<patreonAuthCallback URL>&scope=identity%20identity[email]&state=<signState(uid, origin, PATREON_STATE_SECRET)>`.
- Return `{ ok: true, authorizeUrl }`.

### 6b. `patreonAuthCallback` (Patreon redirects here: `GET ?code&state`)
Mirrors `shopifyAuthCallback`.
- `verifyState(state)` -> `uid` (+ origin for the return redirect). Reject on bad state.
- Exchange code: `POST https://www.patreon.com/api/oauth2/token` (form-urlencoded) `grant_type=authorization_code, code, client_id, client_secret, redirect_uri` -> `{ access_token, refresh_token, expires_in }`.
- Read identity with the **user** token: `GET https://www.patreon.com/api/oauth2/v2/identity?include=memberships,memberships.currently_entitled_tiers,memberships.campaign&fields[user]=email,full_name&fields[member]=patron_status&fields[tier]=title`.
- Find the membership whose `campaign.id == <our campaignId>`; compute level from its `currently_entitled_tiers` via `PATREON_TIER_TO_LEVEL` (highest); `patronUserId = data.id`.
- Admin-SDK multi-path update:
  - `/patreonLinks/{uid} = { patreonUserId, tier: level, campaignId, patronStatus, accessToken, refreshToken, tokenExpiresAt: now+expires_in, linkedAt, updatedAt }`
  - `/patreonBindings/{patronUserId} = uid`
  - `/Patrons/{uid}/tier = level`
- 302 back to the companion account page (`?patreon=linked` / `?patreon=error`).

### 6c. `patreonUnlink` (desktop-called)
`POST {} ` with `net.Post` auto-injecting `{ userid, secretid }` -> `{ ok }`. Auth via `verifySecretId(userid, secretid)`.
- Read `/patreonLinks/{userid}` to get `patreonUserId`.
- Admin-SDK multi-path update, all cleared: `/patreonLinks/{userid}=null`, `/patreonBindings/{patreonUserId}=null` (if known), `/Patrons/{userid}/tier=null`. (DMHub campaign only; never touch `subscription`/`inventory`.)
- Return `{ ok: true }`. (Patreon has no documented token-revocation endpoint; clearing our stored tokens is the unlink. Webhooks are campaign-scoped, left registered.)

Also expose a browser-callable unlink path (same logic, idToken auth) so the companion's Disconnect button works too - factor the core into a shared `doPatreonUnlink(uid)` and wrap it with both auth front-ends.

### 6d. `patreonWebhook` (Patreon-called)
`POST` raw JSON:API body; header `X-Patreon-Event` in `{members:create, members:update, members:delete, members:pledge:*}`.
- **Signature:** compute HMAC-**MD5** of the **raw request body bytes** keyed by `PATREON_WEBHOOK_SECRET`; constant-time compare lowercase hex digest to header `X-Patreon-Signature`. Reject mismatch. (Must read the raw body before parsing - configure the function for the rawBody.)
- Parse the `member` resource: `user.id` (patron id), `currently_entitled_tiers`, `patron_status`.
- Resolve `uid = /patreonBindings/{patronUserId}`. If no binding, ignore (not a linked user).
- Compute level (highest entitled, 0 if not active); write `/patreonLinks/{uid}/tier`, `/patreonLinks/{uid}/patronStatus`, `/patreonLinks/{uid}/updatedAt`, and `/Patrons/{uid}/tier = level`. On `members:delete` -> level 0.
- Return 200 quickly (Patreon retries on non-2xx).
- Register the webhook once via `POST /api/oauth2/v2/webhooks` (creator token, `w:campaigns.webhook`, triggers list, our campaign id). This registration is a one-time setup step (document it; optionally a tiny admin script or a guarded onRequest), not part of the request path.

### 6e. `patreonReconcile` (scheduled daily)
`onSchedule` (daily). Authoritative correction + token refresh.
- Refresh the **creator** token if near expiry: `POST .../oauth2/token grant_type=refresh_token` -> persist the NEW `access_token` + rotated `refresh_token` (refresh tokens rotate; reusing the old one fails).
- Page through `GET /api/oauth2/v2/campaigns/{campaignId}/members?include=currently_entitled_tiers,user&fields[member]=patron_status&fields[tier]=title` (cursor pagination, up to 1000/page; honor rate limits + `retry_after_seconds`).
- For each member with a `/patreonBindings/{user.id}` -> uid: recompute level and overwrite `/patreonLinks/{uid}/tier` + `/Patrons/{uid}/tier`.
- For any `/patreonLinks/{uid}` whose patron no longer appears active in the member list -> set level 0 (catches missed lapse webhooks). This is the safety net that guarantees access drops.
- Also refresh each linked user's stored user-token if you rely on per-user identity reads elsewhere (optional; reconcile via creator/members endpoint avoids needing user tokens).

## 7. SP3 - Companion UI (`draw-steel-companion`)

Mirror `src/shop/ConnectShopifySection.jsx` + `src/auth/shopify.js`:
- New `src/auth/patreon.js`: `startPatreonLink()` (POST idToken to `patreonAuthStart`, `window.location.assign(authorizeUrl)`) and `unlinkPatreon()` (POST idToken to the browser unlink endpoint).
- Replace/extend the existing read-only `PatreonSection` in `src/pages/AccountPage.jsx`: when `status === 'codex-user'` and not linked, show **Connect Patreon**; when linked, show tier (reuse `tierLabel` from `src/account/patronTier.js`) + **Disconnect**. Keep the existing `usePatronTier` live read of `/Patrons/{uid}/tier`.
- Handle the `?patreon=linked|error` query param on return (toast/inline message), like Shopify's `?shopify=` handling.

## 8. SP4 - Codex Disconnect button (`draw-steel-codex`)

In `DMHub Titlescreen/SettingsScreen.lua`, in the patron-state branch (`patronTier > 0`) of the section built in SP1, add a **Disconnect** `gui.Button`:
- On click: show a confirm prompt ("Disconnect your Patreon account? You'll lose patron benefits until you reconnect.") - use the codebase's existing confirm-dialog pattern.
- On confirm: `net.Post{ url = dmhub.cloudFunctionsBaseUrl .. "/patreonUnlink", data = {}, success = ..., error = ... }`. Disable the button while in flight; show an inline error on failure.
- On success: the existing `/Patrons/{uid}` monitor drops `dmhub.patronTier` to 0 and the existing `think` handler flips the section to the non-patron state automatically. No manual UI swap needed.
- Constraints unchanged from SP1: edit existing file only (no new Lua files), ASCII-only, forward-declare self-referencing locals.

## 9. Build sequence

SP1 (done) -> **SP2 (backend)** -> SP3 (companion) + SP4 (codex), which can proceed in parallel once SP2's contract is fixed. Each SP is independently shippable. SP4 against the agreed `patreonUnlink` contract is forward-compatible even before SP2 deploys (button is non-functional until the endpoint exists, like SP1's Connect button).

## 10. Security considerations

- client_secret + creator + webhook secrets live ONLY in Functions secrets, never in any client/bundle. Remove the `VITE_PATREON_*` secret vars from the companion.
- Entitlement writes (`/Patrons/{uid}/tier`, bindings) are Admin-SDK only; clients can never self-grant.
- `patreonUnlink` derives uid from verified auth (idToken or secretid) - never trusts a client-supplied uid.
- Webhook handler verifies HMAC-MD5 over the raw body before acting; rejects unsigned/mismatched.
- OAuth `state` is HMAC-signed (CSRF + uid binding), validated in the callback.
- Refresh-token rotation handled (persist the new token each refresh).

## 11. Required inputs from the campaign owner (before deploy/test)

1. DMHub Patreon **campaign id** and the **tier-id -> integer-level** map (Section 5).
2. The **redirect URI** for `patreonAuthCallback` registered on the DMHub Patreon OAuth client (Clients & API Keys page).
3. Confirmation of **secret migration** target (Functions secrets) and current creator access/refresh tokens.
4. **Existing-writer check:** confirm nothing else currently writes `/Patrons/{uid}/tier` (no writer found in `cloud-functions`; the main dmhubclient backend / admin process is unconfirmed). If one exists, coordinate so connect/reconcile don't fight it.
5. Sandbox/test patron access for end-to-end verification.

## 12. Known limitations

- **MCDM white-label hardcode:** `dmhub.patronTier` is hardcoded to 3 on MCDM builds (`LoginController.cs:47` per the 2026-06-01 notes). Until that engine seam is replaced with a real computation, clearing/setting the tier server-side will not change what those builds display. Engine C# work, out of scope here.
- **MCDM campaign membership** display is deferred (partnership-blocked).
- Patreon `/identity` occasionally omits memberships for active patrons; the daily reconcile (creator/members endpoint) is the authoritative correction, so worst case a tier is briefly stale, not wrong long-term.
- Refresh-token expiry duration is not documented; the daily reconcile keeps the creator token live. If reconcile is down for an extended period, tokens could lapse.

## 13. Open questions

- Token storage location: inside `/patreonLinks/{uid}` vs a dedicated `/patreonTokens/{uid}` (decide in SP2).
- Whether to also subscribe `members:pledge:*` webhooks or rely on `members:update` + reconcile (default: subscribe create/update/delete, lean on reconcile as safety net).
- Confirm the exact `X-Patreon-Event` header value at runtime (docs use `members:*` triggers; historically some `pledges:*` labels appeared) before hard-coding event matching.
