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

--- Brings the player's enabled Hero modules into the current (non-lobby) game,
--- so the classes and ancestries their heroes were built with exist there.
--- Called on the arriving player's own client just before their heroes are
--- pasted in. Only installs, never uninstalls; a module already installed at a
--- usable version is left alone. Calls done() once, after every install has
--- finished or failed, or after timeoutSeconds (default 30) so a slow network
--- never holds the hero back. Installs still running at the timeout carry on,
--- so their classes arrive late rather than never.
--- @param done nil|fun()
--- @param timeoutSeconds nil|number
function HeroModules.InstallIntoGame(done, timeoutSeconds)
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

	HeroModules.CollectInventory(function(items)
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

		local index = 0
		local RunNext
		RunNext = function()
			--do not stop on `finished`: a timeout only releases the hero, and
			--abandoning the queue would leave later modules (and their heroes'
			--classes) missing from this game for good.
			if mod.unloaded then
				Finish()
				return
			end
			index = index + 1
			local info = wanted[index]
			if info == nil then
				Finish()
				return
			end
			local fullid = info.fullid
			info:InstallAsHeroModule{
				success = function()
					g_lastErrors[fullid] = nil
					RunNext()
				end,
				error = function(message)
					g_lastErrors[fullid] = message
					print(string.format("HeroModules: %s not installed in this game: %s", fullid, message))
					RunNext()
				end,
			}
		end
		RunNext()
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
