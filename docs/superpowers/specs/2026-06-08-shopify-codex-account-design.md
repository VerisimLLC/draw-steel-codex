# Shopify in Codex Settings > Account - Design (SP-A + SP-B)

**Date:** 2026-06-08
**Status:** Approved in brainstorm - ready for implementation plan
**Scope:** Connect / disconnect / status only. Purchases list (SP-C) DEFERRED.
**Repos touched:** `dmhubclient/cloud-functions` (Node), `draw-steel-codex` (Lua). Companion untouched.

Mirrors the Patreon codex work (specs `2026-06-07-patreon-*`). The companion's Shopify section
(`draw-steel-companion/src/shop/ConnectShopifySection.jsx`, `src/auth/shopify.js`) is the reference.

## 1. Goal

Add a "Shopify" section to the codex desktop Settings > Account that shows the user's Shopify link
status, lets them connect (via the browser/companion) and disconnect (in-app), mirroring the
companion. Gated behind the `dev:storepreview` shop testing flag.

## 2. Why this needs a status function (not an engine field)

The codex desktop has NO existing signal for Shopify link state (unlike Patreon, which had the
hardcoded `dmhub.patronTier`). Lua cannot read an arbitrary RTDB node (`/shopLinks/{uid}`) directly -
the only account-level cloud-read paths from Lua are specific engine fields and `net.Post` to a
Cloud Function. So the codex reads status by calling a new `shopifyStatus` function over `net.Post`.

This establishes the reusable "codex reads integration status via net.Post" pattern that also
un-parks Patreon's codex status (a future `patreonStatus` + the same Lua fetch).

## 3. Architecture

- **Connect** = browser. `dmhub.OpenURL("https://draw-steel-codex.com/more/account")` - the companion
  hosts the Shopify OAuth (`shopifyAuthStart/Callback`, unchanged).
- **Status / Disconnect** = `net.Post` to dual-auth Cloud Functions. `net.Post` auto-injects the
  desktop user's `{userid, secretid}`; the functions also still accept a browser `idToken` (companion).
- **Codex UI** fetches status on panel open + after connect/disconnect (async; cannot use the 0.1s
  `think` loop), caches it in panel state, and renders connected/not-connected.

Two cloud-function auth schemes already coexist in this codebase: browser `idToken`
(`uidFromBody` -> `verifyIdToken`) and desktop `{userid, secretid}` (validated against
`/users/{userid}/secretid`, the `redeem`/`steamPurchase` pattern). SP-A unifies them behind one
resolver so a single set of functions serves both surfaces.

## 4. SP-A - Backend: dual-auth Shopify functions (`cloud-functions/functions/shopify.js`)

### 4a. Shared `resolveUid(req, res)`
Replaces the idToken-only `uidFromBody` at the call sites that must serve the desktop too:
- If `req.body.idToken` is a non-empty string -> `getAuth().verifyIdToken(idToken)`, validate uid
  against `FIREBASE_UID_RE`, return uid. (Existing browser behavior.)
- Else if `req.body.userid` AND `req.body.secretid` -> read `/users/{userid}/secretid` via Admin SDK;
  if it matches and `userid` passes `FIREBASE_UID_RE`, return uid. (Desktop `net.Post` behavior.)
- Else -> respond 400/401 and return null. Keep `uidFromBody` as a thin wrapper (or inline) so
  `shopifyAuthStart` - which stays browser-only - is unaffected.

### 4b. `shopifyStatus` (NEW)
`POST` -> `{ ok: true, linked: boolean, email: string|null }`.
- `uid = resolveUid(req, res)`; if null, return.
- Read `/shopLinks/{uid}` via Admin SDK; `linked = snapshot has a non-empty customerId`,
  `email = snapshot.email || null` (reuse `normalizeShopLink` logic / the `CUSTOMER_GID_RE` check).
- CORS + OPTIONS + non-POST guards like the other functions (harmless for desktop callers).

### 4c. `shopifyUnlink` (refactor to dual-auth)
Change its `uidFromBody` call to `resolveUid`. Everything else (clear `/shopLinks/{uid}` +
`/shopCustomerLinks/{numericId}`, the best-effort `annotateShopifyCustomer('disconnect')`,
`{ ok: true }`) stays identical. Browser callers (companion) are unaffected.

### 4d. Out of scope for SP-A
`shopifyOrders` stays idToken-only for now; its dual-auth move belongs to SP-C (purchases).
`shopifyAuthStart` / `shopifyAuthCallback` unchanged.

### 4e. Wiring / tests / deploy
- Export `shopifyStatus` from `index.js` (alongside the other shopify exports).
- Tests (`node --test`): `resolveUid` (idToken path, secretid path, missing-both path) with injected
  auth/db; the existing shopify tests must still pass (shopifyUnlink behavior unchanged for idToken).
- Deploy: `shopifyStatus` (new) + `shopifyUnlink` (redeploy). Same `mcdm-385cf` / `us-central1`;
  URLs `https://us-central1-mcdm-385cf.cloudfunctions.net/shopifyStatus` etc.

## 5. SP-B - Codex: Shopify section (`DMHub Titlescreen/SettingsScreen.lua`)

A new section inside `SettingGroup{ group = "Account" }`, gated by the existing
`g_devStorePreviewSetting` (`dev:storepreview`), modeled on the Patreon section + the Disconnect
inline-confirm from SP4.

State (async, not the `think` loop):
- On panel `create`: set a "Checking Shopify..." label, then `net.Post{ url =
  dmhub.cloudFunctionsBaseUrl .. "/shopifyStatus", data = {}, success = ..., error = ... }`.
  Store `linked` / `email` in a forward-declared panel + locals; render from the response.
- **Linked**: "Shopify: Connected as \<email\>" (email omitted if nil) + a **Disconnect** button with
  the SP4 inline two-step confirm (Cancel + Confirm Disconnect -> `net.Post(/shopifyUnlink)`); on
  success, optimistically switch to not-linked (and/or re-fetch status); on error show an inline error.
- **Not linked**: a **Connect Shopify** button -> `dmhub.OpenURL("https://draw-steel-codex.com/more/account")`,
  plus a small **Refresh** affordance (re-runs `shopifyStatus`) since connect completes in the browser
  and the user returns to the desktop. (Status also re-fetches whenever Settings is reopened, since
  `create` fires again.)
- **Loading / error**: "Checking Shopify..." while in flight; an inline error + Refresh on failure.

Constraints (same as Patreon codex work): ASCII only; edit `SettingsScreen.lua` only (no new Lua
files); forward-declare self-referencing locals; match the file's tab indentation; gate the whole
section with `classes = { cond(not g_devStorePreviewSetting:Get(), "collapsed") }`.

## 6. Companion
No change. The dual-auth functions still accept the companion's idToken calls; the existing Shopify
section keeps working unchanged.

## 7. Build sequence
SP-A (backend - the contract) first, deploy + smoke-test, then SP-B (codex UI). Each review-gated.
SP-C (purchases list: `shopifyOrders` dual-auth + a Lua order list) is a separate later pass.

## 8. Security
- Entitlement/link reads + writes stay Admin-SDK (clients never self-grant).
- `resolveUid` derives uid from verified auth (idToken or secretid match) - never trusts a raw uid.
- No secrets in the client; the codex only opens a URL and calls functions with engine-injected auth.

## 9. Known considerations
- The codex status is fetch-on-open (async), not live - acceptable; a Refresh affordance covers the
  return-from-browser case. (Patreon's section used a live `think` read of an engine field; Shopify
  has no such field, hence the fetch model.)
- `dev:storepreview` gates the whole section, so it stays dark in production until shop testing is on.
- Companion's Shopify orders/link remain the richer surface until SP-C brings purchases to the codex.

## 10. Out of scope
SP-C (purchases list in the codex); any engine/C# change; any companion change.
