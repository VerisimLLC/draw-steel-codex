# Patreon SP2 - Backend Cloud Functions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Patreon account-link backend - OAuth connect, unlink, webhook ingest, and daily reconcile - as a self-contained `patreon.js` Cloud Functions module that writes the user's DMHub-campaign tier into `/Patrons/{uid}/tier`.

**Architecture:** Self-contained ESM module mirroring `shopify.js`. Browser-called functions verify a Firebase idToken; the desktop-called unlink trusts `net.Post`'s auto-injected `{userid, secretid}` validated via `verifySecretId`. All entitlement writes use the Admin SDK. Pure helpers (state signing, tier mapping, webhook signature, identity/members parsing) are unit-tested with `node --test`; network calls are tested with an injected `fetch`.

**Tech Stack:** Node 20 ESM, `firebase-functions` v2 (`onRequest`, `onSchedule`), `firebase-admin` (auth + RTDB), Node built-in `crypto` + `node:test`.

**Repo / working dir:** `C:\MCDM\dmhubclient\cloud-functions` (NOT the codex repo). Branch off `master` first: `git checkout -b patreon-backend master`.

**Spec:** `C:\MCDM\draw-steel-codex\docs\superpowers\specs\2026-06-07-patreon-account-linking-system-design.md` (Sections 4, 5, 6, 10, 11).

---

## Important context (read before starting)

- **Admin SDK is already initialized in `index.js`.** Do NOT call `initializeApp()` in `patreon.js`. Mirror `shopify.js`.
- **Module is self-contained**, like `shopify.js`. It re-declares the tiny pure helpers (`signState`/`verifyState`, `setCors`, `bad`) rather than importing them from `shopify.js` - do not refactor `shopify.js`. The ~15 lines of duplication is intentional and matches the existing one-module-per-integration pattern.
- **Test runner:** `npm test` runs `node --test` (executes every `*.test.js`). Run a single file with `node --test functions/patreon.test.js`.
- **Test style:** `import { test } from 'node:test'`, `import assert from 'node:assert/strict'`. Network helpers take a `fetchImpl` parameter so tests inject a fake (mirror `shopify-admin.test.js` / `shopify-orders.test.js`'s `fakeFetch`).
- **Verified Patreon API facts (docs.patreon.com, 2026-06):** authorize `https://www.patreon.com/oauth2/authorize`; token `https://www.patreon.com/api/oauth2/token` (form-urlencoded); identity `https://www.patreon.com/api/oauth2/v2/identity`; members `https://www.patreon.com/api/oauth2/v2/campaigns/{id}/members`; webhook signature = HMAC-**MD5** hex of the **raw body** keyed by the webhook secret, header `X-Patreon-Signature`, event in `X-Patreon-Event`; access tokens ~31d; **refresh tokens rotate (persist the new one each refresh)**; for our OWN campaign the `identity` scope returns the tier.
- **RTDB schema (spec Section 4):** `/patreonLinks/{uid}`, `/patreonBindings/{patreonUserId} = uid`, `/Patrons/{uid}/tier` (number). Plus `/patreonCreatorToken = { accessToken, refreshToken, expiresAt }` for the rotating creator token (seeded from a secret, refreshed by reconcile).
- **ASCII / style:** match `shopify.js` (2-space indent, single quotes, no semicolons).

## File structure

| File | Responsibility | Change |
|---|---|---|
| `functions/patreon.js` | All Patreon functions + helpers | Create |
| `functions/patreon.test.js` | Unit tests for pure helpers + parsers | Create |
| `functions/index.js` | Re-export the new functions | Modify (add one export line) |
| `functions/register-patreon-webhook.js` | One-time webhook registration script | Create |

Config (secrets/params) is set via the Firebase CLI, documented in Task 11 - not code.

---

## Task 1: Module scaffold + config + index.js wiring

**Files:**
- Create: `functions/patreon.js`
- Modify: `functions/index.js`

- [ ] **Step 1: Create `functions/patreon.js` with imports, config, and shared helpers**

```javascript
// Patreon account-link Functions - link a Codex user to their DMHub-campaign
// Patreon membership and reflect the tier in /Patrons/{uid}/tier.
//
// Self-contained ESM module (mirrors shopify.js). Admin SDK is initialized in
// index.js - do NOT call initializeApp() here. Re-exported from index.js.
//
// Spec: draw-steel-codex/docs/superpowers/specs/2026-06-07-patreon-account-linking-system-design.md
// Firebase project: mcdm-385cf
import { onRequest } from 'firebase-functions/v2/https'
import { onSchedule } from 'firebase-functions/v2/scheduler'
import { defineString, defineSecret } from 'firebase-functions/params'
import * as logger from 'firebase-functions/logger'
import { getAuth } from 'firebase-admin/auth'
import { getDatabase, ServerValue } from 'firebase-admin/database'
import { createHmac, randomBytes, timingSafeEqual } from 'crypto'

// --- Secrets (firebase functions:secrets:set <NAME>) ---
const PATREON_CLIENT_ID = defineSecret('PATREON_CLIENT_ID')
const PATREON_CLIENT_SECRET = defineSecret('PATREON_CLIENT_SECRET')
const PATREON_STATE_SECRET = defineSecret('PATREON_STATE_SECRET')
const PATREON_WEBHOOK_SECRET = defineSecret('PATREON_WEBHOOK_SECRET')
// Seed for the rotating creator token; after first reconcile the live token
// lives in RTDB /patreonCreatorToken.
const PATREON_CREATOR_REFRESH_TOKEN = defineSecret('PATREON_CREATOR_REFRESH_TOKEN')

// --- Params (firebase functions:params:set <NAME>="...") ---
const PATREON_CALLBACK_URL = defineString('PATREON_CALLBACK_URL', { default: '' })
const PATREON_APP_ORIGIN = defineString('PATREON_APP_ORIGIN', { default: '' })
const PATREON_ALLOWED_ORIGINS = defineString('PATREON_ALLOWED_ORIGINS', { default: '' })
const PATREON_CAMPAIGN_ID = defineString('PATREON_CAMPAIGN_ID', { default: '' })
// JSON string mapping Patreon tier id -> our integer level, e.g. {"123":1,"456":2}.
const PATREON_TIER_MAP_JSON = defineString('PATREON_TIER_MAP', { default: '{}' })

// --- Constants ---
const AUTHORIZE_URL = 'https://www.patreon.com/oauth2/authorize'
const TOKEN_URL = 'https://www.patreon.com/api/oauth2/token'
const IDENTITY_URL = 'https://www.patreon.com/api/oauth2/v2/identity'
const API_BASE = 'https://www.patreon.com/api/oauth2/v2'
const SCOPE = 'identity identity[email]'
const STATE_MAX_AGE_MS = 10 * 60 * 1000
const FIREBASE_UID_RE = /^[A-Za-z0-9_-]{1,128}$/
const ALL_SECRETS = [PATREON_CLIENT_ID, PATREON_CLIENT_SECRET, PATREON_STATE_SECRET,
  PATREON_WEBHOOK_SECRET, PATREON_CREATOR_REFRESH_TOKEN]

// --- Small shared helpers ---
function splitList(v) {
  return (v || '').split(',').map((s) => s.trim()).filter(Boolean)
}

function setCors(res, origin) {
  const allowed = splitList(PATREON_ALLOWED_ORIGINS.value())
  if (origin && allowed.includes(origin)) {
    res.set('Access-Control-Allow-Origin', origin)
    res.set('Vary', 'Origin')
  }
  res.set('Access-Control-Allow-Headers', 'Content-Type')
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS')
}

function bad(res, msg, code = 400) {
  return res.status(code).json({ ok: false, error: msg })
}

function b64url(buf) {
  return Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function b64urlToBuf(s) {
  return Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64')
}
```

- [ ] **Step 2: Add the index.js re-export**

In `functions/index.js`, next to the shopify export line (`export { shopifyAuthStart, ... } from "./shopify.js";`), add:

```javascript
export { patreonAuthStart, patreonAuthCallback, patreonUnlink, patreonUnlinkWeb, patreonWebhook, patreonReconcile } from "./patreon.js";
```

- [ ] **Step 3: Verify the module imports cleanly**

Run: `node --input-type=module -e "await import('./functions/patreon.js'); console.log('OK')"` from the repo root.
Expected: `OK` (no export errors yet because the named exports in index.js don't exist - so instead verify patreon.js parses by importing it directly as above; defer the index.js line until Task 6+ OR add temporary stub exports). To avoid a broken index.js mid-plan, add stub exports at the end of patreon.js now:

```javascript
// Stubs replaced in later tasks (keep index.js importable between tasks).
export const patreonAuthStart = onRequest({ secrets: ALL_SECRETS }, (req, res) => res.status(501).end())
export const patreonAuthCallback = onRequest({ secrets: ALL_SECRETS }, (req, res) => res.status(501).end())
export const patreonUnlink = onRequest((req, res) => res.status(501).end())
export const patreonUnlinkWeb = onRequest((req, res) => res.status(501).end())
export const patreonWebhook = onRequest((req, res) => res.status(501).end())
export const patreonReconcile = onSchedule({ schedule: 'every 24 hours', secrets: ALL_SECRETS }, async () => {})
```

Run: `node --input-type=module -e "await import('./functions/index.js'); console.log('OK')"`
Expected: `OK`

- [ ] **Step 4: Commit**

```
git add functions/patreon.js functions/index.js
git commit -m "feat(patreon): scaffold patreon.js module + config + index export"
```

---

## Task 2: Tier mapping helper (TDD)

**Files:**
- Modify: `functions/patreon.js`
- Create: `functions/patreon.test.js`

- [ ] **Step 1: Write the failing test**

Create `functions/patreon.test.js`:

```javascript
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { levelFromEntitledTiers } from './patreon.js'

const MAP = { tierA: 1, tierB: 2, tierC: 3, tierD: 4 }

test('levelFromEntitledTiers: empty / missing -> 0', () => {
  assert.equal(levelFromEntitledTiers([], MAP), 0)
  assert.equal(levelFromEntitledTiers(undefined, MAP), 0)
})

test('levelFromEntitledTiers: single known tier -> its level', () => {
  assert.equal(levelFromEntitledTiers(['tierB'], MAP), 2)
})

test('levelFromEntitledTiers: multiple tiers -> highest level', () => {
  assert.equal(levelFromEntitledTiers(['tierA', 'tierD', 'tierB'], MAP), 4)
})

test('levelFromEntitledTiers: unknown tier ids are ignored', () => {
  assert.equal(levelFromEntitledTiers(['nope', 'tierA'], MAP), 1)
  assert.equal(levelFromEntitledTiers(['nope'], MAP), 0)
})
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `node --test functions/patreon.test.js`
Expected: FAIL (`levelFromEntitledTiers` is not exported).

- [ ] **Step 3: Implement the helper in `patreon.js`** (add after the small helpers)

```javascript
// Highest mapped level among the entitled tier ids; 0 if none map.
export function levelFromEntitledTiers(entitledTierIds, tierMap) {
  let level = 0
  for (const id of entitledTierIds || []) {
    const l = tierMap[id]
    if (typeof l === 'number' && l > level) level = l
  }
  return level
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `node --test functions/patreon.test.js`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```
git add functions/patreon.js functions/patreon.test.js
git commit -m "feat(patreon): levelFromEntitledTiers tier mapping (TDD)"
```

---

## Task 3: Webhook signature verification (TDD)

**Files:**
- Modify: `functions/patreon.js`, `functions/patreon.test.js`

- [ ] **Step 1: Write the failing test** (append to `patreon.test.js`)

```javascript
import { verifyPatreonSignature } from './patreon.js'
import { createHmac } from 'crypto'

const WH_SECRET = 'webhook-secret-xyz'
const RAW = Buffer.from('{"data":{"type":"member"}}', 'utf8')
const GOOD = createHmac('md5', WH_SECRET).update(RAW).digest('hex')

test('verifyPatreonSignature: correct HMAC-MD5 hex passes', () => {
  assert.equal(verifyPatreonSignature(RAW, GOOD, WH_SECRET), true)
})

test('verifyPatreonSignature: wrong signature fails', () => {
  assert.equal(verifyPatreonSignature(RAW, 'deadbeef', WH_SECRET), false)
})

test('verifyPatreonSignature: tampered body fails', () => {
  assert.equal(verifyPatreonSignature(Buffer.from('{}', 'utf8'), GOOD, WH_SECRET), false)
})

test('verifyPatreonSignature: missing signature or secret fails', () => {
  assert.equal(verifyPatreonSignature(RAW, '', WH_SECRET), false)
  assert.equal(verifyPatreonSignature(RAW, GOOD, ''), false)
})
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `node --test functions/patreon.test.js`
Expected: FAIL (`verifyPatreonSignature` not exported).

- [ ] **Step 3: Implement in `patreon.js`**

```javascript
// Patreon signs webhooks as the hex HMAC-MD5 of the RAW body, keyed by the
// webhook secret (header X-Patreon-Signature). Constant-time compare.
export function verifyPatreonSignature(rawBody, signatureHeader, secret) {
  if (!signatureHeader || !secret) return false
  const expected = createHmac('md5', secret).update(rawBody).digest('hex')
  const a = Buffer.from(expected, 'utf8')
  const b = Buffer.from(String(signatureHeader), 'utf8')
  if (a.length !== b.length) return false
  return timingSafeEqual(a, b)
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `node --test functions/patreon.test.js`
Expected: PASS (all tests so far).

- [ ] **Step 5: Commit**

```
git add functions/patreon.js functions/patreon.test.js
git commit -m "feat(patreon): verifyPatreonSignature HMAC-MD5 (TDD)"
```

---

## Task 4: Signed OAuth state (TDD)

**Files:**
- Modify: `functions/patreon.js`, `functions/patreon.test.js`

- [ ] **Step 1: Write the failing test** (append)

```javascript
import { signState, verifyState } from './patreon.js'

const ST = 'state-secret-123'

test('signState/verifyState: round-trips uid + origin', () => {
  const s = signState('user-1', 'https://codex.mcdm.com', ST)
  assert.deepEqual(verifyState(s, ST), { uid: 'user-1', origin: 'https://codex.mcdm.com' })
})

test('verifyState: bad signature / secret / uid / garbage -> null', () => {
  const s = signState('user-1', '', ST)
  assert.equal(verifyState(s.slice(0, -1) + (s.slice(-1) === 'a' ? 'b' : 'a'), ST), null)
  assert.equal(verifyState(s, 'other'), null)
  assert.equal(verifyState(signState('bad uid!', '', ST), ST), null)
  assert.equal(verifyState('garbage', ST), null)
  assert.equal(verifyState(null, ST), null)
})
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `node --test functions/patreon.test.js`
Expected: FAIL (`signState`/`verifyState` not exported).

- [ ] **Step 3: Implement in `patreon.js`** (mirrors shopify.js state, with our UID regex)

```javascript
// state = b64url(JSON{uid,origin,iat,n}) + "." + b64url(HMAC-SHA256(payload)).
// Secret passed in (not the param) so these stay pure + unit-testable.
export function signState(uid, origin, secret) {
  const payload = b64url(JSON.stringify({ uid, origin: origin || '', iat: Date.now(), n: b64url(randomBytes(12)) }))
  const sig = b64url(createHmac('sha256', secret).update(payload).digest())
  return `${payload}.${sig}`
}

export function verifyState(state, secret) {
  if (typeof state !== 'string' || !state.includes('.')) return null
  const [payload, sig] = state.split('.')
  if (!payload || !sig) return null
  const expected = b64url(createHmac('sha256', secret).update(payload).digest())
  const a = Buffer.from(sig), b = Buffer.from(expected)
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null
  let obj
  try { obj = JSON.parse(b64urlToBuf(payload).toString('utf8')) } catch { return null }
  if (!obj || !FIREBASE_UID_RE.test(obj.uid || '')) return null
  if (typeof obj.iat !== 'number' || Date.now() - obj.iat > STATE_MAX_AGE_MS) return null
  return { uid: obj.uid, origin: obj.origin || '' }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `node --test functions/patreon.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add functions/patreon.js functions/patreon.test.js
git commit -m "feat(patreon): signed OAuth state (TDD)"
```

---

## Task 5: Patreon API client + identity/members parsers (TDD)

**Files:**
- Modify: `functions/patreon.js`, `functions/patreon.test.js`

- [ ] **Step 1: Write the failing tests** (append) - parsers are pure; fetchers use injected fetch

```javascript
import { parseIdentityForCampaign, parseMembersPage, exchangeCode } from './patreon.js'

const TIER_MAP = { t1: 1, t2: 2 }
const CAMPAIGN = 'camp-9'

const IDENTITY = {
  data: { type: 'user', id: 'patron-7', attributes: { email: 'a@b.c' },
    relationships: { memberships: { data: [{ type: 'member', id: 'm1' }] } } },
  included: [
    { type: 'member', id: 'm1',
      attributes: { patron_status: 'active_patron' },
      relationships: {
        currently_entitled_tiers: { data: [{ type: 'tier', id: 't2' }] },
        campaign: { data: { type: 'campaign', id: 'camp-9' } },
      } },
  ],
}

test('parseIdentityForCampaign: extracts patron id, level, status for our campaign', () => {
  assert.deepEqual(parseIdentityForCampaign(IDENTITY, CAMPAIGN, TIER_MAP),
    { patronUserId: 'patron-7', level: 2, patronStatus: 'active_patron' })
})

test('parseIdentityForCampaign: membership in a different campaign -> level 0', () => {
  const other = JSON.parse(JSON.stringify(IDENTITY))
  other.included[0].relationships.campaign.data.id = 'someone-else'
  assert.deepEqual(parseIdentityForCampaign(other, CAMPAIGN, TIER_MAP),
    { patronUserId: 'patron-7', level: 0, patronStatus: null })
})

test('parseMembersPage: maps user id -> {patronUserId, level, patronStatus}, returns nextCursor', () => {
  const page = {
    data: [
      { type: 'member', id: 'm1', attributes: { patron_status: 'active_patron' },
        relationships: { currently_entitled_tiers: { data: [{ type: 'tier', id: 't1' }] },
          user: { data: { type: 'user', id: 'patron-1' } } } },
    ],
    meta: { pagination: { cursors: { next: 'CURSOR2' } } },
  }
  const { members, nextCursor } = parseMembersPage(page, TIER_MAP)
  assert.deepEqual(members, [{ patronUserId: 'patron-1', level: 1, patronStatus: 'active_patron' }])
  assert.equal(nextCursor, 'CURSOR2')
})

test('exchangeCode: posts form body and returns tokens (injected fetch)', async () => {
  let seenUrl, seenBody
  const fakeFetch = async (url, opts) => {
    seenUrl = url; seenBody = opts.body
    return { ok: true, json: async () => ({ access_token: 'AT', refresh_token: 'RT', expires_in: 2678400 }) }
  }
  const tok = await exchangeCode({ code: 'C', clientId: 'cid', clientSecret: 'sec', redirectUri: 'https://cb' }, fakeFetch)
  assert.equal(seenUrl, 'https://www.patreon.com/api/oauth2/token')
  assert.match(seenBody, /grant_type=authorization_code/)
  assert.match(seenBody, /code=C/)
  assert.deepEqual(tok, { access_token: 'AT', refresh_token: 'RT', expires_in: 2678400 })
})
```

- [ ] **Step 2: Run to confirm failure**

Run: `node --test functions/patreon.test.js`
Expected: FAIL (parsers/exchangeCode not exported).

- [ ] **Step 3: Implement in `patreon.js`**

```javascript
// --- Patreon API client (all take fetchImpl for testability; default global fetch) ---
function formBody(obj) {
  return Object.entries(obj).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&')
}

export async function exchangeCode({ code, clientId, clientSecret, redirectUri }, fetchImpl = fetch) {
  const res = await fetchImpl(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: formBody({ code, grant_type: 'authorization_code', client_id: clientId, client_secret: clientSecret, redirect_uri: redirectUri }),
  })
  if (!res.ok) throw new Error(`token exchange failed: ${res.status}`)
  return res.json()
}

export async function refreshToken({ refreshToken, clientId, clientSecret }, fetchImpl = fetch) {
  const res = await fetchImpl(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: formBody({ grant_type: 'refresh_token', refresh_token: refreshToken, client_id: clientId, client_secret: clientSecret }),
  })
  if (!res.ok) throw new Error(`token refresh failed: ${res.status}`)
  return res.json() // { access_token, refresh_token (rotated), expires_in }
}

export async function fetchIdentity(accessToken, fetchImpl = fetch) {
  const url = `${IDENTITY_URL}?include=memberships,memberships.currently_entitled_tiers,memberships.campaign`
    + `&fields%5Buser%5D=email,full_name&fields%5Bmember%5D=patron_status&fields%5Btier%5D=title`
  const res = await fetchImpl(url, { headers: { Authorization: `Bearer ${accessToken}` } })
  if (!res.ok) throw new Error(`identity fetch failed: ${res.status}`)
  return res.json()
}

export async function fetchMembersPage({ accessToken, campaignId, cursor }, fetchImpl = fetch) {
  let url = `${API_BASE}/campaigns/${encodeURIComponent(campaignId)}/members`
    + `?include=currently_entitled_tiers,user&fields%5Bmember%5D=patron_status&page%5Bcount%5D=1000`
  if (cursor) url += `&page%5Bcursor%5D=${encodeURIComponent(cursor)}`
  const res = await fetchImpl(url, { headers: { Authorization: `Bearer ${accessToken}` } })
  if (!res.ok) throw new Error(`members fetch failed: ${res.status}`)
  return res.json()
}

// --- Pure parsers ---
export function parseIdentityForCampaign(identity, campaignId, tierMap) {
  const patronUserId = identity?.data?.id || null
  const members = (identity?.included || []).filter((x) => x.type === 'member')
  let level = 0, patronStatus = null
  for (const m of members) {
    if (m.relationships?.campaign?.data?.id !== campaignId) continue
    patronStatus = m.attributes?.patron_status || null
    const ids = (m.relationships?.currently_entitled_tiers?.data || []).map((t) => t.id)
    level = levelFromEntitledTiers(ids, tierMap)
  }
  return { patronUserId, level, patronStatus }
}

export function parseMembersPage(page, tierMap) {
  const members = (page?.data || []).map((m) => ({
    patronUserId: m.relationships?.user?.data?.id || null,
    level: levelFromEntitledTiers((m.relationships?.currently_entitled_tiers?.data || []).map((t) => t.id), tierMap),
    patronStatus: m.attributes?.patron_status || null,
  })).filter((x) => x.patronUserId)
  const nextCursor = page?.meta?.pagination?.cursors?.next || null
  return { members, nextCursor }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `node --test functions/patreon.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add functions/patreon.js functions/patreon.test.js
git commit -m "feat(patreon): API client + identity/members parsers (TDD)"
```

---

## Task 6: `patreonAuthStart` (browser-called)

**Files:** Modify `functions/patreon.js`

- [ ] **Step 1: Add `uidFromBody` helper and replace the `patreonAuthStart` stub**

```javascript
async function uidFromBody(req, res) {
  const { idToken } = req.body || {}
  if (!idToken || typeof idToken !== 'string') { bad(res, 'Missing idToken', 400); return null }
  try {
    const decoded = await getAuth().verifyIdToken(idToken)
    if (!FIREBASE_UID_RE.test(decoded.uid || '')) { bad(res, 'invalid-id-token', 401); return null }
    return decoded.uid
  } catch (err) {
    logger.warn('patreon: verifyIdToken rejected', err?.message || err)
    bad(res, 'invalid-id-token', 401); return null
  }
}

export const patreonAuthStart = onRequest({ secrets: ALL_SECRETS }, async (req, res) => {
  const origin = req.get('Origin') || ''
  setCors(res, origin)
  if (req.method === 'OPTIONS') return res.status(204).send('')
  if (req.method !== 'POST') return bad(res, 'Method not allowed', 405)
  try {
    const uid = await uidFromBody(req, res)
    if (!uid) return
    const url = new URL(AUTHORIZE_URL)
    url.searchParams.set('response_type', 'code')
    url.searchParams.set('client_id', PATREON_CLIENT_ID.value())
    url.searchParams.set('redirect_uri', PATREON_CALLBACK_URL.value())
    url.searchParams.set('scope', SCOPE)
    url.searchParams.set('state', signState(uid, origin, PATREON_STATE_SECRET.value()))
    return res.status(200).json({ ok: true, authorizeUrl: url.toString() })
  } catch (err) {
    logger.error('patreonAuthStart error', err)
    return bad(res, 'Internal error', 500)
  }
})
```

- [ ] **Step 2: Verify the module still imports**

Run: `node --input-type=module -e "await import('./functions/index.js'); console.log('OK')"`
Expected: `OK`

- [ ] **Step 3: Run the full test file (no regressions)**

Run: `node --test functions/patreon.test.js`
Expected: PASS.

- [ ] **Step 4: Commit**

```
git add functions/patreon.js
git commit -m "feat(patreon): patreonAuthStart authorize-URL endpoint"
```

---

## Task 7: `patreonAuthCallback` (Patreon redirect)

**Files:** Modify `functions/patreon.js`

- [ ] **Step 1: Replace the `patreonAuthCallback` stub**

```javascript
function tierMap() {
  try { return JSON.parse(PATREON_TIER_MAP_JSON.value() || '{}') } catch { return {} }
}

export const patreonAuthCallback = onRequest({ secrets: ALL_SECRETS }, async (req, res) => {
  const appOrigin = PATREON_APP_ORIGIN.value()
  const back = (status) => res.redirect(302, `${appOrigin}/more/account?patreon=${status}`)
  try {
    if (req.method !== 'GET') return res.status(405).send('Method Not Allowed')
    const { code, state } = req.query
    if (typeof code !== 'string' || typeof state !== 'string') return back('error')
    const decoded = verifyState(state, PATREON_STATE_SECRET.value())
    if (!decoded) { logger.warn('patreonAuthCallback: bad state'); return back('error') }
    const uid = decoded.uid

    const tokens = await exchangeCode({
      code,
      clientId: PATREON_CLIENT_ID.value(),
      clientSecret: PATREON_CLIENT_SECRET.value(),
      redirectUri: PATREON_CALLBACK_URL.value(),
    })
    const identity = await fetchIdentity(tokens.access_token)
    const { patronUserId, level, patronStatus } = parseIdentityForCampaign(identity, PATREON_CAMPAIGN_ID.value(), tierMap())
    if (!patronUserId) { logger.error('patreonAuthCallback: no patron id in identity'); return back('error') }

    const rtdb = getDatabase()
    const updates = {
      [`patreonLinks/${uid}`]: {
        patreonUserId,
        tier: level,
        campaignId: PATREON_CAMPAIGN_ID.value(),
        patronStatus,
        accessToken: tokens.access_token,
        refreshToken: tokens.refresh_token,
        tokenExpiresAt: Date.now() + (tokens.expires_in || 0) * 1000,
        linkedAt: ServerValue.TIMESTAMP,
        updatedAt: ServerValue.TIMESTAMP,
      },
      [`patreonBindings/${patronUserId}`]: uid,
      [`Patrons/${uid}/tier`]: level,
    }
    await rtdb.ref().update(updates)
    return back('linked')
  } catch (err) {
    logger.error('patreonAuthCallback error', err)
    return back('error')
  }
})
```

- [ ] **Step 2: Verify import + tests**

Run: `node --input-type=module -e "await import('./functions/index.js'); console.log('OK')"` then `node --test functions/patreon.test.js`
Expected: `OK`, then PASS.

- [ ] **Step 3: Commit**

```
git add functions/patreon.js
git commit -m "feat(patreon): patreonAuthCallback OAuth exchange + link write"
```

---

## Task 8: Unlink - shared core + desktop + browser front-ends (TDD for the core)

**Files:** Modify `functions/patreon.js`, `functions/patreon.test.js`

- [ ] **Step 1: Write a failing test for the pure update-builder** (append)

```javascript
import { buildUnlinkUpdates } from './patreon.js'

test('buildUnlinkUpdates: clears link, binding (when known), and tier', () => {
  assert.deepEqual(buildUnlinkUpdates('uid-1', 'patron-9'), {
    'patreonLinks/uid-1': null,
    'patreonBindings/patron-9': null,
    'Patrons/uid-1/tier': null,
  })
})

test('buildUnlinkUpdates: no patron id -> omits the binding path', () => {
  assert.deepEqual(buildUnlinkUpdates('uid-1', null), {
    'patreonLinks/uid-1': null,
    'Patrons/uid-1/tier': null,
  })
})
```

- [ ] **Step 2: Run to confirm failure**

Run: `node --test functions/patreon.test.js`
Expected: FAIL.

- [ ] **Step 3: Implement core + front-ends in `patreon.js`**

```javascript
export function buildUnlinkUpdates(uid, patreonUserId) {
  const updates = { [`patreonLinks/${uid}`]: null, [`Patrons/${uid}/tier`]: null }
  if (patreonUserId) updates[`patreonBindings/${patreonUserId}`] = null
  return updates
}

// Admin-SDK unlink for a verified uid. Reads the link to find the patron id so
// the reverse binding is removed too. DMHub campaign only - never touches
// /Patrons/{uid}/subscription or /inventory.
async function doPatreonUnlink(uid) {
  const rtdb = getDatabase()
  const snap = await rtdb.ref(`patreonLinks/${uid}`).get()
  const patreonUserId = snap.exists() ? (snap.val()?.patreonUserId || null) : null
  await rtdb.ref().update(buildUnlinkUpdates(uid, patreonUserId))
}

// Desktop-called: net.Post auto-injects { userid, secretid }; validate via secretid.
export const patreonUnlink = onRequest(async (req, res) => {
  try {
    if (req.method !== 'POST') return res.status(405).json({ error: 'Method Not Allowed' })
    const userid = req.body?.userid
    const secretid = req.body?.secretid
    if (!userid || !secretid) return res.status(400).json({ error: 'Must provide secretid and userid' })
    const rtdb = getDatabase()
    const secretSnap = await rtdb.ref(`/users/${userid}/secretid`).once('value')
    if (!secretSnap.exists() || secretSnap.val() !== secretid) {
      return res.status(403).json({ error: 'Your account could not be validated.' })
    }
    await doPatreonUnlink(userid)
    return res.status(200).json({ ok: true })
  } catch (err) {
    logger.error('patreonUnlink error', err)
    return res.status(500).json({ error: 'Internal error' })
  }
})

// Browser-called: verify idToken from the body (for the companion Disconnect button).
export const patreonUnlinkWeb = onRequest({ secrets: ALL_SECRETS }, async (req, res) => {
  setCors(res, req.get('Origin') || '')
  if (req.method === 'OPTIONS') return res.status(204).send('')
  if (req.method !== 'POST') return bad(res, 'Method not allowed', 405)
  try {
    const uid = await uidFromBody(req, res)
    if (!uid) return
    await doPatreonUnlink(uid)
    return res.status(200).json({ ok: true })
  } catch (err) {
    logger.error('patreonUnlinkWeb error', err)
    return bad(res, 'Internal error', 500)
  }
})
```

Note: `patreonUnlink` mirrors `redeem`'s validation (read `/users/{userid}/secretid`) rather than a shared `verifySecretId` import, because that helper is module-private to `index.js`; the inline check is identical behavior.

- [ ] **Step 4: Run the test to confirm it passes**

Run: `node --test functions/patreon.test.js`
Expected: PASS.

- [ ] **Step 5: Verify import; Commit**

Run: `node --input-type=module -e "await import('./functions/index.js'); console.log('OK')"`
Expected: `OK`

```
git add functions/patreon.js functions/patreon.test.js
git commit -m "feat(patreon): unlink core + desktop + browser endpoints (TDD)"
```

---

## Task 9: `patreonWebhook` (signed member events)

**Files:** Modify `functions/patreon.js`

- [ ] **Step 1: Replace the `patreonWebhook` stub**

```javascript
// Parse a webhook member payload (same shape as a member GET) into our fields.
export function parseWebhookMember(body, tierMap) {
  const member = body?.data
  if (!member || member.type !== 'member') return null
  const patronUserId = member.relationships?.user?.data?.id || null
  const ids = (member.relationships?.currently_entitled_tiers?.data || []).map((t) => t.id)
  return {
    patronUserId,
    level: levelFromEntitledTiers(ids, tierMap),
    patronStatus: member.attributes?.patron_status || null,
  }
}

export const patreonWebhook = onRequest({ secrets: ALL_SECRETS }, async (req, res) => {
  try {
    if (req.method !== 'POST') return res.status(405).end()
    const sig = req.get('X-Patreon-Signature')
    const event = req.get('X-Patreon-Event') || ''
    if (!verifyPatreonSignature(req.rawBody, sig, PATREON_WEBHOOK_SECRET.value())) {
      logger.warn('patreonWebhook: bad signature')
      return res.status(401).end()
    }
    let body
    try { body = JSON.parse(req.rawBody.toString('utf8')) } catch { return res.status(400).end() }
    const parsed = parseWebhookMember(body, tierMap())
    if (!parsed || !parsed.patronUserId) return res.status(200).end() // nothing actionable

    const rtdb = getDatabase()
    const uidSnap = await rtdb.ref(`patreonBindings/${parsed.patronUserId}`).get()
    if (!uidSnap.exists()) return res.status(200).end() // not a linked user
    const uid = uidSnap.val()

    const isDelete = event.includes('delete')
    const level = isDelete ? 0 : parsed.level
    await rtdb.ref().update({
      [`patreonLinks/${uid}/tier`]: level,
      [`patreonLinks/${uid}/patronStatus`]: isDelete ? 'former_patron' : parsed.patronStatus,
      [`patreonLinks/${uid}/updatedAt`]: ServerValue.TIMESTAMP,
      [`Patrons/${uid}/tier`]: level,
    })
    return res.status(200).end()
  } catch (err) {
    logger.error('patreonWebhook error', err)
    return res.status(500).end() // Patreon will retry
  }
})
```

Add a unit test for `parseWebhookMember` (append to `patreon.test.js`):

```javascript
import { parseWebhookMember } from './patreon.js'

test('parseWebhookMember: extracts patron id, level, status', () => {
  const body = { data: { type: 'member', attributes: { patron_status: 'active_patron' },
    relationships: { currently_entitled_tiers: { data: [{ type: 'tier', id: 't2' }] },
      user: { data: { type: 'user', id: 'p9' } } } } }
  assert.deepEqual(parseWebhookMember(body, { t2: 2 }),
    { patronUserId: 'p9', level: 2, patronStatus: 'active_patron' })
})

test('parseWebhookMember: non-member body -> null', () => {
  assert.equal(parseWebhookMember({ data: { type: 'post' } }, {}), null)
})
```

- [ ] **Step 2: Run tests + import check**

Run: `node --test functions/patreon.test.js` then `node --input-type=module -e "await import('./functions/index.js'); console.log('OK')"`
Expected: PASS, then `OK`.

- [ ] **Step 3: Commit**

```
git add functions/patreon.js functions/patreon.test.js
git commit -m "feat(patreon): patreonWebhook signed member-event ingest"
```

---

## Task 10: `patreonReconcile` (scheduled daily)

**Files:** Modify `functions/patreon.js`

- [ ] **Step 1: Replace the `patreonReconcile` stub**

```javascript
// Read the live creator token from RTDB, refreshing it (and persisting the
// rotated refresh token) when within 2 days of expiry. Seeds from the secret
// on first run.
async function getCreatorAccessToken(rtdb) {
  const ref = rtdb.ref('patreonCreatorToken')
  const snap = await ref.get()
  let stored = snap.exists() ? snap.val() : null
  const needsRefresh = !stored || !stored.accessToken
    || (stored.expiresAt || 0) - Date.now() < 2 * 24 * 60 * 60 * 1000
  if (!needsRefresh) return stored.accessToken
  const refreshTok = (stored && stored.refreshToken) || PATREON_CREATOR_REFRESH_TOKEN.value()
  const tok = await refreshToken({
    refreshToken: refreshTok,
    clientId: PATREON_CLIENT_ID.value(),
    clientSecret: PATREON_CLIENT_SECRET.value(),
  })
  await ref.set({
    accessToken: tok.access_token,
    refreshToken: tok.refresh_token, // rotated - persist the NEW one
    expiresAt: Date.now() + (tok.expires_in || 0) * 1000,
  })
  return tok.access_token
}

export const patreonReconcile = onSchedule({ schedule: 'every 24 hours', secrets: ALL_SECRETS }, async () => {
  const rtdb = getDatabase()
  const campaignId = PATREON_CAMPAIGN_ID.value()
  const map = tierMap()
  const accessToken = await getCreatorAccessToken(rtdb)

  // 1) Sweep all members; record the level for each linked uid we see active.
  const seenPatronIds = new Set()
  let cursor = null
  do {
    const page = await fetchMembersPage({ accessToken, campaignId, cursor })
    const { members, nextCursor } = parseMembersPage(page, map)
    for (const m of members) {
      seenPatronIds.add(m.patronUserId)
      const uidSnap = await rtdb.ref(`patreonBindings/${m.patronUserId}`).get()
      if (!uidSnap.exists()) continue
      const uid = uidSnap.val()
      const level = m.patronStatus === 'active_patron' ? m.level : 0
      await rtdb.ref().update({
        [`patreonLinks/${uid}/tier`]: level,
        [`patreonLinks/${uid}/patronStatus`]: m.patronStatus,
        [`patreonLinks/${uid}/updatedAt`]: ServerValue.TIMESTAMP,
        [`Patrons/${uid}/tier`]: level,
      })
    }
    cursor = nextCursor
  } while (cursor)

  // 2) Safety net: any linked patron NOT seen as active in the sweep -> level 0
  // (catches missed lapse webhooks). Iterate /patreonBindings.
  const bindingsSnap = await rtdb.ref('patreonBindings').get()
  const bindings = bindingsSnap.exists() ? bindingsSnap.val() : {}
  for (const [patronUserId, uid] of Object.entries(bindings)) {
    if (seenPatronIds.has(patronUserId)) continue
    await rtdb.ref().update({
      [`patreonLinks/${uid}/tier`]: 0,
      [`patreonLinks/${uid}/patronStatus`]: 'former_patron',
      [`patreonLinks/${uid}/updatedAt`]: ServerValue.TIMESTAMP,
      [`Patrons/${uid}/tier`]: 0,
    })
  }
  logger.log(`patreonReconcile: swept ${seenPatronIds.size} active members`)
})
```

- [ ] **Step 2: Verify import + tests (no regressions)**

Run: `node --input-type=module -e "await import('./functions/index.js'); console.log('OK')"` then `node --test functions/patreon.test.js`
Expected: `OK`, then PASS.

- [ ] **Step 3: Commit**

```
git add functions/patreon.js
git commit -m "feat(patreon): patreonReconcile daily token-refresh + tier sync + lapse sweep"
```

---

## Task 11: Webhook registration script + deploy/config docs

**Files:**
- Create: `functions/register-patreon-webhook.js`
- Modify: `CLOUD_FUNCTIONS.md`

- [ ] **Step 1: Create the one-time registration script**

```javascript
// One-time: register the Patreon webhook for our campaign. Run locally with the
// creator access token + secrets in env. NOT a deployed function.
//   node functions/register-patreon-webhook.js
// Env: PATREON_CREATOR_ACCESS_TOKEN, PATREON_CAMPAIGN_ID, PATREON_WEBHOOK_URI
const accessToken = process.env.PATREON_CREATOR_ACCESS_TOKEN
const campaignId = process.env.PATREON_CAMPAIGN_ID
const uri = process.env.PATREON_WEBHOOK_URI
if (!accessToken || !campaignId || !uri) {
  console.error('Set PATREON_CREATOR_ACCESS_TOKEN, PATREON_CAMPAIGN_ID, PATREON_WEBHOOK_URI'); process.exit(1)
}
const body = {
  data: {
    type: 'webhook',
    attributes: { triggers: ['members:create', 'members:update', 'members:delete'], uri },
    relationships: { campaign: { data: { type: 'campaign', id: campaignId } } },
  },
}
const res = await fetch('https://www.patreon.com/api/oauth2/v2/webhooks', {
  method: 'POST',
  headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
  body: JSON.stringify(body),
})
const json = await res.json()
console.log(res.status, JSON.stringify(json, null, 2))
console.log('IMPORTANT: copy the returned data.attributes.secret into the PATREON_WEBHOOK_SECRET function secret.')
```

- [ ] **Step 2: Document config in `CLOUD_FUNCTIONS.md`**

Append a "Patreon account link" section listing: the deployed function URLs; the secrets to set (`firebase functions:secrets:set PATREON_CLIENT_ID` etc. for CLIENT_ID, CLIENT_SECRET, STATE_SECRET, WEBHOOK_SECRET, CREATOR_REFRESH_TOKEN); the params to set (`firebase functions:params:set PATREON_CALLBACK_URL="..."` for CALLBACK_URL, APP_ORIGIN, ALLOWED_ORIGINS, CAMPAIGN_ID, TIER_MAP); the redirect URI to register on the Patreon client (= the deployed `patreonAuthCallback` URL); and the webhook registration step (run the script, then store the returned secret). Reference spec Section 11 for the owner-supplied inputs.

- [ ] **Step 3: Full test suite + import sanity**

Run: `npm test`
Expected: all tests PASS.
Run: `node --input-type=module -e "await import('./functions/index.js'); console.log('OK')"`
Expected: `OK`

- [ ] **Step 4: Commit**

```
git add functions/register-patreon-webhook.js CLOUD_FUNCTIONS.md
git commit -m "docs(patreon): webhook registration script + deploy/config notes"
```

---

## Deploy / verification (requires owner inputs - NOT part of code review)

These steps need the Section 11 inputs and cannot run until then. Document, do not execute during implementation:
1. Set all secrets + params (Task 11 Step 2).
2. `npm run deploy` (or `firebase deploy --only functions:patreonAuthStart,functions:patreonAuthCallback,...`).
3. Register the `patreonAuthCallback` URL as the redirect URI on the Patreon OAuth client; store the client id/secret.
4. Run `register-patreon-webhook.js`; copy the returned secret into `PATREON_WEBHOOK_SECRET`; redeploy.
5. End-to-end test with a sandbox patron: connect via the companion (SP3), confirm `/Patrons/{uid}/tier` updates and `dmhub.patronTier` reflects it; change the tier on Patreon and confirm the webhook updates it; disconnect and confirm it clears.

---

## Self-review notes (author)

- **Spec coverage:** schema (S4) -> Tasks 1,7,8,9,10 write exactly `/patreonLinks`, `/patreonBindings`, `/Patrons/{uid}/tier` (+ `/patreonCreatorToken`); tier map (S5) -> Task 2 + `tierMap()`; `patreonAuthStart` (S6a) -> Task 6; `patreonAuthCallback` (S6b) -> Task 7; `patreonUnlink` desktop + browser (S6c) -> Task 8; `patreonWebhook` HMAC-MD5 raw body (S6d) -> Tasks 3,9; `patreonReconcile` refresh+sweep+lapse (S6e) -> Tasks 5,10; secrets migration (S6 config, S10) -> Task 11; security (S10): admin-only writes, uid from verified auth, signed state, signature verify -> Tasks 4,6,7,8,9. All spec backend requirements map to a task.
- **Naming consistency:** `levelFromEntitledTiers`, `verifyPatreonSignature`, `signState`/`verifyState`, `exchangeCode`/`refreshToken`/`fetchIdentity`/`fetchMembersPage`, `parseIdentityForCampaign`/`parseMembersPage`/`parseWebhookMember`, `buildUnlinkUpdates`, `doPatreonUnlink`, `tierMap`, `uidFromBody` - each defined once and referenced by the same name in later tasks. Exports in index.js (Task 1 Step 2) match the six function names.
- **No placeholders:** every code step has complete code; every test step has runnable assertions and an expected result.
- **Known deferral:** the onRequest/onSchedule handlers are verified by import + their pure cores' unit tests + the documented emulator/end-to-end deploy steps (handlers need the emulator/live secrets, like shopify's functions which are not unit-tested directly). This matches the existing repo's test boundary.
