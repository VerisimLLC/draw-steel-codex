local mod = dmhub.GetModLoading()

--Hero modules: modules of hero options (classes, ancestries, kits) that a
--player builds heroes with. A free one is used once the player adds it (Browse
--Free Items) and stops being used when they remove it. A premium one the player
--owns is used unless they switch it off on its store item's details page.
--An enabled one is installed into the lobby game, where heroes are built,
--through ModuleLua:InstallAsHeroModule, which only uses versions whose code an
--admin approved. A disabled one is uninstalled from the lobby so its code stops
--running too.
--
--The inventory is an account setting, so it follows the player between
--machines (the lobby game itself is stored locally on each machine):
--  { [moduleid] = { enabled = boolean, added = unix time } }
--A free module has an entry while added (added > 0) and is always enabled. An
--owned premium module needs no entry; SetEnabled writes one with added = 0.
local g_heroModulesSetting = setting{
	id = "heromodules",
	description = "Hero Modules",
	storage = "account",
	default = {},
}

--- @class HeroModuleEntry
--- @field enabled boolean
--- @field added number

--- @class HeroModuleItem
--- @field module ModuleLua
--- @field enabled boolean
--- @field added boolean True for a free module the player added; false for an owned premium module.

--- @return table<string, HeroModuleEntry>
local function GetEntries()
	local result = {}
	local stored = g_heroModulesSetting:Get()
	if type(stored) == "table" then
		for k, v in pairs(stored) do
			if type(k) == "string" and type(v) == "table" then
				result[k] = { enabled = v.enabled ~= false, added = tonumber(v.added) or 0 }
			end
		end
	end
	return result
end

--Shared with the titlescreen and the shop (other files of the core codex).
HeroModules = {}

--Panels showing the inventory, told to refresh with a "heroModulesChanged"
--event when it changes or a lobby sync finishes. Weak, so a closed screen's
--panels just drop out. Each is tagged with the game it was made in: a panel
--left over from another game (the store, after entering a campaign) is
--dropped without being touched, since even reading .valid on it errors.
--- @type table<Panel, string>
local g_listeners = setmetatable({}, { __mode = "k" })

--- Registers a panel to receive a "heroModulesChanged" event whenever the
--- inventory changes or a lobby sync finishes (install errors may have changed).
--- @param element Panel
function HeroModules.Listen(element)
	g_listeners[element] = dmhub.gameid or ""
end

local function NotifyChanged()
	local gameid = dmhub.gameid or ""
	for element, listenerGame in pairs(g_listeners) do
		if listenerGame == gameid and element.valid then
			element:FireEvent("heroModulesChanged")
		else
			g_listeners[element] = nil
		end
	end
end

--- @param entries table<string, HeroModuleEntry>
local function SetEntries(entries)
	--a fresh table every time: the setting layer compares by identity.
	g_heroModulesSetting:Set(entries)
	NotifyChanged()
end

--- True if the player added this (free) module.
--- @param moduleid string
--- @return boolean
function HeroModules.IsAdded(moduleid)
	local entry = GetEntries()[moduleid]
	return entry ~= nil and entry.added > 0
end

--- True unless the player switched this module off. An added module is always
--- on: removing it is how it stops applying. Only meaningful for a module in
--- the inventory.
--- @param moduleid string
--- @return boolean
function HeroModules.IsEnabled(moduleid)
	local entry = GetEntries()[moduleid]
	return entry == nil or entry.enabled or entry.added > 0
end

--- Adds a module to the inventory, enabled, and brings it into the lobby.
--- @param moduleid string
function HeroModules.Add(moduleid)
	local entries = GetEntries()
	entries[moduleid] = { enabled = true, added = os.time() }
	SetEntries(entries)
	HeroModules.SyncLobby()
end

--- Removes a module the player added, so it no longer applies. An owned
--- premium module stays in the inventory; use SetEnabled to switch it off.
--- @param moduleid string
function HeroModules.Remove(moduleid)
	local entries = GetEntries()
	entries[moduleid] = nil
	SetEntries(entries)
	HeroModules.SyncLobby()
end

--- Switches an owned premium module on or off for the player's heroes.
--- @param moduleid string
--- @param enabled boolean
function HeroModules.SetEnabled(moduleid, enabled)
	local entries = GetEntries()
	entries[moduleid] = { enabled = enabled, added = 0 }
	SetEntries(entries)
	HeroModules.SyncLobby()
end

--- Downloads fresh records for every module in the inventory: the ones the
--- player added, plus the premium Hero modules they own. Calls back once with
--- the list, sorted by name. A module whose record can't be downloaded is left
--- out of this list but stays in the inventory.
--- @param callback fun(items: HeroModuleItem[])
function HeroModules.CollectInventory(callback)
	local entries = GetEntries()

	--moduleid -> true if the player added it.
	local ids = {}
	for id, entry in pairs(entries) do
		if entry.added > 0 then
			ids[id] = true
		end
	end
	for _, list in ipairs({ module.GetOurPurchasedModules(), module.GetOurPatreonModules() }) do
		for _, id in ipairs(list) do
			if ids[id] == nil then
				ids[id] = false
			end
		end
	end

	local items = {}
	local pending = 0
	local finished = false

	local Finish = function()
		if pending > 0 or finished then
			return
		end
		finished = true
		table.sort(items, function(a, b)
			return string.lower(a.module.name or "") < string.lower(b.module.name or "")
		end)
		callback(items)
	end

	for id, added in pairs(ids) do
		pending = pending + 1
		module.DownloadModuleInfo{
			moduleid = id,
			success = function(info)
				--a purchased module counts only if it is a Hero module the player
				--owns. An added free module is always on; premium ones are never
				--"added" (an older entry may still carry an added time).
				local playerAdded = added and not info.premium
				if info.isHeroModule and (playerAdded or info.owned) then
					local entry = entries[id]
					items[#items+1] = {
						module = info,
						enabled = playerAdded or entry == nil or entry.enabled,
						added = playerAdded,
					}
				end
				pending = pending - 1
				Finish()
			end,
			failure = function(message)
				print(string.format("HeroModules: could not download module %s: %s", id, tostring(message)))
				pending = pending - 1
				Finish()
			end,
		}
	end

	Finish()
end

--A CollectInventory started ahead of InstallIntoGame (see PrefetchInventory),
--for this game only: { gameid, items = nil until it lands, waiters }.
local g_inventoryPrefetch = nil

--- Starts collecting the inventory for a coming InstallIntoGame in this game,
--- so the install does not then wait on the module-info downloads (one per
--- owned or added module, 0.1-3 s together). An Encounter of the Week arrival
--- calls it first thing, so the downloads overlap the map travel. The next
--- InstallIntoGame in this game uses the result (waiting for it if needed);
--- any later one collects afresh.
function HeroModules.PrefetchInventory()
	if dmhub.isLobbyGame or not dmhub.inGame then
		return
	end
	local prefetch = { gameid = dmhub.gameid, items = nil, waiters = {} }
	g_inventoryPrefetch = prefetch
	HeroModules.CollectInventory(function(items)
		prefetch.items = items
		local waiters = prefetch.waiters
		prefetch.waiters = {}
		for _, waiter in ipairs(waiters) do
			waiter(items)
		end
	end)
end

--CollectInventory, or the prefetched result for this game when there is one.
local function CollectInventoryForInstall(callback)
	local prefetch = g_inventoryPrefetch
	g_inventoryPrefetch = nil
	if prefetch == nil or prefetch.gameid ~= dmhub.gameid then
		HeroModules.CollectInventory(callback)
	elseif prefetch.items ~= nil then
		callback(prefetch.items)
	else
		prefetch.waiters[#prefetch.waiters + 1] = callback
	end
end

--moduleid -> the last error installing it into the lobby, for the inventory
--UI to show (e.g. "waiting for review by an admin").
local g_lastErrors = {}

--- The last error from bringing this module into the lobby, or nil.
--- @param moduleid string
--- @return nil|string
function HeroModules.GetError(moduleid)
	return g_lastErrors[moduleid]
end

local g_syncing = false
local g_syncAgain = false

--- Brings the lobby game in line with the inventory: installs each enabled
--- Hero module the player may use and uninstalls the rest. Only acts in the
--- lobby game. Installs run one at a time; a call made while a sync is running
--- queues one more pass.
function HeroModules.SyncLobby()
	if not dmhub.isLobbyGame then
		return
	end
	if g_syncing then
		g_syncAgain = true
		return
	end
	g_syncing = true

	HeroModules.CollectInventory(function(items)
		if mod.unloaded or not dmhub.isLobbyGame then
			g_syncing = false
			return
		end

		--each step is a function(next) that calls next() when done.
		local steps = {}
		local wanted = {}
		for _, item in ipairs(items) do
			local info = item.module
			local fullid = info.fullid
			local usable = (not info.premium) or info.owned
			if item.enabled and usable then
				wanted[fullid] = true
				steps[#steps+1] = function(nextStep)
					if info.isdisabled then
						info:SetDisabled(false)
					end
					info:InstallAsHeroModule{
						success = function()
							g_lastErrors[fullid] = nil
							nextStep()
						end,
						error = function(message)
							g_lastErrors[fullid] = message
							print(string.format("HeroModules: %s not installed in the lobby: %s", fullid, message))
							nextStep()
						end,
					}
				end
			end
		end

		--Hero modules installed in the lobby that the inventory no longer wants.
		for _, info in ipairs(module.GetLoadedModules()) do
			local fullid = info.fullid
			if info.isHeroModule and info.installedVersion ~= nil and not wanted[fullid] then
				steps[#steps+1] = function(nextStep)
					g_lastErrors[fullid] = nil
					info:Uninstall{}
					nextStep()
				end
			end
		end

		local index = 0
		local RunNext
		RunNext = function()
			if mod.unloaded then
				g_syncing = false
				return
			end
			index = index + 1
			local step = steps[index]
			if step ~= nil then
				step(RunNext)
				return
			end

			g_syncing = false
			NotifyChanged()
			if g_syncAgain then
				g_syncAgain = false
				HeroModules.SyncLobby()
			end
		end
		RunNext()
	end)
end

--Only the game's owner may change a game's code list, so a player in someone
--else's game can't add a Hero module that carries code (the engine refuses,
--see ModuleManager.InstallHeroModuleCo). Such a player asks the owner's client
--through this shared document instead, and the owner's client installs it
--(HeroModules.ServeOwnerRequests). Every client then loads the new code.
--  requests[userid][fullid] = server time the player asked
--  results[fullid] = { ok = boolean, message = nil|string, time = server time }
--A result answers every ask made at or before its time.
local OWNER_REQUESTS_DOC_ID = "heromoduleownerrequests"

--Hero modules that could not be brought into the current game, for the
--warning a player sees: { gameid, list = { [fullid] = {name, message, pending} } }.
--pending: still waiting for the game owner's client to answer.
local g_gameProblems = { gameid = nil, list = {} }

--- @param info ModuleLua
--- @param message string
--- @param pending nil|boolean
local function SetGameProblem(info, message, pending)
	if g_gameProblems.gameid ~= dmhub.gameid then
		g_gameProblems = { gameid = dmhub.gameid, list = {} }
	end
	g_gameProblems.list[info.fullid] = { name = info.name, message = message, pending = pending == true }
end

--- @param fullid string
local function ClearGameProblem(fullid)
	if g_gameProblems.gameid == dmhub.gameid then
		g_gameProblems.list[fullid] = nil
	end
end

--- Asks the game owner's client to install modules this client could not.
--- Records each as a problem until the owner answers; answers that come in
--- later (after the arrival has moved on) still clear or update them.
--- @param infos ModuleLua[]
local function AskOwnerToInstall(infos)
	local gameid = dmhub.gameid
	local askedAt = dmhub.serverTime
	local doc = mod:GetDocumentSnapshot(OWNER_REQUESTS_DOC_ID)
	doc:BeginChange()
	doc.data.requests = doc.data.requests or {}
	local mine = doc.data.requests[dmhub.loginUserid] or {}
	for _, info in ipairs(infos) do
		mine[info.fullid] = askedAt
		SetGameProblem(info, "Waiting for the game's owner to add it. Their client adds it automatically while they are in the game.", true)
		print(string.format("HeroModules: asked the game's owner to add %s", info.fullid))
	end
	doc.data.requests[dmhub.loginUserid] = mine
	doc:CompleteChange("Ask the game owner to add Hero modules", {undoable = false})

	--- @type table<string, ModuleLua>
	local pending = {}
	for _, info in ipairs(infos) do
		pending[info.fullid] = info
	end

	dmhub.Coroutine(function()
		while next(pending) ~= nil and not mod.unloaded and dmhub.gameid == gameid do
			local results = mod:GetDocumentSnapshot(OWNER_REQUESTS_DOC_ID).data.results
			if type(results) == "table" then
				for fullid, info in pairs(pending) do
					local result = results[fullid]
					if type(result) == "table" and (tonumber(result.time) or 0) >= askedAt then
						pending[fullid] = nil
						if result.ok then
							g_lastErrors[fullid] = nil
							ClearGameProblem(fullid)
							print(string.format("HeroModules: the game's owner added %s", fullid))
						else
							local message = tostring(result.message or "The game's owner could not add it.")
							g_lastErrors[fullid] = message
							SetGameProblem(info, message)
							print(string.format("HeroModules: the game's owner could not add %s: %s", fullid, message))
						end
					end
				end
			end
			coroutine.yield(0.25)
		end
	end)
end

--The game currently served by ServeOwnerRequests, so a second call only
--updates the callback: { gameid, onInstalled }.
local g_serving = nil

--- Installs one module a player asked for, on the owner's client. Calls
--- back once with (true) or (false, message for the player).
--- @param fullid string
--- @param callback fun(ok: boolean, message: nil|string)
local function InstallForPlayer(fullid, callback)
	module.DownloadModuleInfo{
		moduleid = fullid,
		success = function(info)
			--a player can only ask for Hero modules: their code was approved
			--by an admin, which is what makes adding it on request safe.
			if not info.isHeroModule then
				callback(false, "This is not a Hero module.")
				return
			end
			if info.premium and not info.owned then
				callback(false, "This is a premium module the game's owner does not own, so they can't add it.")
				return
			end
			info:InstallAsHeroModule{
				success = function()
					callback(true)
				end,
				error = function(message)
					callback(false, message)
				end,
			}
		end,
		failure = function(message)
			callback(false, string.format("The game's owner could not download it: %s", tostring(message)))
		end,
	}
end

--- On the game owner's client: installs the Hero modules other players ask
--- for (see AskOwnerToInstall), all at once, for as long as this client is
--- in this game. Asks made while the owner was away are served when this
--- starts. Runs for the owner of every game from game entry (see the
--- EnterGame handler below). onInstalled(fullid), if given, runs after each
--- successful install; a later call for the same game replaces it.
--- Does nothing for anyone but the owner.
--- @param onInstalled nil|fun(fullid: string)
function HeroModules.ServeOwnerRequests(onInstalled)
	if dmhub.isLobbyGame or not dmhub.inGame or not dmhub.isGameOwner then
		return
	end
	local gameid = dmhub.gameid
	if g_serving ~= nil and g_serving.gameid == gameid then
		if onInstalled ~= nil then
			g_serving.onInstalled = onInstalled
		end
		return
	end
	local serving = { gameid = gameid, onInstalled = onInstalled }
	g_serving = serving

	dmhub.Coroutine(function()
		--modules being added now, by fullid. Every unanswered ask starts at
		--once (the party's reveal waits on the slowest member's modules).
		--- @type table<string, boolean>
		local inFlight = {}
		while not mod.unloaded and dmhub.gameid == gameid do
			do
				local data = mod:GetDocumentSnapshot(OWNER_REQUESTS_DOC_ID).data
				local results = type(data.results) == "table" and data.results or {}

				--the newest ask for each module, across every player.
				--- @type table<string, number>
				local asks = {}
				if type(data.requests) == "table" then
					for _, list in pairs(data.requests) do
						if type(list) == "table" then
							for fullid, t in pairs(list) do
								t = tonumber(t)
								if type(fullid) == "string" and t ~= nil and (asks[fullid] == nil or t > asks[fullid]) then
									asks[fullid] = t
								end
							end
						end
					end
				end

				for fullid, askedAt in pairs(asks) do
					local result = results[fullid]
					local answered = type(result) == "table" and (tonumber(result.time) or 0) >= askedAt
					if not answered and not inFlight[fullid] then
						inFlight[fullid] = true
						print(string.format("HeroModules: adding %s for a player who asked", fullid))
						InstallForPlayer(fullid, function(ok, message)
							inFlight[fullid] = nil
							if mod.unloaded or dmhub.gameid ~= gameid then
								return
							end
							if not ok then
								print(string.format("HeroModules: could not add %s for a player: %s", fullid, tostring(message)))
							end
							local doc = mod:GetDocumentSnapshot(OWNER_REQUESTS_DOC_ID)
							doc:BeginChange()
							doc.data.results = doc.data.results or {}
							--never earlier than the ask, so a small clock difference
							--between the two clients can't leave it unanswered.
							doc.data.results[fullid] = { ok = ok, message = message, time = math.max(dmhub.serverTime, askedAt) }
							doc:CompleteChange("Add a player's Hero module", {undoable = false})
							if ok and serving.onInstalled ~= nil then
								local okCall, err = pcall(serving.onInstalled, fullid)
								if not okCall then
									print(string.format("HeroModules: after adding %s: %s", fullid, tostring(err)))
								end
							end
						end)
					end
				end
			end
			coroutine.yield(0.25)
		end
		if g_serving == serving then
			g_serving = nil
		end
	end)
end

--every game's owner serves its players' asks while in the game. Also on a
--reload of this file mid-game, which stops the old file's loop.
dmhub.RegisterEventHandler("EnterGame", function()
	if mod.unloaded then
		return
	end
	HeroModules.ServeOwnerRequests()
end)
if dmhub.inGame then
	HeroModules.ServeOwnerRequests()
end

--- True if this hero was built with a class or ancestry that is not in this
--- game (its Hero module was not installed here). The hero then has no class
--- -- 0 Stamina, no Recoveries -- or falls back to the default ancestry.
--- @param token CharacterToken
--- @return boolean
function HeroModules.HeroIsMissingContent(token)
	local missing = false
	pcall(function()
		local props = token.properties
		if props == nil or not props:IsHero() then
			return
		end
		local classesTable = GetTableCached("classes")
		for _, entry in ipairs(props:try_get("classes", {})) do
			if entry.classid ~= nil and classesTable[entry.classid] == nil then
				missing = true
			end
		end
		local raceid = props:try_get("raceid")
		if raceid ~= nil and GetTableCached("races")[raceid] == nil then
			missing = true
		end
	end)
	return missing
end

--- @type fun(charids: string[])
local ShowMissingContentWarning

--- Shows the player a warning when any of these heroes is missing its class
--- or ancestry because a Hero module could not be added to this game, naming
--- each such module and why. Shows nothing when every hero is complete.
--- Waits for the loading screen to clear first, and checks then, so a module
--- the game owner added in the meantime is not reported.
--- @param charids string[]
function HeroModules.WarnIfHeroesMissingContent(charids)
	local gameid = dmhub.gameid
	dmhub.Coroutine(function()
		local waited = 0
		while dmhub.loadingScreenHeld and waited < 60 and not mod.unloaded do
			coroutine.yield(0.5)
			waited = waited + 0.5
		end
		--let the reveal's fade finish first.
		coroutine.yield(1.5)
		if mod.unloaded or dmhub.gameid ~= gameid then
			return
		end
		ShowMissingContentWarning(charids)
	end)
end

--- The warning itself, for WarnIfHeroesMissingContent.
--- @param charids string[]
ShowMissingContentWarning = function(charids)
	if g_gameProblems.gameid ~= dmhub.gameid or next(g_gameProblems.list) == nil then
		return
	end

	local heroNames = {}
	for _, charid in ipairs(charids or {}) do
		local token = dmhub.GetCharacterById(charid)
		if token ~= nil and HeroModules.HeroIsMissingContent(token) then
			heroNames[#heroNames+1] = token.name or "A hero"
		end
	end
	if #heroNames == 0 then
		return
	end

	local lines = {}
	for _, problem in pairs(g_gameProblems.list) do
		lines[#lines+1] = string.format("<b>%s</b>: %s", tostring(problem.name), tostring(problem.message))
	end
	table.sort(lines)

	gui.ModalMessage{
		title = "Hero Module Not Added",
		message = string.format("%s %s missing content from a Hero module that could not be added to this game, so %s may have no class (0 Stamina) or the wrong ancestry.\n\n%s",
			table.concat(heroNames, ", "),
			#heroNames == 1 and "is" or "are",
			#heroNames == 1 and "this hero" or "these heroes",
			table.concat(lines, "\n")),
	}
end

--- Brings the player's enabled Hero modules into the current (non-lobby) game,
--- so the classes and ancestries their heroes were built with exist there.
--- Called on the arriving player's own client just before their heroes are
--- pasted in. Only installs, never uninstalls; a module already installed at a
--- usable version is left alone. Calls done() once, after every install has
--- finished or failed, or after timeoutSeconds (default 30) so a slow network
--- never holds the hero back. Installs still running at the timeout carry on,
--- so their classes arrive late rather than never.
--- options.askOwner: a player who isn't the game's owner asks the owner's
--- client to add what this client could not (a module with code; see
--- HeroModules.ServeOwnerRequests). done() then also waits for the owner's
--- answers, for at most options.ownerWaitSeconds (default: until the overall
--- timeout). An owner who is not in the game answers when they next enter.
--- @param done nil|fun()
--- @param timeoutSeconds nil|number
--- @param options nil|{askOwner: nil|boolean, ownerWaitSeconds: nil|number}
function HeroModules.InstallIntoGame(done, timeoutSeconds, options)
	local finished = false
	local Finish = function()
		if finished then
			return
		end
		finished = true
		if done ~= nil then
			done()
		end
	end

	if dmhub.isLobbyGame or not dmhub.inGame then
		Finish()
		return
	end

	dmhub.Schedule(timeoutSeconds or 30, function()
		if not finished then
			print("HeroModules: installing Hero modules into this game timed out; continuing")
		end
		Finish()
	end)

	CollectInventoryForInstall(function(items)
		if mod.unloaded then
			Finish()
			return
		end

		local wanted = {}
		for _, item in ipairs(items) do
			local info = item.module
			if item.enabled and ((not info.premium) or info.owned) then
				wanted[#wanted+1] = info
			end
		end

		g_gameProblems = { gameid = dmhub.gameid, list = {} }
		local askOwner = options ~= nil and options.askOwner == true and not dmhub.isGameOwner
		--- @type ModuleLua[]
		local forOwner = {}

		--done() waits for the owner's answers: Finish once none is pending.
		local function FinishWhenOwnerAnswers()
			local gameid = dmhub.gameid
			local ownerWaitSeconds = options ~= nil and tonumber(options.ownerWaitSeconds) or nil
			local waited = 0
			dmhub.Coroutine(function()
				while not finished and not mod.unloaded and dmhub.gameid == gameid and (ownerWaitSeconds == nil or waited < ownerWaitSeconds) do
					local pending = false
					for _, info in ipairs(forOwner) do
						local problem = g_gameProblems.list[info.fullid]
						if problem ~= nil and problem.pending then
							pending = true
						end
					end
					if not pending then
						break
					end
					coroutine.yield(0.25)
					waited = waited + 0.25
				end
				Finish()
			end)
		end

		--every install starts at once: each one is a handful of network round
		--trips (its code review, its snapshot, the game patch and its echo), so
		--one after another cost ~0.35 s per module on the arriving hero's
		--critical path (8+ s for players with many modules). A timeout only
		--releases the hero; installs still running carry on.
		local pending = #wanted
		local function OneDone()
			pending = pending - 1
			if pending > 0 then
				return
			end
			if mod.unloaded then
				Finish()
			elseif #forOwner > 0 then
				AskOwnerToInstall(forOwner)
				FinishWhenOwnerAnswers()
			else
				Finish()
			end
		end
		if pending == 0 then
			pending = 1
			OneDone()
			return
		end
		for _, info in ipairs(wanted) do
			local fullid = info.fullid
			info:InstallAsHeroModule{
				success = function()
					g_lastErrors[fullid] = nil
					OneDone()
				end,
				error = function(message)
					g_lastErrors[fullid] = message
					print(string.format("HeroModules: %s not installed in this game: %s", fullid, message))
					if askOwner then
						forOwner[#forOwner+1] = info
					else
						SetGameProblem(info, message)
					end
					OneDone()
				end,
			}
		end
	end)
end

--- True for a Hero module kept out of the public listings: published with the
--- "Unlisted" option (publishingProperties.eotwUnlisted, which every browsing
--- tab of the module browser already honours), or never published at all.
--- Only admins see these in Browse Free Items -- used for test modules.
--- @param info ModuleLua
--- @return boolean
function HeroModules.IsUnlisted(info)
	local unlisted = not info.published
	pcall(function()
		unlisted = unlisted or info.publishingProperties.eotwUnlisted == true
	end)
	return unlisted
end

--- @param info ModuleLua
--- @return boolean
local function IsFreeHeroModule(info)
	return info.isHeroModule and (not info.premium)
		and not (info.deprecated and not info.deprecationOverridden)
end

--- Searches one module index ("new" = the public index, "published" = the
--- player's own and their organizations' modules) for free Hero modules.
--- @param index string
--- @param callback fun(items: nil|ModuleLua[], error: nil|string)
local function SearchIndexForFreeModules(index, callback)
	module.QueryModuleIndex{
		index = index,
		success = function(moduleIndex)
			moduleIndex:Search{
				text = "",
				maxResults = 10000,
				success = function(result)
					local items = {}
					for _, info in ipairs(result.items or {}) do
						if IsFreeHeroModule(info) then
							items[#items+1] = info
						end
					end
					callback(items, nil)
				end,
			}
		end,
		failure = function(message)
			callback(nil, tostring(message))
		end,
	}
end

--- Finds every free Hero module: not premium, not deprecated, and listed in
--- the public index. Admins also get unlisted ones, including their own
--- unpublished test modules. Calls back with the list sorted by name, or with
--- nil and a message if the index can't be read.
--- @param callback fun(items: nil|ModuleLua[], error: nil|string)
function HeroModules.QueryFreeModules(callback)
	local admin = dmhub.isAdminAccount
	SearchIndexForFreeModules("new", function(publicItems, err)
		if publicItems == nil then
			callback(nil, err)
			return
		end

		local items = {}
		local seen = {}
		for _, info in ipairs(publicItems) do
			if admin or not HeroModules.IsUnlisted(info) then
				items[#items+1] = info
				seen[info.fullid] = true
			end
		end

		local Finish = function()
			table.sort(items, function(a, b)
				return string.lower(a.name or "") < string.lower(b.name or "")
			end)
			callback(items, nil)
		end

		if not admin then
			Finish()
			return
		end

		SearchIndexForFreeModules("published", function(ownItems)
			for _, info in ipairs(ownItems or {}) do
				if not seen[info.fullid] then
					items[#items+1] = info
					seen[info.fullid] = true
				end
			end
			Finish()
		end)
	end)
end
