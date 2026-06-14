# Discord Account Linking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a signed-in Codex user link their Discord account from the companion Account page — adding them to the Draw Steel guild, granting a flat "linked" role, and showing their Discord handle + avatar.

**Architecture:** Mirrors the existing Patreon/Shopify account-link pattern. Backend Cloud Functions (`dmhubclient/cloud-functions/functions/discord.js`) own the OAuth secret + bot token and do the guild-join + role-grant; the companion frontend only kicks off the round-trip and reads the resulting `/discordLinks/{uid}` node live. The user's OAuth token is used once server-side and never persisted; the bot token grants the role.

**Tech Stack:** Firebase Functions v2 (ESM), firebase-admin RTDB, Discord OAuth2 + REST API; React + Vite frontend; `node:test` (backend) and Vitest (frontend) for tests.

**Spec:** `draw-steel-codex/docs/superpowers/specs/2026-06-14-discord-account-linking-design.md`

**Two repos / two phases:** Phase A is the backend in `C:\MCDM\dmhubclient\cloud-functions`. Phase B is the frontend in `C:\MCDM\draw-steel-companion`. Phase B is mergeable before Phase A deploys (the connect buttons are hidden until the Function URLs are configured).

---

## Phase A — Backend (`C:\MCDM\dmhubclient\cloud-functions`)

All Phase A paths are relative to `C:\MCDM\dmhubclient\cloud-functions`. Tests run with `npm test` (which runs `node --test`) from the `functions/` directory, matching `patreon.test.js` / `shopify-state.test.js`.

### Task A1: Discord module skeleton + state helpers (TDD)

**Files:**
- Create: `functions/discord.js`
- Test: `functions/discord-state.test.js`

- [ ] **Step 1: Write the failing test**

Create `functions/discord-state.test.js`:

```js
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { signState, verifyState, pickRedirectOrigin } from './discord.js'

const SECRET = 'test-state-secret-abc-123'

test('signState/verifyState: round-trips uid + origin', () => {
  const state = signState('user-123', 'https://draw-steel-codex.com', SECRET)
  assert.deepEqual(verifyState(state, SECRET), {
    uid: 'user-123', origin: 'https://draw-steel-codex.com',
  })
})

test('verifyState: empty/undefined origin normalizes to ""', () => {
  assert.deepEqual(verifyState(signState('u1', '', SECRET), SECRET), { uid: 'u1', origin: '' })
  assert.deepEqual(verifyState(signState('u1', undefined, SECRET), SECRET), { uid: 'u1', origin: '' })
})

test('verifyState: signature mismatch returns null', () => {
  const state = signState('user-123', 'https://x.com', SECRET)
  const last = state.slice(-1)
  const mangled = state.slice(0, -1) + (last === 'a' ? 'b' : 'a')
  assert.equal(verifyState(mangled, SECRET), null)
})

test('verifyState: different secret returns null', () => {
  assert.equal(verifyState(signState('u1', 'https://x.com', SECRET), 'other'), null)
})

test('verifyState: invalid uid format returns null even if validly signed', () => {
  assert.equal(verifyState(signState('bad uid!', '', SECRET), SECRET), null)
})

test('verifyState: garbage input returns null', () => {
  assert.equal(verifyState('not-a-state', SECRET), null)
  assert.equal(verifyState('', SECRET), null)
  assert.equal(verifyState(null, SECRET), null)
})

test('pickRedirectOrigin: allowlisted origin passes, else fallback', () => {
  const allowed = ['https://a.com', 'https://draw-steel-codex.com']
  assert.equal(pickRedirectOrigin('https://draw-steel-codex.com', allowed, 'https://fb.com'), 'https://draw-steel-codex.com')
  assert.equal(pickRedirectOrigin('https://evil.com', allowed, 'https://fb.com'), 'https://fb.com')
  assert.equal(pickRedirectOrigin('', allowed, 'https://fb.com'), 'https://fb.com')
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && node --test discord-state.test.js`
Expected: FAIL — `Cannot find module './discord.js'`.

- [ ] **Step 3: Write minimal implementation**

Create `functions/discord.js` with the module header, secret/param definitions, and the pure helpers (own copies, keeping the module self-contained as `patreon.js` / `shopify.js` do):

```js
// Discord account-link Functions — link a Codex user to their Discord account,
// add them to the Draw Steel guild, and grant a flat "linked" role.
//
// Self-contained ESM module (mirrors patreon.js / shopify.js). Admin SDK is
// initialized in index.js — do NOT call initializeApp() here. Re-exported from
// index.js.
//
// Spec: draw-steel-codex/docs/superpowers/specs/2026-06-14-discord-account-linking-design.md
// Firebase project: mcdm-385cf
import { onRequest } from 'firebase-functions/v2/https'
import { defineString, defineSecret } from 'firebase-functions/params'
import * as logger from 'firebase-functions/logger'
import { getAuth } from 'firebase-admin/auth'
import { getDatabase, ServerValue } from 'firebase-admin/database'
import { createHmac, randomBytes, timingSafeEqual } from 'crypto'

// --- Secrets (firebase functions:secrets:set <NAME>) ---
const DISCORD_CLIENT_ID = defineSecret('DISCORD_CLIENT_ID')
const DISCORD_CLIENT_SECRET = defineSecret('DISCORD_CLIENT_SECRET')
const DISCORD_STATE_SECRET = defineSecret('DISCORD_STATE_SECRET')
const DISCORD_BOT_TOKEN = defineSecret('DISCORD_BOT_TOKEN')

// --- Params (firebase functions:params:set <NAME>="...") ---
const DISCORD_CALLBACK_URL = defineString('DISCORD_CALLBACK_URL', { default: '' })
const DISCORD_APP_ORIGIN = defineString('DISCORD_APP_ORIGIN', { default: '' })
const DISCORD_ALLOWED_ORIGINS = defineString('DISCORD_ALLOWED_ORIGINS', { default: '' })
const DISCORD_GUILD_ID = defineString('DISCORD_GUILD_ID', { default: '' })
const DISCORD_LINKED_ROLE_ID = defineString('DISCORD_LINKED_ROLE_ID', { default: '' })

// --- Constants ---
const AUTHORIZE_URL = 'https://discord.com/oauth2/authorize'
const TOKEN_URL = 'https://discord.com/api/oauth2/token'
const API_BASE = 'https://discord.com/api'
const SCOPE = 'identify guilds.join'
const STATE_MAX_AGE_MS = 10 * 60 * 1000
const FIREBASE_UID_RE = /^[A-Za-z0-9_-]{1,128}$/
const START_SECRETS = [DISCORD_CLIENT_ID, DISCORD_STATE_SECRET]
const CALLBACK_SECRETS = [DISCORD_CLIENT_ID, DISCORD_CLIENT_SECRET, DISCORD_STATE_SECRET, DISCORD_BOT_TOKEN]

// --- Small shared helpers (own copies; self-contained module) ---
function splitList(v) {
  return (v || '').split(',').map((s) => s.trim()).filter(Boolean)
}

function setCors(res, origin) {
  const allowed = splitList(DISCORD_ALLOWED_ORIGINS.value())
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

// state = b64url(JSON{uid,origin,iat,n}) + "." + b64url(HMAC-SHA256(payload)).
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
  return { uid: obj.uid, origin: typeof obj.origin === 'string' ? obj.origin : '' }
}

export function pickRedirectOrigin(origin, allowed, fallback) {
  return origin && allowed.includes(origin) ? origin : fallback
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && node --test discord-state.test.js`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add functions/discord.js functions/discord-state.test.js
git commit -m "feat(discord): state-signing + redirect helpers for account link"
```

---

### Task A2: Discord API client + parser (TDD)

**Files:**
- Modify: `functions/discord.js` (append)
- Test: `functions/discord-api.test.js`

- [ ] **Step 1: Write the failing test**

Create `functions/discord-api.test.js`:

```js
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { fetchDiscordUser, addGuildMember, setMemberRole, parseDiscordUser } from './discord.js'

// Minimal fake of the fetch Response surface the client uses.
function fakeFetch(responses) {
  const calls = []
  const impl = async (url, opts) => {
    calls.push({ url, opts })
    const r = responses.shift()
    return {
      ok: r.status >= 200 && r.status < 300,
      status: r.status,
      json: async () => r.body,
      text: async () => JSON.stringify(r.body ?? ''),
    }
  }
  impl.calls = calls
  return impl
}

test('parseDiscordUser: extracts id/username/global_name/avatar; missing → null', () => {
  assert.deepEqual(
    parseDiscordUser({ id: '42', username: 'runehammer', global_name: 'Rune', avatar: 'abc' }),
    { discordUserId: '42', username: 'runehammer', globalName: 'Rune', avatar: 'abc' },
  )
  assert.deepEqual(
    parseDiscordUser({ id: '7', username: 'x' }),
    { discordUserId: '7', username: 'x', globalName: null, avatar: null },
  )
  assert.deepEqual(parseDiscordUser(null), { discordUserId: null, username: null, globalName: null, avatar: null })
})

test('fetchDiscordUser: GETs /users/@me with a bearer token and returns the body', async () => {
  const f = fakeFetch([{ status: 200, body: { id: '42', username: 'r' } }])
  const user = await fetchDiscordUser('access-tok', f)
  assert.equal(user.id, '42')
  assert.match(f.calls[0].url, /\/users\/@me$/)
  assert.equal(f.calls[0].opts.headers.Authorization, 'Bearer access-tok')
})

test('fetchDiscordUser: throws on non-2xx', async () => {
  const f = fakeFetch([{ status: 401, body: { message: 'nope' } }])
  await assert.rejects(() => fetchDiscordUser('bad', f), /identity fetch failed: 401/)
})

test('addGuildMember: PUT with bot auth + access_token body; 201 and 204 both succeed', async () => {
  const f = fakeFetch([{ status: 201, body: {} }, { status: 204, body: null }])
  await addGuildMember({ guildId: 'g', userId: 'u', botToken: 'bot', userAccessToken: 'ua' }, f)
  await addGuildMember({ guildId: 'g', userId: 'u', botToken: 'bot', userAccessToken: 'ua' }, f)
  assert.match(f.calls[0].url, /\/guilds\/g\/members\/u$/)
  assert.equal(f.calls[0].opts.method, 'PUT')
  assert.equal(f.calls[0].opts.headers.Authorization, 'Bot bot')
  assert.deepEqual(JSON.parse(f.calls[0].opts.body), { access_token: 'ua' })
})

test('addGuildMember: throws on a real error status (403)', async () => {
  const f = fakeFetch([{ status: 403, body: { message: 'banned' } }])
  await assert.rejects(
    () => addGuildMember({ guildId: 'g', userId: 'u', botToken: 'b', userAccessToken: 'a' }, f),
    /guild join failed: 403/,
  )
})

test('setMemberRole: PUT adds, DELETE removes, both with bot auth; 204 succeeds', async () => {
  const f = fakeFetch([{ status: 204, body: null }, { status: 204, body: null }])
  await setMemberRole({ guildId: 'g', userId: 'u', roleId: 'r', botToken: 'bot', method: 'PUT' }, f)
  await setMemberRole({ guildId: 'g', userId: 'u', roleId: 'r', botToken: 'bot', method: 'DELETE' }, f)
  assert.match(f.calls[0].url, /\/guilds\/g\/members\/u\/roles\/r$/)
  assert.equal(f.calls[0].opts.method, 'PUT')
  assert.equal(f.calls[1].opts.method, 'DELETE')
  assert.equal(f.calls[0].opts.headers.Authorization, 'Bot bot')
})

test('setMemberRole: throws on non-2xx', async () => {
  const f = fakeFetch([{ status: 403, body: { message: 'no perms' } }])
  await assert.rejects(
    () => setMemberRole({ guildId: 'g', userId: 'u', roleId: 'r', botToken: 'b', method: 'PUT' }, f),
    /role update failed: 403/,
  )
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && node --test discord-api.test.js`
Expected: FAIL — the named exports don't exist yet.

- [ ] **Step 3: Write minimal implementation**

Append to `functions/discord.js`:

```js
// --- Discord API client (inject fetchImpl for tests; defaults to global fetch) ---
function formBody(obj) {
  return Object.entries(obj).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&')
}

export async function exchangeCode({ code, clientId, clientSecret, redirectUri }, fetchImpl = fetch) {
  const res = await fetchImpl(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: formBody({
      grant_type: 'authorization_code', code, redirect_uri: redirectUri,
      client_id: clientId, client_secret: clientSecret,
    }),
  })
  if (!res.ok) {
    const body = await res.text().catch(() => '')
    throw new Error(`token exchange failed: ${res.status} ${body.slice(0, 200)}`)
  }
  return res.json() // { access_token, token_type, expires_in, scope, ... }
}

export async function fetchDiscordUser(accessToken, fetchImpl = fetch) {
  const res = await fetchImpl(`${API_BASE}/users/@me`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  })
  if (!res.ok) {
    const body = await res.text().catch(() => '')
    throw new Error(`identity fetch failed: ${res.status} ${body.slice(0, 200)}`)
  }
  return res.json() // { id, username, global_name, avatar, ... }
}

// PUT a guild member on the user's behalf (guilds.join). 201 = added, 204 =
// already a member; both are success. Anything else throws.
export async function addGuildMember({ guildId, userId, botToken, userAccessToken }, fetchImpl = fetch) {
  const res = await fetchImpl(`${API_BASE}/guilds/${guildId}/members/${userId}`, {
    method: 'PUT',
    headers: { Authorization: `Bot ${botToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ access_token: userAccessToken }),
  })
  if (res.status !== 201 && res.status !== 204) {
    const body = await res.text().catch(() => '')
    throw new Error(`guild join failed: ${res.status} ${body.slice(0, 200)}`)
  }
}

// Add (method 'PUT') or remove (method 'DELETE') a role on a guild member,
// using the bot token. Idempotent. 204 on success.
export async function setMemberRole({ guildId, userId, roleId, botToken, method }, fetchImpl = fetch) {
  const res = await fetchImpl(`${API_BASE}/guilds/${guildId}/members/${userId}/roles/${roleId}`, {
    method,
    headers: { Authorization: `Bot ${botToken}` },
  })
  if (!res.ok) {
    const body = await res.text().catch(() => '')
    throw new Error(`role update failed: ${res.status} ${body.slice(0, 200)}`)
  }
}

// --- Pure parser ---
export function parseDiscordUser(user) {
  return {
    discordUserId: user?.id || null,
    username: user?.username || null,
    globalName: user?.global_name || null,
    avatar: user?.avatar || null,
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && node --test discord-api.test.js`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add functions/discord.js functions/discord-api.test.js
git commit -m "feat(discord): OAuth token exchange, identity, guild-join + role REST helpers"
```

---

### Task A3: RTDB update builders (TDD)

**Files:**
- Modify: `functions/discord.js` (append)
- Test: `functions/discord-updates.test.js`

- [ ] **Step 1: Write the failing test**

Create `functions/discord-updates.test.js`:

```js
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { buildLinkUpdates, buildUnlinkUpdates } from './discord.js'

const TS = { '.sv': 'timestamp' } // ServerValue.TIMESTAMP sentinel

test('buildLinkUpdates: writes only /discordLinks/{uid} with profile + timestamps, no tokens', () => {
  const updates = buildLinkUpdates('uid-1', {
    discordUserId: '42', username: 'rune', globalName: 'Rune', avatar: 'abc',
  })
  assert.deepEqual(updates, {
    'discordLinks/uid-1': {
      discordUserId: '42', username: 'rune', globalName: 'Rune', avatar: 'abc',
      linkedAt: TS, updatedAt: TS,
    },
  })
  // No access/refresh token leaks into the record.
  const json = JSON.stringify(updates)
  assert.ok(!/token/i.test(json), 'record must not contain any token field')
})

test('buildUnlinkUpdates: nulls the link node', () => {
  assert.deepEqual(buildUnlinkUpdates('uid-1'), { 'discordLinks/uid-1': null })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && node --test discord-updates.test.js`
Expected: FAIL — `buildLinkUpdates` not exported.

- [ ] **Step 3: Write minimal implementation**

Append to `functions/discord.js`:

```js
// --- RTDB update builders (pure; ServerValue.TIMESTAMP is a constant sentinel) ---
export function buildLinkUpdates(uid, profile) {
  return {
    [`discordLinks/${uid}`]: {
      discordUserId: profile.discordUserId,
      username: profile.username,
      globalName: profile.globalName,
      avatar: profile.avatar,
      linkedAt: ServerValue.TIMESTAMP,
      updatedAt: ServerValue.TIMESTAMP,
    },
  }
}

export function buildUnlinkUpdates(uid) {
  return { [`discordLinks/${uid}`]: null }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && node --test discord-updates.test.js`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add functions/discord.js functions/discord-updates.test.js
git commit -m "feat(discord): pure RTDB link/unlink update builders"
```

---

### Task A4: HTTP handlers + index export (no new unit tests — integration-verified later)

**Files:**
- Modify: `functions/discord.js` (append handlers)
- Modify: `functions/index.js:27` (add export line)

The handlers compose the already-tested pure pieces; like `patreon.js`, the handlers themselves aren't unit-tested (they need the emulator). Verify by running the full suite (proves nothing broke) plus a deploy smoke test in Task A5.

- [ ] **Step 1: Append the handlers to `functions/discord.js`**

```js
// --- HTTP handler helpers ---
async function uidFromBody(req, res) {
  const { idToken } = req.body || {}
  if (!idToken || typeof idToken !== 'string') { bad(res, 'Missing idToken', 400); return null }
  try {
    const decoded = await getAuth().verifyIdToken(idToken)
    if (!FIREBASE_UID_RE.test(decoded.uid || '')) { bad(res, 'invalid-id-token', 401); return null }
    return decoded.uid
  } catch (err) {
    logger.warn('discord: verifyIdToken rejected', err?.message || err)
    bad(res, 'invalid-id-token', 401); return null
  }
}

export const discordAuthStart = onRequest({ secrets: START_SECRETS }, async (req, res) => {
  const origin = req.get('Origin') || ''
  setCors(res, origin)
  if (req.method === 'OPTIONS') return res.status(204).send('')
  if (req.method !== 'POST') return bad(res, 'Method not allowed', 405)
  try {
    const uid = await uidFromBody(req, res)
    if (!uid) return
    const url = new URL(AUTHORIZE_URL)
    url.searchParams.set('response_type', 'code')
    url.searchParams.set('client_id', DISCORD_CLIENT_ID.value())
    url.searchParams.set('redirect_uri', DISCORD_CALLBACK_URL.value())
    url.searchParams.set('scope', SCOPE)
    url.searchParams.set('state', signState(uid, origin, DISCORD_STATE_SECRET.value()))
    return res.status(200).json({ ok: true, authorizeUrl: url.toString() })
  } catch (err) {
    logger.error('discordAuthStart error', err)
    return bad(res, 'Internal error', 500)
  }
})

export const discordAuthCallback = onRequest({ secrets: CALLBACK_SECRETS }, async (req, res) => {
  let appOrigin = DISCORD_APP_ORIGIN.value()
  const back = (status) => res.redirect(302, `${appOrigin}/more/account?discord=${status}`)
  try {
    if (req.method !== 'GET') return res.status(405).send('Method Not Allowed')
    const { code, state } = req.query
    if (typeof code !== 'string' || typeof state !== 'string') return back('error')
    const decoded = verifyState(state, DISCORD_STATE_SECRET.value())
    if (!decoded) { logger.warn('discordAuthCallback: bad state'); return back('error') }
    const uid = decoded.uid
    appOrigin = pickRedirectOrigin(decoded.origin, splitList(DISCORD_ALLOWED_ORIGINS.value()), appOrigin)

    const tokens = await exchangeCode({
      code,
      clientId: DISCORD_CLIENT_ID.value(),
      clientSecret: DISCORD_CLIENT_SECRET.value(),
      redirectUri: DISCORD_CALLBACK_URL.value(),
    })
    const profile = parseDiscordUser(await fetchDiscordUser(tokens.access_token))
    if (!profile.discordUserId) { logger.error('discordAuthCallback: no user id in identity'); return back('error') }

    const guildId = DISCORD_GUILD_ID.value()
    const roleId = DISCORD_LINKED_ROLE_ID.value()
    const botToken = DISCORD_BOT_TOKEN.value()
    // Add to the guild (no-op if already a member), then grant the linked role.
    await addGuildMember({ guildId, userId: profile.discordUserId, botToken, userAccessToken: tokens.access_token })
    await setMemberRole({ guildId, userId: profile.discordUserId, roleId, botToken, method: 'PUT' })

    // Only write the link AFTER the role grant succeeds — no partial links.
    await getDatabase().ref().update(buildLinkUpdates(uid, profile))
    return back('linked')
  } catch (err) {
    logger.error('discordAuthCallback error', err)
    return back('error')
  }
})

export const discordUnlinkWeb = onRequest({ secrets: [DISCORD_BOT_TOKEN] }, async (req, res) => {
  setCors(res, req.get('Origin') || '')
  if (req.method === 'OPTIONS') return res.status(204).send('')
  if (req.method !== 'POST') return bad(res, 'Method not allowed', 405)
  try {
    const uid = await uidFromBody(req, res)
    if (!uid) return
    const rtdb = getDatabase()
    const snap = await rtdb.ref(`discordLinks/${uid}`).get()
    const discordUserId = snap.exists() ? (snap.val()?.discordUserId || null) : null
    if (discordUserId) {
      // Best-effort role removal; we still clear our record even if Discord
      // rejects (e.g. the member already left the guild).
      try {
        await setMemberRole({
          guildId: DISCORD_GUILD_ID.value(), userId: discordUserId,
          roleId: DISCORD_LINKED_ROLE_ID.value(), botToken: DISCORD_BOT_TOKEN.value(), method: 'DELETE',
        })
      } catch (e) {
        logger.warn('discordUnlinkWeb: role removal failed (clearing link anyway)', e?.message || e)
      }
    }
    await rtdb.ref().update(buildUnlinkUpdates(uid))
    return res.status(200).json({ ok: true })
  } catch (err) {
    logger.error('discordUnlinkWeb error', err)
    return bad(res, 'Internal error', 500)
  }
})
```

- [ ] **Step 2: Add the export to `functions/index.js`**

After line 27 (the `patreon.js` export), add:

```js
export { discordAuthStart, discordAuthCallback, discordUnlinkWeb } from "./discord.js";
```

- [ ] **Step 3: Run the full backend test suite**

Run: `cd functions && npm test`
Expected: PASS — all existing tests plus the 16 new Discord tests (7 + 7 + 2). No failures.

- [ ] **Step 4: Lint / syntax check the new module**

Run: `cd functions && node --check discord.js`
Expected: no output (exit 0) — the module parses.

- [ ] **Step 5: Commit**

```bash
git add functions/discord.js functions/index.js
git commit -m "feat(discord): auth-start, callback (join+role), and unlink handlers"
```

---

### Task A5: Configure secrets/params + deploy (operator checklist — no code)

**Files:** none (Firebase + Discord console).

- [ ] **Step 1: Create/confirm the Discord OAuth app + bot prerequisites**

  - Bot is a member of the Draw Steel guild with the **Manage Roles** permission.
  - The "linked" role sits **below** the bot's highest role (Discord refuses to assign a role above the bot's own).
  - The OAuth app's redirect URI list includes the callback URL:
    `https://us-central1-mcdm-385cf.cloudfunctions.net/discordAuthCallback`.
  - Note the **Client ID**, **Client Secret**, **Bot Token**, **Guild ID**, and the **linked Role ID**.

- [ ] **Step 2: Set the secrets**

```bash
cd functions
npx firebase functions:secrets:set DISCORD_CLIENT_ID
npx firebase functions:secrets:set DISCORD_CLIENT_SECRET
npx firebase functions:secrets:set DISCORD_BOT_TOKEN
# Generate a random state secret, e.g. `openssl rand -hex 32`, and paste it:
npx firebase functions:secrets:set DISCORD_STATE_SECRET
```

- [ ] **Step 3: Set the params**

```bash
npx firebase functions:params:set DISCORD_CALLBACK_URL="https://us-central1-mcdm-385cf.cloudfunctions.net/discordAuthCallback"
npx firebase functions:params:set DISCORD_APP_ORIGIN="https://seahorse-app-cgk4c.ondigitalocean.app"
npx firebase functions:params:set DISCORD_ALLOWED_ORIGINS="https://seahorse-app-cgk4c.ondigitalocean.app,https://draw-steel-codex.com"
npx firebase functions:params:set DISCORD_GUILD_ID="<guild id>"
npx firebase functions:params:set DISCORD_LINKED_ROLE_ID="<role id>"
```

- [ ] **Step 4: Deploy the three functions**

Deploy gotcha (from project memory): `--only functions:a,b` silently deploys only the first target. Repeat the prefix per function:

```bash
npx firebase deploy --only functions:discordAuthStart --only functions:discordAuthCallback --only functions:discordUnlinkWeb
```

Expected: three functions deploy; their HTTPS URLs are printed.

- [ ] **Step 5: Smoke-test the start endpoint rejects an unauthenticated call**

```bash
curl -s -X POST https://us-central1-mcdm-385cf.cloudfunctions.net/discordAuthStart \
  -H 'Content-Type: application/json' -d '{}'
```

Expected: `{"ok":false,"error":"Missing idToken"}` (proves the function is live and validating).

- [ ] **Step 6: Add the RTDB read rule for `/discordLinks/{uid}`**

In the RTDB rules (same place `patreonLinks` / `shopLinks` are defined), add a sibling rule so a user can read only their own link and clients can't write it:

```json
"discordLinks": {
  "$uid": {
    ".read": "auth != null && auth.uid === $uid",
    ".write": false
  }
}
```

Deploy the rules (`npx firebase deploy --only database`) and confirm in the console.

---

## Phase B — Frontend (`C:\MCDM\draw-steel-companion`)

All Phase B paths are relative to `C:\MCDM\draw-steel-companion`. Tests run with `npm test` (Vitest). Confirm the branch is `main` before each commit (project convention — production drifts mid-session).

### Task B1: Pure link normalizer + avatar URL (TDD)

**Files:**
- Create: `src/account/discordLink.js`
- Test: `src/account/discordLink.test.js`

- [ ] **Step 1: Write the failing test**

Create `src/account/discordLink.test.js`:

```js
import { describe, it, expect } from 'vitest'
import { normalizeDiscordLink, discordAvatarUrl } from './discordLink'

describe('discordAvatarUrl — (discordUserId, avatarHash) → CDN url', () => {
  it('uses the custom avatar when a hash is present', () => {
    expect(discordAvatarUrl('42', 'abc123'))
      .toBe('https://cdn.discordapp.com/avatars/42/abc123.png')
  })

  it('falls back to a default embed avatar when the hash is null', () => {
    // Default index = (snowflake >> 22) % 6. For id "0" that is 0.
    expect(discordAvatarUrl('0', null))
      .toBe('https://cdn.discordapp.com/embed/avatars/0.png')
  })

  it('returns null when there is no user id', () => {
    expect(discordAvatarUrl(null, 'abc')).toBe(null)
  })
})

describe('normalizeDiscordLink — raw /discordLinks/{uid} → { linked, displayName, avatarUrl }', () => {
  it('treats missing / null / non-object as unlinked', () => {
    expect(normalizeDiscordLink(undefined)).toEqual({ linked: false, displayName: null, avatarUrl: null })
    expect(normalizeDiscordLink(null)).toEqual({ linked: false, displayName: null, avatarUrl: null })
    expect(normalizeDiscordLink('nope')).toEqual({ linked: false, displayName: null, avatarUrl: null })
  })

  it('requires a non-empty discordUserId to count as linked', () => {
    expect(normalizeDiscordLink({ username: 'x' })).toEqual({ linked: false, displayName: null, avatarUrl: null })
    expect(normalizeDiscordLink({ discordUserId: '', username: 'x' })).toEqual({ linked: false, displayName: null, avatarUrl: null })
  })

  it('prefers globalName, falls back to username, then a generic label', () => {
    expect(normalizeDiscordLink({ discordUserId: '42', username: 'rune', globalName: 'Rune', avatar: 'h' }))
      .toEqual({ linked: true, displayName: 'Rune', avatarUrl: 'https://cdn.discordapp.com/avatars/42/h.png' })
    expect(normalizeDiscordLink({ discordUserId: '42', username: 'rune', avatar: 'h' }))
      .toEqual({ linked: true, displayName: 'rune', avatarUrl: 'https://cdn.discordapp.com/avatars/42/h.png' })
    expect(normalizeDiscordLink({ discordUserId: '42' }))
      .toEqual({ linked: true, displayName: 'Discord user', avatarUrl: 'https://cdn.discordapp.com/embed/avatars/0.png' })
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/account/discordLink.test.js`
Expected: FAIL — module not found.

- [ ] **Step 3: Write minimal implementation**

Create `src/account/discordLink.js`:

```js
// Pure normalizer for the /discordLinks/{uid} RTDB node into UI-ready state.
// Backend writes: { discordUserId, username, globalName, avatar, linkedAt, updatedAt }.
// A link only "counts" if it carries a discordUserId. Keeping this pure mirrors
// src/shop/shopLink.js so the hook and the UI section agree on meaning.

// Build a Discord CDN avatar URL. With a hash → the user's custom avatar;
// without → Discord's default embed avatar, indexed by (snowflake >> 22) % 6
// (the post-discriminator scheme). Returns null when there's no user id.
export function discordAvatarUrl(discordUserId, avatarHash) {
  if (!discordUserId) return null
  if (avatarHash) return `https://cdn.discordapp.com/avatars/${discordUserId}/${avatarHash}.png`
  let index = 0
  try { index = Number((BigInt(discordUserId) >> 22n) % 6n) } catch { index = 0 }
  return `https://cdn.discordapp.com/embed/avatars/${index}.png`
}

export function normalizeDiscordLink(raw) {
  const unlinked = { linked: false, displayName: null, avatarUrl: null }
  if (!raw || typeof raw !== 'object') return unlinked
  const id = typeof raw.discordUserId === 'string' && raw.discordUserId.length > 0 ? raw.discordUserId : null
  if (!id) return unlinked
  const globalName = typeof raw.globalName === 'string' && raw.globalName.trim() ? raw.globalName.trim() : null
  const username = typeof raw.username === 'string' && raw.username.trim() ? raw.username.trim() : null
  const avatar = typeof raw.avatar === 'string' && raw.avatar ? raw.avatar : null
  return {
    linked: true,
    displayName: globalName || username || 'Discord user',
    avatarUrl: discordAvatarUrl(id, avatar),
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- src/account/discordLink.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/account/discordLink.js src/account/discordLink.test.js
git commit -m "feat(discord): pure /discordLinks normalizer + avatar URL"
```

---

### Task B2: Live link hook

**Files:**
- Create: `src/account/useDiscordLink.js`

- [ ] **Step 1: Write the implementation**

Create `src/account/useDiscordLink.js` (mirrors `src/shop/useShopLink.js` exactly):

```js
import { useEffect, useState } from 'react'
import { ref, onValue } from 'firebase/database'
import { db } from '../firebase'
import { useAuth } from '../auth/AuthProvider'
import { normalizeDiscordLink } from './discordLink'

// Subscribes to the signed-in user's Discord link at /discordLinks/{uid}.
// Only codex-users have a uid to read against; everyone else is unlinked. The
// RTDB rule permits own-uid reads only, so this hook is a pure read consumer —
// it never establishes the link (the backend Function does that). On
// permission/network failure we fall back to unlinked rather than error.
export default function useDiscordLink() {
  const { status, codexUid } = useAuth()
  const [state, setState] = useState({
    linked: false,
    displayName: null,
    avatarUrl: null,
    loading: status === 'loading' || status === 'codex-user',
  })

  useEffect(() => {
    if (status !== 'codex-user' || !codexUid) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- intentional: non-codex users have no /discordLinks node; reset to unlinked
      setState({ linked: false, displayName: null, avatarUrl: null, loading: false })
      return
    }
    setState({ linked: false, displayName: null, avatarUrl: null, loading: true })

    const linkRef = ref(db, `discordLinks/${codexUid}`)
    const unsub = onValue(
      linkRef,
      (snap) => setState({ ...normalizeDiscordLink(snap.val()), loading: false }),
      () => setState({ linked: false, displayName: null, avatarUrl: null, loading: false }),
    )
    return () => unsub()
  }, [status, codexUid])

  return state
}
```

- [ ] **Step 2: Verify it compiles (lint)**

Run: `npm run lint -- src/account/useDiscordLink.js`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add src/account/useDiscordLink.js
git commit -m "feat(discord): live useDiscordLink hook on /discordLinks/{uid}"
```

---

### Task B3: Browser link/unlink helpers

**Files:**
- Create: `src/auth/discord.js`

- [ ] **Step 1: Write the implementation**

Create `src/auth/discord.js` (mirrors `src/auth/patreon.js`):

```js
// Browser-side Discord account-link helpers. The backend Function owns the
// OAuth secret, the bot token, and the code exchange; these helpers only
// (a) ask the Function for the authorize URL and redirect to it, and
// (b) request an unlink. The resulting link state arrives via the live
// useDiscordLink subscription (which reads /discordLinks/{uid}), not here.
import { getAuth } from 'firebase/auth'
import { app as firebaseApp } from '../firebase'
import { postJson } from './platform'

async function currentIdToken() {
  const user = getAuth(firebaseApp).currentUser
  if (!user) throw new Error('Must be signed in to manage your Discord link')
  return user.getIdToken()
}

// Start the Discord OAuth round-trip: POST the Firebase ID token to the start
// Function, then navigate the tab to the returned authorize URL. Discord
// redirects to the Function callback, which joins the guild, grants the role,
// and writes /discordLinks/{uid}; on return the live read flips the UI to
// "Connected". Throws on misconfig / network / backend error.
export async function startDiscordLink() {
  const url = import.meta.env.VITE_DISCORD_AUTH_START_FN_URL
  if (!url) throw new Error('VITE_DISCORD_AUTH_START_FN_URL is not configured')
  const idToken = await currentIdToken()
  const { ok, status, data } = await postJson(url, { idToken })
  if (!ok || !data || data.ok !== true || typeof data.authorizeUrl !== 'string') {
    throw new Error((data && data.error) || `HTTP ${status}`)
  }
  window.location.assign(data.authorizeUrl)
}

// Clear the link. The backend verifies the ID token, removes the linked role in
// Discord, and clears /discordLinks/{uid}; the live read flips the UI back.
export async function unlinkDiscord() {
  const url = import.meta.env.VITE_DISCORD_UNLINK_FN_URL
  if (!url) throw new Error('VITE_DISCORD_UNLINK_FN_URL is not configured')
  const idToken = await currentIdToken()
  const { ok, status, data } = await postJson(url, { idToken })
  if (!ok || !data || data.ok !== true) {
    throw new Error((data && data.error) || `HTTP ${status}`)
  }
}
```

- [ ] **Step 2: Verify it compiles (lint)**

Run: `npm run lint -- src/auth/discord.js`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add src/auth/discord.js
git commit -m "feat(discord): startDiscordLink / unlinkDiscord browser helpers"
```

---

### Task B4: Account-page section + wiring

**Files:**
- Create: `src/account/ConnectDiscordSection.jsx`
- Modify: `src/pages/AccountPage.jsx` (add the import + render after `<ConnectShopifySection />`)
- Modify: `.env` (add the two URLs locally for testing)

- [ ] **Step 1: Create `src/account/ConnectDiscordSection.jsx`**

Modeled on `src/shop/ConnectShopifySection.jsx`, including the `?discord=` return-param read and the `discordConfigured` env gate:

```jsx
import { useEffect, useState } from 'react'
import { useAuth } from '../auth/AuthProvider'
import useDiscordLink from './useDiscordLink'
import { startDiscordLink, unlinkDiscord } from '../auth/discord'

const GOLD = '#c8a45a'
const MUTED = '#8a8a8a'
const TEXT = '#e8e8e8'
const CODEX_GREEN = '#4db88c'
const ERROR_RED = '#d96363'
const SECTION_BORDER = 'rgba(200,164,90,0.15)'
const ROW_BORDER = 'rgba(200,164,90,0.18)'

const sectionStyle = { marginTop: 24, paddingTop: 16, borderTop: `1px solid ${SECTION_BORDER}` }
const h2Style = {
  color: GOLD, fontSize: 13, letterSpacing: '0.1em', textTransform: 'uppercase',
  margin: '0 0 10px', fontFamily: 'Georgia, serif',
}
const bodyTextStyle = { margin: 0, fontSize: 14, color: TEXT }
const mutedTextStyle = { margin: 0, fontSize: 13, color: MUTED }
const greenStyle = { color: CODEX_GREEN }
const errorStyle = { margin: '6px 0 0', fontSize: 13, color: ERROR_RED }
const buttonRowStyle = { display: 'flex', gap: 8, marginTop: 12, flexWrap: 'wrap' }
const buttonBase = {
  padding: '8px 14px', borderRadius: 6, fontSize: 13, fontFamily: 'Georgia, serif',
  cursor: 'pointer', display: 'inline-flex', alignItems: 'center',
}
const buttonPrimary = { ...buttonBase, background: GOLD, color: '#0a0a0b', border: `1px solid ${GOLD}`, fontWeight: 600 }
const buttonOutline = { ...buttonBase, background: 'transparent', color: MUTED, border: `1px solid ${ROW_BORDER}` }
const avatarRow = { display: 'flex', alignItems: 'center', gap: 10 }
const avatarImg = { width: 32, height: 32, borderRadius: '50%', border: `1px solid ${ROW_BORDER}` }

// Gate the connect/disconnect buttons behind the backend being configured. Until
// the Cloud Function URLs are set, fall back to read-only status so production
// never shows a button that errors on click. Mirrors patreonConfigured.
const discordConfigured = Boolean(
  import.meta.env.VITE_DISCORD_AUTH_START_FN_URL && import.meta.env.VITE_DISCORD_UNLINK_FN_URL,
)

export default function ConnectDiscordSection() {
  const { status } = useAuth()
  const { linked, displayName, avatarUrl, loading } = useDiscordLink()
  const [busyAction, setBusyAction] = useState(null)
  const [error, setError] = useState(null)
  const [returnMsg, setReturnMsg] = useState(null)

  // One-shot read of ?discord= on mount, then strip it so a reload doesn't re-show.
  useEffect(() => {
    const param = new URLSearchParams(window.location.search).get('discord')
    if (param === 'linked' || param === 'error') {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- intentional one-shot URL-param read on mount; no external subscription
      setReturnMsg(param)
      const clean = window.location.pathname + window.location.hash
      window.history.replaceState(null, '', clean)
    }
  }, [])

  // Clear stale action error when link state flips.
  // eslint-disable-next-line react-hooks/set-state-in-effect -- intentional stale-error clear on link-state change (repo convention; see useLiveCharacter.js)
  useEffect(() => { setError(null) }, [linked])

  if (status === 'loading' || status === 'error') return null

  async function run(fn, action, navigatesAway = false) {
    setReturnMsg(null)
    setBusyAction(action)
    setError(null)
    try {
      await fn()
      if (navigatesAway) return // startDiscordLink navigates away; keep "Connecting…"
    } catch (e) {
      setError(e?.message || String(e))
    }
    setBusyAction(null)
  }

  let body
  if (status !== 'codex-user') {
    body = <p style={mutedTextStyle}>Link your Codex account to connect Discord.</p>
  } else if (loading) {
    body = <p style={mutedTextStyle}>Checking Discord connection…</p>
  } else if (linked) {
    body = (
      <>
        <div style={avatarRow}>
          {avatarUrl && <img src={avatarUrl} alt="" style={avatarImg} />}
          <p style={bodyTextStyle}>
            Discord · <span style={greenStyle}>Connected{displayName ? ` as ${displayName}` : ''}</span>
          </p>
        </div>
        {discordConfigured && (
          <div style={buttonRowStyle}>
            <button type="button" style={buttonOutline} disabled={busyAction !== null} onClick={() => run(unlinkDiscord, 'disconnect')}>
              {busyAction === 'disconnect' ? 'Disconnecting…' : 'Disconnect'}
            </button>
          </div>
        )}
        {error && <p style={errorStyle}>{error}</p>}
      </>
    )
  } else {
    body = (
      <>
        <p style={mutedTextStyle}>Connect your Discord account to join the Draw Steel server.</p>
        {discordConfigured && (
          <div style={buttonRowStyle}>
            <button type="button" style={buttonPrimary} disabled={busyAction !== null} onClick={() => run(startDiscordLink, 'connect', true)}>
              {busyAction === 'connect' ? 'Connecting…' : 'Connect Discord'}
            </button>
          </div>
        )}
        {error && <p style={errorStyle}>{error}</p>}
      </>
    )
  }

  return (
    <div style={sectionStyle}>
      <h2 style={h2Style}>Discord</h2>
      {returnMsg === 'linked' && <p style={{ ...greenStyle, margin: '0 0 8px', fontSize: 13 }}>Discord connected.</p>}
      {returnMsg === 'error' && <p style={errorStyle}>Discord connection failed.</p>}
      {body}
    </div>
  )
}
```

- [ ] **Step 2: Wire it into `src/pages/AccountPage.jsx`**

Add the import beside the other section imports (after the `ConnectShopifySection` import, ~line 5):

```jsx
import ConnectDiscordSection from '../account/ConnectDiscordSection'
```

And render it after `<ConnectShopifySection />` (~line 288):

```jsx
          <ConnectShopifySection />
          <ConnectDiscordSection />
```

- [ ] **Step 3: Add the local env vars**

Append to `.env` (these point at the deployed Functions; safe to commit nothing here — `.env` is gitignored):

```
VITE_DISCORD_AUTH_START_FN_URL=https://us-central1-mcdm-385cf.cloudfunctions.net/discordAuthStart
VITE_DISCORD_UNLINK_FN_URL=https://us-central1-mcdm-385cf.cloudfunctions.net/discordUnlinkWeb
```

- [ ] **Step 4: Run the full frontend suite + lint + build**

```bash
npm test
npm run lint
npm run build
```

Expected: all green. (`npm run build` is the default companion build; also run `VITE_CODEX_MODE=true npm run build` to confirm the Codex bundle compiles, since the Account page ships there too.)

- [ ] **Step 5: Commit**

```bash
git add src/account/ConnectDiscordSection.jsx src/pages/AccountPage.jsx
git commit -m "feat(discord): Account-page Connect Discord section"
```

---

### Task B5: Live verification (Playwright MCP)

**Files:** none (manual/MCP verification against the running app).

- [ ] **Step 1:** With the backend deployed and the local `.env` set, run `npm run dev` and sign in as a Codex user.

- [ ] **Step 2:** `browser_navigate` to `/more/account`. `browser_snapshot`. Assert a **Discord** section renders with a **Connect Discord** button (not the hidden/unconfigured state).

- [ ] **Step 3:** `browser_click` the **Connect Discord** button. Assert the tab navigates to a `discord.com/oauth2/authorize` URL whose query carries the expected `client_id` and `scope=identify guilds.join` (`browser_network_requests` or the resulting URL).

- [ ] **Step 4:** Complete consent with a test Discord account. Assert the redirect lands back on `/more/account` and the section shows **Connected as `<handle>`** with the avatar, and that the test account now holds the linked role in the Draw Steel server.

- [ ] **Step 5:** `browser_click` **Disconnect**. Assert the section returns to **Connect Discord** and the role is removed from the test account in the server.

- [ ] **Step 6 (only after live verification passes):** Push `main` (auto-deploys DO test) and, when promoting, ff `main` → `production` per `CLAUDE.md`. Decide whether the two `VITE_DISCORD_*_FN_URL` vars are added to the Cloudflare (Codex) build as well — yes, since the Account page ships on Codex too.

---

## Self-Review

**Spec coverage:**
- Frontend `discord.js` / `useDiscordLink` / `ConnectDiscordSection` → Tasks B3 / B2 / B4. ✓
- `discordConfigured` env gate + two `VITE_DISCORD_*_FN_URL` → Task B4. ✓
- Backend `discordAuthStart` / `discordAuthCallback` / `discordUnlinkWeb` + index export → Task A4. ✓
- Scopes `identify`+`guilds.join`, auto guild-join, role grant, token-free record → Tasks A2/A3/A4. ✓
- Secrets/params + deploy gotcha + RTDB rule + Codex-safety note → Task A5 / B5. ✓
- Token never persisted (asserted in A3 test) ✓; link written only after role grant (A4 ordering) ✓.
- Testing: backend pure-helper TDD (A1–A3), frontend pure-module TDD (B1), Playwright (B5). ✓
- YAGNI: no `/discordBindings`, no notifications, no presence — matches spec. ✓

**Placeholder scan:** The only literal placeholders are the operator-supplied `<guild id>` / `<role id>` / secret values in Task A5 (unavoidable — they're real-world credentials the operator pastes in). No "TODO/implement later" code steps; every test and implementation step carries complete code.

**Type consistency:** `parseDiscordUser` → `{ discordUserId, username, globalName, avatar }` is consumed unchanged by `buildLinkUpdates` (A3) and written as the `/discordLinks/{uid}` shape that `normalizeDiscordLink` (B1) reads. `setMemberRole({ method })` is called `PUT` in the callback and `DELETE` in unlink — one function, consistent signature. Hook return `{ linked, displayName, avatarUrl, loading }` matches what `ConnectDiscordSection` destructures.
