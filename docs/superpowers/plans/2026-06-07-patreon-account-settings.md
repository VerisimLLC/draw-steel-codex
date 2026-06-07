# Patreon Status in Settings -> Account Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "DMHub Patreon" subsection to Settings -> Account that shows the user's patron tier (from `dmhub.patronTier`) and, for non-patrons, a "Connect Patreon" button that opens the web companion's account page in the browser.

**Architecture:** Pure client-side display. The engine already syncs the tier from `/Patrons/{uid}` into `dmhub.patronTier`; a `think` handler reflects it live. The connect action is a single `dmhub.OpenURL(...)` to `https://codex.mcdm.com/more/account`, where the authenticated browser OAuth link happens. No Firebase, no OAuth, no secrets in the client.

**Tech Stack:** DMHub Lua + the `gui.*` panel framework. Single file edited: `DMHub Titlescreen/SettingsScreen.lua`.

**Spec:** `docs/superpowers/specs/2026-06-07-patreon-account-settings-design.md`

---

## Important constraints (read before starting)

- **No new Lua files.** All changes go in the existing `DMHub Titlescreen/SettingsScreen.lua`. DMHub's module loader requires file registration; a new file would not load.
- **ASCII-only source.** No em dashes, curly quotes, or ellipses anywhere (comments included).
- **No automated test runner exists** in this repo. Verification is (a) an ASCII/byte scan, (b) an optional Lua syntax parse, and (c) a manual in-app QA checklist.
- **Indentation is mixed in this file.** The top-of-file helpers (e.g. `track`) use **4 spaces**. The Account `SettingGroup` deep in the file uses **tabs**. Match the local style of whatever block you edit. Always `Read` the exact lines before `Edit` so whitespace matches and the `old_string` is unique.
- **Forward-declaration rule:** a `local x = gui.Panel{...}` whose own initializer references `x` must be split into declaration + assignment. The locals in this plan do NOT self-reference in their own initializers (their handlers only touch `dmhub`/`element`), so plain `local x = gui.Label{...}` is fine. The container panel's `think` references them, but it is constructed after they are assigned.

## File structure

| File | Responsibility | Change |
|---|---|---|
| `DMHub Titlescreen/SettingsScreen.lua` | Settings UI incl. the Account tab | Add a tier-label helper near the top; add a Patreon subsection inside `SettingGroup{ group = "Account" }`. |

No other files change. `main.lua` already requires this file.

---

## Task 1: Patreon tier-label helper

Adds a small module-level helper that maps a patron tier integer to a display name, mirroring the companion's source of truth (`draw-steel-companion/src/account/patronTier.js`).

**Files:**
- Modify: `DMHub Titlescreen/SettingsScreen.lua` (top of file, just after the `track` function, ~line 12)

- [ ] **Step 1: Read the anchor**

Read `DMHub Titlescreen/SettingsScreen.lua` lines 1-14 to confirm the `track` function body and its trailing `end` (4-space indentation).

- [ ] **Step 2: Add the helper**

Edit: insert the following immediately AFTER the closing `end` of the `track` function and before `local CreateBetaBranchEditor`. Use 4-space indentation to match the surrounding top-of-file code.

```lua

-- DMHub Patreon (patreon.com/c/dmhub) tier int -> display label.
-- Mirrors draw-steel-companion/src/account/patronTier.js so the desktop app and
-- the web companion label tiers identically. Returns nil for tier 0 / invalid
-- (i.e. "not a patron"), so callers can branch on nil.
local g_patronTierLabels = {
    [1] = "Whelp",
    [2] = "Goblin",
    [3] = "Hobgoblin",
    [4] = "Bugbear",
}

local function PatronTierLabel(tier)
    tier = math.floor(tonumber(tier) or 0)
    if tier <= 0 then
        return nil
    end
    return g_patronTierLabels[tier] or string.format("Tier %d", tier)
end
```

- [ ] **Step 3: ASCII scan**

Run (Bash):
```
python -c "d=open(r'C:\MCDM\draw-steel-codex\DMHub Titlescreen\SettingsScreen.lua','rb').read(); b=[i for i,c in enumerate(d) if c>127]; print('NON-ASCII at:', b[:20]) if b else print('ASCII OK')"
```
Expected: `ASCII OK`

- [ ] **Step 4: Commit**

```
git add "DMHub Titlescreen/SettingsScreen.lua"
git commit -m "feat(patreon): add PatronTierLabel helper to settings screen"
```

---

## Task 2: Patreon subsection in Account settings

Adds the UI. Two edits to the `SettingGroup{ group = "Account" }` block: (A) open the `build` function body and declare the three child elements as locals; (B) insert the container panel that lays them out and drives state from `dmhub.patronTier`.

**Files:**
- Modify: `DMHub Titlescreen/SettingsScreen.lua` (the `SettingGroup{ group = "Account" }` block, ~lines 664-761)

- [ ] **Step 1: Read the anchors**

Read `DMHub Titlescreen/SettingsScreen.lua` lines 664-762. Confirm:
- Line ~666 reads `build = function() return {`
- The Subscription `gui.Panel{ ... }` ends at a line with a single `}` (its own indent), followed by `},` (the Account container panel close) and then `} end,` (the return table + function close).

Note the exact tab indentation of those closing braces; your inserted code must match the sibling level of the Subscription panel.

- [ ] **Step 2 (Edit A): Open the build function and declare the child elements**

Replace the `build = function() return {` line so the function gains a body that declares three locals before returning the table. Match the tab indentation already used inside the `SettingGroup`.

old_string anchor:
```
						build = function() return {

							gui.Panel{
```

new_string:
```
						build = function()

							local patreonStatusLabel = gui.Label{
								fontSize = 14,
								width = "100%",
								maxWidth = 600,
								height = "auto",
								text = "",
							}

							local patreonConnectButton = gui.Button{
								width = 240,
								height = 40,
								fontSize = 20,
								halign = "left",
								vmargin = 4,
								text = "Connect Patreon",
								click = function(element)
									dmhub.OpenURL("https://codex.mcdm.com/more/account")
								end,
							}

							local patreonLinkLabel = gui.Label{
								markdown = true,
								links = true,
								fontSize = 14,
								maxWidth = 600,
								width = "auto",
								height = "auto",
								text = "",
								press = function(element)
									if element.linkHovered ~= nil then
										dmhub.OpenURL(element.linkHovered)
									end
								end,
							}

							return {

							gui.Panel{
```

(If the exact whitespace of the anchor differs in the file, adjust the `old_string` to match what `Read` showed in Step 1; keep the `new_string` structure identical.)

- [ ] **Step 3 (Edit B): Insert the Patreon container panel**

Insert the Patreon panel as the LAST child of the Account container `gui.Panel`, immediately after the Subscription panel's closing brace. Concretely, give the Subscription panel a trailing comma and add the new panel before the container close.

old_string anchor (the Subscription panel close, the container close, and the function close):
```
								}
							},
							} end,
```

new_string:
```
								},

								gui.Panel{
									vmargin = 16,
									flow = "vertical",
									width = "100%",
									height = "auto",

									create = function(element)
										element:FireEvent("think")
									end,
									thinkTime = 0.1,
									think = function(element)
										local tierName = PatronTierLabel(dmhub.patronTier)
										if tierName ~= nil then
											patreonStatusLabel.text = string.format("Patron tier: %s", tierName)
											patreonConnectButton:SetClass("collapsed", true)
											patreonLinkLabel.text = "Manage your membership on <color=#00FFFF><link=https://www.patreon.com/c/dmhub>Patreon</link></color>"
										else
											patreonStatusLabel.text = "Link your Patreon account to unlock patron benefits."
											patreonConnectButton:SetClass("collapsed", false)
											patreonLinkLabel.text = "Support us on <color=#00FFFF><link=https://www.patreon.com/c/dmhub>Patreon</link></color>"
										end
									end,

									gui.Label{
										bold = true,
										fontSize = 16,
										width = "auto",
										height = "auto",
										text = "DMHub Patreon",
									},

									patreonStatusLabel,
									patreonConnectButton,
									patreonLinkLabel,
								},
							},
							} end,
```

(As in Edit A: if the file's whitespace differs from the anchor, match the `old_string` to the real lines from Step 1. The `}` that becomes `},` is the Subscription panel's close; the `},` after the new panel is the unchanged Account-container close.)

- [ ] **Step 4: ASCII scan**

Run (Bash):
```
python -c "d=open(r'C:\MCDM\draw-steel-codex\DMHub Titlescreen\SettingsScreen.lua','rb').read(); b=[i for i,c in enumerate(d) if c>127]; print('NON-ASCII at:', b[:20]) if b else print('ASCII OK')"
```
Expected: `ASCII OK`

- [ ] **Step 5: Optional Lua syntax parse**

If a standalone `luac` is available, run a parse-only check (it will not catch DMHub-specific globals, but it catches brace/paren/`end` mistakes):
```
luac -p "DMHub Titlescreen/SettingsScreen.lua"
```
Expected: no output (success). If `luac` is not installed, skip this step and rely on Step 5 of Task 3 (in-app load).

- [ ] **Step 6: Commit**

```
git add "DMHub Titlescreen/SettingsScreen.lua"
git commit -m "feat(patreon): show patron tier + Connect Patreon in Account settings"
```

---

## Task 3: Verification and manual QA

No automated tests exist; verify by loading the mod in DMHub.

**Files:** none (verification only)

- [ ] **Step 1: Confirm the file still parses on load**

Launch DMHub with the codex mod loaded. Confirm there is no Lua load error referencing `SettingsScreen.lua` (a syntax or brace error here would fail the module load).

- [ ] **Step 2: Open the section**

Open Settings, select the **Account** tab. Confirm a **"DMHub Patreon"** subsection appears below the (collapsed) Subscription block.

- [ ] **Step 3: Non-patron state (`dmhub.patronTier == 0`)**

With a non-patron account, confirm:
- Status line reads: *"Link your Patreon account to unlock patron benefits."*
- A **"Connect Patreon"** button is visible.
- A link reads *"Support us on Patreon"*.
- Clicking **Connect Patreon** opens the system browser to `https://codex.mcdm.com/more/account`.
- Clicking the **Patreon** link opens `https://www.patreon.com/c/dmhub`.

- [ ] **Step 4: Patron state (`dmhub.patronTier > 0`)**

Verify with an account that has a patron tier (or temporarily test by an account known to return a non-zero `dmhub.patronTier`). Confirm:
- Status line reads: *"Patron tier: <Name>"* with the correct name (1=Whelp, 2=Goblin, 3=Hobgoblin, 4=Bugbear).
- The **Connect Patreon** button is hidden.
- The link reads *"Manage your membership on Patreon"* and opens `https://www.patreon.com/c/dmhub`.

Note: if no patron account is readily available, document that Step 4 was verified by code inspection only, and confirm the live path once a patron account is available. Do not claim it passed without evidence.

- [ ] **Step 5: Live update (optional but preferred)**

If the tier can be changed for the test account while the panel is open, confirm the section switches between the two states within ~1 second without reopening Settings (the `thinkTime = 0.1` handler).

---

## Self-review notes (author)

- **Spec coverage:** location (Account SettingGroup) -> Task 2; data source `dmhub.patronTier` via `think`/`thinkTime=0.1` -> Task 2 Step 3; tier-label map mirroring companion -> Task 1; both states (tier>0 / ==0) -> Task 2 Step 3 + Task 3 Steps 3-4; connect via `dmhub.OpenURL("https://codex.mcdm.com/more/account")` -> Task 2 Step 2; support/manage link to `patreon.com/c/dmhub` -> Task 2 Step 3; DMHub-only scope (no MCDM) -> honored (single tier shown); constraints (no new file, ASCII, forward-decl) -> constraints section + Task steps. All spec sections map to a task.
- **Naming consistency:** `PatronTierLabel` (Task 1) is the exact symbol called in Task 2 Step 3. Element locals `patreonStatusLabel` / `patreonConnectButton` / `patreonLinkLabel` are declared in Edit A and referenced by the same names in Edit B.
- **No placeholders:** every code step shows complete code; verification steps show exact commands and expected output.
