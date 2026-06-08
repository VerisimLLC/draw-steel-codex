# Shopify in Codex Account (SP-A + SP-B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Shopify connect/disconnect/status section to the codex Settings > Account, served by dual-auth Cloud Functions (so the desktop `net.Post` works alongside the existing browser flow). Purchases list (SP-C) deferred.

**Architecture:** SP-A refactors `shopify.js` so `shopifyUnlink` + a new `shopifyStatus` accept EITHER a browser idToken OR desktop `{userid, secretid}` via a shared `resolveUid`. SP-B adds a Lua section that fetches status via `net.Post` on panel open (async; not the `think` loop), opens the browser to connect, and disconnects in-app with an inline confirm.

**Tech Stack:** Node 20 ESM + `firebase-functions` v2 + `node:test` (SP-A, repo `dmhubclient/cloud-functions`); DMHub Lua + `gui.*` (SP-B, repo `draw-steel-codex`).

**Spec:** `draw-steel-codex/docs/superpowers/specs/2026-06-08-shopify-codex-account-design.md`

---

## Important context

- **SP-A repo:** `C:\MCDM\dmhubclient\cloud-functions`. Branch off `master`: `git checkout -b shopify-dual-auth master`. Test: `npm test` (from `functions/`) runs `node --test`. Style: ESM, 2-space, single quotes, no semicolons (match `shopify.js`).
- **SP-B repo:** `C:\MCDM\draw-steel-codex`, branch `shopify-codex-account` (already exists, the spec is on it). NO test runner; verify by ASCII scan + manual QA. ASCII-only; no new Lua files; forward-declare self-referencing locals; tab indentation in the Account `SettingGroup`.
- `shopify.js` facts: `uidFromBody(req,res)` (idToken-only) at ~line 180; `FIREBASE_UID_RE`, `CUSTOMER_GID_RE`, `bad(res,msg,code)`, `setCors`, `getDatabase`, `logger` all already defined; `shopifyUnlink` at ~line 312 (`{ secrets: ADMIN_SECRETS }`); `index.js` line 25 exports the shopify functions. Handlers are NOT unit-tested (only pure/injected helpers are - mirror that).
- Function URLs after deploy: `https://us-central1-mcdm-385cf.cloudfunctions.net/shopifyStatus` etc.

## File structure

| File | Responsibility | Change |
|---|---|---|
| `cloud-functions/functions/shopify.js` | Shopify functions | Add `resolveUid` + `shopLinkStatus` + `shopifyStatus`; refactor `shopifyUnlink` |
| `cloud-functions/functions/shopify-auth.test.js` | Unit tests for `resolveUid` + `shopLinkStatus` | Create |
| `cloud-functions/functions/index.js` | Re-export | Add `shopifyStatus` |
| `draw-steel-codex/DMHub Titlescreen/SettingsScreen.lua` | Account settings UI | Add Shopify section |

---

# SP-A - Backend (build first; repo dmhubclient/cloud-functions, branch shopify-dual-auth)

## Task A1: `shopLinkStatus` + `resolveUid` (TDD)

**Files:** Modify `functions/shopify.js`; Create `functions/shopify-auth.test.js`

- [ ] **Step 1: Write the failing tests** (`functions/shopify-auth.test.js`)

```javascript
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { shopLinkStatus, resolveUid } from './shopify.js'

// --- shopLinkStatus (pure) ---
test('shopLinkStatus: linked with email', () => {
  assert.deepEqual(shopLinkStatus({ customerId: 'gid://shopify/Customer/1', email: 'a@b.c' }),
    { linked: true, email: 'a@b.c' })
})
test('shopLinkStatus: linked, missing/blank email -> null', () => {
  assert.deepEqual(shopLinkStatus({ customerId: 'gid://shopify/Customer/1' }), { linked: true, email: null })
  assert.deepEqual(shopLinkStatus({ customerId: 'gid://shopify/Customer/1', email: '  ' }), { linked: true, email: null })
})
test('shopLinkStatus: no customerId / garbage -> not linked', () => {
  assert.deepEqual(shopLinkStatus({ email: 'a@b.c' }), { linked: false, email: null })
  assert.deepEqual(shopLinkStatus(null), { linked: false, email: null })
})

// --- resolveUid (injected auth + db) ---
function fakeRes() {
  return { code: null, body: null, status(c) { this.code = c; return this }, json(b) { this.body = b; return this } }
}
const okAuth = { verifyIdToken: async (t) => ({ uid: t === 'good' ? 'uid-1' : 'bad uid!' }) }
const denyAuth = { verifyIdToken: async () => { throw new Error('nope') } }
const dbWith = (stored) => ({ readSecretId: async () => ({ exists: () => stored != null, val: () => stored }) })

test('resolveUid: valid idToken -> uid', async () => {
  const res = fakeRes()
  assert.equal(await resolveUid({ body: { idToken: 'good' } }, res, { ...okAuth, ...dbWith(null) }), 'uid-1')
})
test('resolveUid: idToken with bad uid format -> 401 null', async () => {
  const res = fakeRes()
  assert.equal(await resolveUid({ body: { idToken: 'weird' } }, res, { ...okAuth, ...dbWith(null) }), null)
  assert.equal(res.code, 401)
})
test('resolveUid: rejected idToken -> 401 null', async () => {
  const res = fakeRes()
  assert.equal(await resolveUid({ body: { idToken: 'x' } }, res, { ...denyAuth, ...dbWith(null) }), null)
  assert.equal(res.code, 401)
})
test('resolveUid: matching userid+secretid -> uid', async () => {
  const res = fakeRes()
  assert.equal(await resolveUid({ body: { userid: 'uid-2', secretid: 's3cr3t' } }, res, { ...okAuth, ...dbWith('s3cr3t') }), 'uid-2')
})
test('resolveUid: secretid mismatch -> 403 null', async () => {
  const res = fakeRes()
  assert.equal(await resolveUid({ body: { userid: 'uid-2', secretid: 'wrong' } }, res, { ...okAuth, ...dbWith('s3cr3t') }), null)
  assert.equal(res.code, 403)
})
test('resolveUid: bad userid format -> 400 null', async () => {
  const res = fakeRes()
  assert.equal(await resolveUid({ body: { userid: 'bad uid!', secretid: 's' } }, res, { ...okAuth, ...dbWith('s') }), null)
  assert.equal(res.code, 400)
})
test('resolveUid: no credentials -> 400 null', async () => {
  const res = fakeRes()
  assert.equal(await resolveUid({ body: {} }, res, { ...okAuth, ...dbWith(null) }), null)
  assert.equal(res.code, 400)
})
```

- [ ] **Step 2: Run to confirm failure**

Run: `node --test functions/shopify-auth.test.js`
Expected: FAIL (`shopLinkStatus` / `resolveUid` not exported).

- [ ] **Step 3: Implement in `shopify.js`** (add after the existing `uidFromBody`, ~line 198)

```javascript
// Pure: shape a /shopLinks/{uid} snapshot value into { linked, email }.
export function shopLinkStatus(raw) {
  if (!raw || typeof raw !== 'object') return { linked: false, email: null }
  const linked = typeof raw.customerId === 'string' && raw.customerId.length > 0
  const email = linked && typeof raw.email === 'string' && raw.email.trim() ? raw.email.trim() : null
  return { linked, email }
}

// Resolve the caller's uid from EITHER a browser idToken OR desktop {userid, secretid}.
// Deps are injectable for unit tests; default to the live Admin SDK.
export async function resolveUid(req, res, deps = {}) {
  const verifyIdToken = deps.verifyIdToken || ((t) => getAuth().verifyIdToken(t))
  const readSecretId = deps.readSecretId || ((uid) => getDatabase().ref(`/users/${uid}/secretid`).get())
  const body = req.body || {}

  if (typeof body.idToken === 'string' && body.idToken) {
    try {
      const decoded = await verifyIdToken(body.idToken)
      if (!FIREBASE_UID_RE.test(decoded.uid || '')) { bad(res, 'invalid-id-token', 401); return null }
      return decoded.uid
    } catch (err) {
      logger.warn('shopify: verifyIdToken rejected', err?.message || err)
      bad(res, 'invalid-id-token', 401); return null
    }
  }

  if (typeof body.userid === 'string' && body.userid && typeof body.secretid === 'string' && body.secretid) {
    if (!FIREBASE_UID_RE.test(body.userid)) { bad(res, 'invalid userid', 400); return null }
    const snap = await readSecretId(body.userid)
    if (snap.exists() && snap.val() === body.secretid) return body.userid
    bad(res, 'Your account could not be validated.', 403); return null
  }

  bad(res, 'Missing credentials', 400); return null
}
```

Note: `getAuth` is already imported in `shopify.js`. Keep `uidFromBody` as-is (still used by `shopifyAuthStart`).

- [ ] **Step 4: Run to confirm pass**

Run: `node --test functions/shopify-auth.test.js`
Expected: PASS (all).

- [ ] **Step 5: Full suite (no regressions)**

Run: `npm test`
Expected: all pass (existing shopify/patreon tests + the new ones).

- [ ] **Step 6: Commit**

```
git add functions/shopify.js functions/shopify-auth.test.js
git commit -m "feat(shopify): resolveUid dual-auth + shopLinkStatus helper (TDD)"
```

## Task A2: `shopifyStatus` endpoint + export

**Files:** Modify `functions/shopify.js`, `functions/index.js`

- [ ] **Step 1: Add `shopifyStatus` in `shopify.js`** (near `shopifyUnlink`, ~line 310)

```javascript
// --- shopifyStatus ------------------------------------------------------------
// POST (idToken OR {userid,secretid}) -> { ok, linked, email }. The codex reads
// this via net.Post; the companion reads /shopLinks directly, but this works for both.
export const shopifyStatus = onRequest(async (req, res) => {
  setCors(res, req.get('Origin') || '')
  if (req.method === 'OPTIONS') return res.status(204).send('')
  if (req.method !== 'POST') return bad(res, 'Method not allowed', 405)
  try {
    const uid = await resolveUid(req, res)
    if (!uid) return
    const snap = await getDatabase().ref(`shopLinks/${uid}`).get()
    const { linked, email } = shopLinkStatus(snap.exists() ? snap.val() : null)
    return res.status(200).json({ ok: true, linked, email })
  } catch (err) {
    logger.error('shopifyStatus error', err)
    return bad(res, 'Internal error', 500)
  }
})
```

- [ ] **Step 2: Export from `index.js`** (line 25)

Change the shopify export line to include `shopifyStatus`:
```javascript
export { shopifyAuthStart, shopifyAuthCallback, shopifyUnlink, shopifyStatus, shopifyOrders } from "./shopify.js";
```

- [ ] **Step 3: Verify import + suite**

Run: `node --input-type=module -e "await import('./functions/index.js'); console.log('OK')"` then `npm test`
Expected: `OK`, then all tests pass. (Note: if `index.js` has a pre-existing module-level `getDatabase()` that needs a real URL, the import check may warn - that predates this work; instead verify `await import('./functions/shopify.js')` prints OK.)

- [ ] **Step 4: Commit**

```
git add functions/shopify.js functions/index.js
git commit -m "feat(shopify): shopifyStatus endpoint (dual-auth link status)"
```

## Task A3: `shopifyUnlink` -> dual-auth

**Files:** Modify `functions/shopify.js`

- [ ] **Step 1: Read the current `shopifyUnlink`**

Read `functions/shopify.js` around line 312-348. Confirm it calls `const uid = await uidFromBody(req, res)`.

- [ ] **Step 2: Swap the auth call**

In `shopifyUnlink`, change:
```javascript
    const uid = await uidFromBody(req, res)
    if (!uid) return
```
to:
```javascript
    const uid = await resolveUid(req, res)
    if (!uid) return
```
Leave everything else (the `/shopLinks/{uid}` + `/shopCustomerLinks/{numericId}` clear, the `annotateShopifyCustomer('disconnect')`, `{ ok: true }`) unchanged.

- [ ] **Step 3: Full suite (existing tests unaffected)**

Run: `npm test`
Expected: all pass. (The shopify handler tests don't exercise `shopifyUnlink`'s auth directly, so behavior for idToken callers is unchanged.)

- [ ] **Step 4: Commit**

```
git add functions/shopify.js
git commit -m "feat(shopify): shopifyUnlink accepts desktop secretid auth (dual-auth)"
```

## SP-A deploy (after review; needs no new owner inputs)

```
npx firebase deploy --only functions:shopifyStatus,functions:shopifyUnlink
```
Smoke-test (non-destructive):
```
curl -sS -o /dev/null -w "%{http_code}\n" -X POST https://us-central1-mcdm-385cf.cloudfunctions.net/shopifyStatus -H "Content-Type: application/json" -d '{}'
```
Expected: `400` (Missing credentials) - confirms live. `shopifyUnlink` should still answer for the companion's idToken calls.

---

# SP-B - Codex Shopify section (repo draw-steel-codex, branch shopify-codex-account)

## Task B1: Add the Shopify section to `SettingsScreen.lua`

**Files:** Modify `DMHub Titlescreen/SettingsScreen.lua`

The Account `SettingGroup` already has a Patreon section (forward-declared locals before `return {`, a gated container panel as a child). Add a Shopify section the same way, AFTER the Patreon container panel in the children list. `g_devStorePreviewSetting` already exists (declared for the Patreon gate) - reuse it.

- [ ] **Step 1: Read the anchors**

Read the Account `SettingGroup` build function in `DMHub Titlescreen/SettingsScreen.lua` (search `group = "Account"`). Note: the forward-declaration block (where `patreonStatusLabel` etc. are declared), and the Patreon container panel's closing `},` in the children list (you'll insert the Shopify panel right after it).

- [ ] **Step 2: Add forward declarations** (in the same block as the `patreon*` forward-decls, before `return {`)

```lua
							local shopifyStatusLabel
							local shopifyConnectButton
							local shopifyDisconnectButton
							local shopifyConfirmPanel
							local shopifyConfirmButton
							local shopifyErrorLabel
							local shopifyRefreshButton
							local RefreshShopifyStatus
```

- [ ] **Step 3: Assign the elements + the fetch function** (after the forward-decl block, before `return {`; match tab indentation)

```lua
							shopifyStatusLabel = gui.Label{
								fontSize = 14, width = "100%", maxWidth = 600, height = "auto",
								text = "Checking Shopify...",
							}

							shopifyErrorLabel = gui.Label{
								classes = {"collapsed"},
								fontSize = 14, color = "#ff6666", width = "auto", height = "auto", text = "",
							}

							shopifyConnectButton = gui.Button{
								classes = {"collapsed"},
								width = 240, height = 40, fontSize = 20, halign = "left", vmargin = 4,
								text = "Connect Shopify",
								click = function(element)
									dmhub.OpenURL("https://draw-steel-codex.com/more/account")
								end,
							}

							shopifyDisconnectButton = gui.Button{
								classes = {"collapsed"},
								width = 240, height = 40, fontSize = 20, halign = "left", vmargin = 4,
								text = "Disconnect",
								click = function(element)
									shopifyDisconnectButton:SetClass("collapsed", true)
									shopifyConfirmPanel:SetClass("collapsed", false)
									shopifyErrorLabel:SetClass("collapsed", true)
								end,
							}

							shopifyConfirmButton = gui.Button{
								width = 180, height = 36, fontSize = 16, halign = "left", vmargin = 4,
								text = "Confirm Disconnect",
								click = function(element)
									element.text = "Disconnecting..."
									element.interactable = false
									shopifyErrorLabel:SetClass("collapsed", true)
									net.Post{
										url = dmhub.cloudFunctionsBaseUrl .. "/shopifyUnlink",
										data = {},
										success = function(data)
											element.text = "Confirm Disconnect"
											element.interactable = true
											shopifyConfirmPanel:SetClass("collapsed", true)
											RefreshShopifyStatus()
										end,
										error = function(msg)
											element.text = "Confirm Disconnect"
											element.interactable = true
											shopifyErrorLabel.text = "Disconnect failed: " .. tostring(msg)
											shopifyErrorLabel:SetClass("collapsed", false)
										end,
									}
								end,
							}

							shopifyConfirmPanel = gui.Panel{
								classes = {"collapsed"},
								flow = "vertical", width = "auto", height = "auto", vmargin = 4,
								gui.Label{
									fontSize = 14, maxWidth = 600, width = "100%", height = "auto",
									text = "Disconnect your Shopify account?",
								},
								gui.Panel{
									flow = "horizontal", width = "auto", height = "auto",
									shopifyConfirmButton,
									gui.Button{
										width = 120, height = 36, fontSize = 16, halign = "left", vmargin = 4, hmargin = 8,
										text = "Cancel",
										click = function(element)
											shopifyConfirmPanel:SetClass("collapsed", true)
											shopifyDisconnectButton:SetClass("collapsed", false)
										end,
									},
								},
							}

							shopifyRefreshButton = gui.Button{
								classes = {"collapsed"},
								width = 120, height = 30, fontSize = 14, halign = "left", vmargin = 4,
								text = "Refresh",
								click = function(element)
									RefreshShopifyStatus()
								end,
							}

							-- Fetch link status from the backend (Lua cannot read /shopLinks directly).
							-- Called on panel create, on Refresh, and after a successful disconnect.
							RefreshShopifyStatus = function()
								shopifyStatusLabel.text = "Checking Shopify..."
								shopifyConnectButton:SetClass("collapsed", true)
								shopifyDisconnectButton:SetClass("collapsed", true)
								shopifyConfirmPanel:SetClass("collapsed", true)
								shopifyRefreshButton:SetClass("collapsed", true)
								shopifyErrorLabel:SetClass("collapsed", true)
								net.Post{
									url = dmhub.cloudFunctionsBaseUrl .. "/shopifyStatus",
									data = {},
									success = function(data)
										shopifyRefreshButton:SetClass("collapsed", false)
										if type(data) ~= "table" or not data.ok then
											shopifyStatusLabel.text = "Could not load Shopify status."
											return
										end
										if data.linked then
											shopifyStatusLabel.text = (data.email ~= nil and data.email ~= "")
												and string.format("Shopify: Connected as %s", data.email)
												or "Shopify: Connected"
											shopifyDisconnectButton:SetClass("collapsed", false)
										else
											shopifyStatusLabel.text = "Connect your Shopify account to link your purchases."
											shopifyConnectButton:SetClass("collapsed", false)
										end
									end,
									error = function(msg)
										shopifyRefreshButton:SetClass("collapsed", false)
										shopifyStatusLabel.text = "Could not load Shopify status."
										shopifyErrorLabel.text = "Error: " .. tostring(msg)
										shopifyErrorLabel:SetClass("collapsed", false)
									end,
								}
							end
```

- [ ] **Step 4: Add the container panel as a child** (in the returned children list, immediately AFTER the Patreon container panel's closing `},`)

```lua
								gui.Panel{
									vmargin = 16,
									classes = { cond(not g_devStorePreviewSetting:Get(), "collapsed") },
									flow = "vertical",
									width = "100%",
									height = "auto",

									create = function(element)
										RefreshShopifyStatus()
									end,

									gui.Label{
										bold = true, fontSize = 16, width = "auto", height = "auto",
										text = "Shopify",
									},
									shopifyStatusLabel,
									shopifyConnectButton,
									shopifyDisconnectButton,
									shopifyConfirmPanel,
									shopifyRefreshButton,
									shopifyErrorLabel,
								},
```

- [ ] **Step 5: ASCII scan**

Run (Bash): `python -c "d=open(r'C:\MCDM\draw-steel-codex\DMHub Titlescreen\SettingsScreen.lua','rb').read(); b=[i for i,c in enumerate(d) if c>127]; print('NON-ASCII',b[:10]) if b else print('ASCII OK')"`
Expected: `ASCII OK`

- [ ] **Step 6: Brace/structure sanity**

Read the edited region. Confirm: every `gui.Panel{`/`gui.Button{`/`gui.Label{` is balanced; the forward-declared locals are all assigned before the container panel references them; the build function still ends `return { ... } end,`; the new container is a sibling of the Patreon container in the children list. If `luac` is installed, run `luac -p "DMHub Titlescreen/SettingsScreen.lua"` (else skip).

- [ ] **Step 7: Commit**

```
git add "DMHub Titlescreen/SettingsScreen.lua"
git commit -m "feat(shopify): add Shopify connect/disconnect/status section to Account settings"
```

## SP-B manual QA (requires DMHub + SP-A deployed)

1. Enable the shop testing flag (`dev:storepreview`). Open Settings > Account. A "Shopify" section appears after the Patreon section.
2. On open it shows "Checking Shopify..." then resolves to one of:
   - Not linked: "Connect your Shopify account..." + **Connect Shopify** (opens browser to draw-steel-codex.com/more/account) + **Refresh**.
   - Linked: "Shopify: Connected as \<email\>" + **Disconnect** + **Refresh**.
3. Disconnect -> confirm row (Cancel / Confirm Disconnect). Confirm -> "Disconnecting..." -> on success the status re-fetches and flips to not-linked.
4. After connecting in the browser, click **Refresh** (or reopen Settings) -> shows linked.
5. With the flag OFF, the whole Shopify section is hidden.

---

## Self-review notes (author)

- **Spec coverage:** dual-auth resolver (S4a) -> A1; shopifyStatus (S4b) -> A2; shopifyUnlink dual-auth (S4c) -> A3; shopifyOrders untouched (S4d) -> not in plan (correct); index export -> A2; tests -> A1; deploy -> SP-A deploy block; codex section gated by dev:storepreview, fetch-on-open + Refresh, connect-opens-browser, disconnect inline-confirm (S5) -> B1; companion untouched (S6) -> no companion task. All in-scope spec items map to a task.
- **Naming consistency:** `resolveUid`, `shopLinkStatus`, `shopifyStatus` defined in A1/A2 and used consistently. Lua: `RefreshShopifyStatus`, `shopify*` locals all forward-declared in B1 Step 2 and referenced by the same names in Steps 3-4. `dmhub.cloudFunctionsBaseUrl .. "/shopifyStatus"` / `"/shopifyUnlink"` match the deployed names.
- **No placeholders:** every code step has complete code; test/verify steps give exact commands + expected output.
- **Deferred:** SP-C (shopifyOrders dual-auth + Lua purchases list) is explicitly out of this plan.
