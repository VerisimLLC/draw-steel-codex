--The panel registry. DockablePanel.Register declares a panel (name, icon,
--content builder, size bounds, permissions); the icon rail
--(DocumentSystem.lua) shows registered panels as rail buttons and floating
--windows. Opening one by name, from a menu or a keybind goes through
--GetMenuItems' click to the rail's open handler.

--The icon rail used to be optional ("New Experimental UI") beside the old
--side docks. The docks are retired, but the setting stays registered and
--always on because the engine reads it: GameConfig.cs picks window zoom over
--font zoom from it. It has no editor, so nothing can turn it off. resetCount 2
--switches back on everyone who had turned it off: the engine
--(CoreAssets/Lua/settings.txt) resets a setting to its default while its
--"iconrail_resets" counter is below resetCount.
setting{
    id = "iconrail",
    storage = "preference",
    default = true,
    resetCount = 2,
}

--registered panels, keyed by identifier ("<modid>-<name>").
local dockablePanels = {}

--The HOST that opens a panel from a menu, keybind or by-name request
--(GetMenuItems' click). The icon rail registers the only one: it shows
--the panel as a rail window. The handler returns true if it hosted the
--panel. Keyed by id so a Lua reload replaces rather than duplicates.
g_dockablePanelOpenHandlers = rawget(_G, "g_dockablePanelOpenHandlers") or {}

--- @param id string unique id for this handler
--- @param fn fun(panelName: string, operation: nil|'toggle'|'show'|'hide'): boolean
function RegisterDockablePanelOpenHandler(id, fn)
	g_dockablePanelOpenHandlers[id] = fn
end

--Returns true if some handler hosted the panel itself.
local function NotifyDockablePanelOpen(name, operation)
	if name == nil then
		return false
	end
	local ids = {}
	for id, _ in pairs(g_dockablePanelOpenHandlers) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		--a broken handler is logged, and the next one is tried.
		local ok, handled = pcall(g_dockablePanelOpenHandlers[id], name, operation)
		if not ok then
			print(string.format("DOCKPANEL:: open handler '%s' failed: %s", id, tostring(handled)))
		elseif handled then
			return true
		end
	end
	return false
end

local function CustomInterfaceSuppresses(name)
	return GameHud.CustomInterfaceSuppressesPanel(name) == true
end

--May THIS user have this panel at all? devonly panels need dev mode, dmonly
--panels need the Director, hostonly panels the Director or a player host.
--Asked everywhere a panel is listed or opened, not just in the menus: the
--rail restores panels from saved layouts, which may name a panel this user
--may no longer have (report XRA4WE35).
local PanelPermittedForUser = function(p)
	if p == nil then
		--unknown identifier (a mod that is not loaded): leave it to the
		--caller, which finds no registration and adds nothing.
		return true
	end
	if p.devonly and not devmode() then
		return false
	end
	--a panel behind a setting: available() says whether it exists right now. It runs
	--several times a second on the rails, so keep it cheap.
	if p.available ~= nil and not p.available() then
		return false
	end
	--DirectorUIVisible rather than dmhub.isDM so dmonly panels also hide for
	--a Director presenting as a player (Encounter of the Week host). Panel
	--background processes (DockablePanel.StartProcess) are independent of
	--this gate, so the EotW host still runs the Monster AI headless.
	if p.dmonly and not GameHud.DirectorUIVisible() then
		return false
	end
	--hostonly: the Director's UI, or the host of a game with no Director, who
	--holds the Director's tools there (dmhub.playerHostMode).
	if p.hostonly and not (GameHud.DirectorUIVisible() or dmhub.playerHostMode) then
		return false
	end
	--a mod-enforced custom interface can suppress panels by name
	--(GameHud.RegisterCustomInterface); this gate covers every discovery
	--surface that respects registrations -- menus, toolbar, rail, search.
	--(pcall of a named function, not a closure: the icon rails run this per panel
	--several times a second.)
	if p.name ~= nil then
		local ok, suppressed = pcall(CustomInterfaceSuppresses, p.name)
		if ok and suppressed then
			return false
		end
	end
	return true
end

--The panel shown for a registration: itself, or, when it can't show for this user, the
--panel registered to stand in for it (standsInFor). A layout saved with the Action Log
--shows History instead, and the other way round. Nil when nothing can show.
local function StandIn(registration)
	if registration == nil or PanelPermittedForUser(registration) then
		return registration
	end
	for _, candidate in pairs(dockablePanels) do
		if candidate.standsInFor ~= nil and string.lower(candidate.standsInFor) == string.lower(registration.name) and PanelPermittedForUser(candidate) then
			return candidate
		end
	end
	return nil
end

DockablePanel = {
	--Exposed because the icon rail and the panel windows restore panels from
	--their own saved config and must apply the same rule.
	PanelPermittedForUser = PanelPermittedForUser,

	ContentWidth = 364,
	DockWidth = 364,

	--args: name, icon, content(), vscroll, minHeight/maxHeight (vertical
	--content bounds for the panel's rail window; equal values pin a fixed
	--height and make the window vertically unresizable), dmonly, devonly, ...
	--Standalone-window extras: resizableWidth/resizableHeight = false
	--lock window resizing on that axis (default: both freely resizable);
	--minWidth/maxWidth bound the window's width; defaultWidth is the width
	--a new window opens at (PanelDocument.DefaultWidth otherwise).
	--popoutHeight (content px) gives the panel's native OS popout window
	--its own default height, instead of inheriting the in-app window's
	--footprint when popping out.
	--menu = "codex"|"game"|"tools" lists the panel in that title-bar menu
	--INSTEAD of the Panels menu.
	--launch = function() makes this an ACTION registration instead of a
	--panel: activating it (menu row, icon-rail button, ShowPanelByName)
	--runs launch() and no window ever opens. Give it no content; it still
	--gets an icon, menu placement, dmonly/devonly gating, and rail
	--membership like any panel. First client: the Body Banks, which
	--launches the companion app.
	--available = function() hides the panel from every list while it returns false.
	--standsInFor = "<panel name>": a layout that saved that panel shows this one while that
	--one is not available (History and the old Action Log).
	Register = function(args)
		--if args.dmonly and not dmhub.isDM then
		--	return
		--end
		
		local guid = dmhub.GenerateGuid()

		local panelInfo = DeepCopy(args)
		local modLoading = dmhub.GetModLoading()
		if modLoading ~= nil then
			panelInfo.modid = modLoading.modid
		end
		panelInfo.guid = guid

		panelInfo.identifier = string.format("%s-%s", panelInfo.modid or "CORE", panelInfo.name)

		--if there is an existing panel with the same name we prefer to overwrite it.
		for k,v in pairs(dockablePanels) do
			if v.name == args.name then
				panelInfo.identifier = v.identifier
			end
		end

		dockablePanels[panelInfo.identifier] = panelInfo
	end,

	Deregister = function(name)
		for k,v in pairs(dockablePanels) do
			if v.name == name then
				dockablePanels[k] = nil
				return
			end
		end
	end,

	--Open a panel by its registered name, or raise it if it is already
	--open. The counterpart of the launchable panels' GetOrLaunchPanel, for
	--the callers that summon a specific panel rather than toggling one --
	--journal command links, and the remote present-a-dialog request --
	--which have to search both registries now that panels like Maps live
	--here. Returns true if a panel by that name exists here. Filtered
	--panels are included: being hidden from the menus does not mean a
	--direct request for it should fail.
	ShowPanelByName = function(name)
		if name == nil then
			return false
		end
		name = string.lower(name)
		for _,item in ipairs(DockablePanel.GetMenuItems(true, true)) do
			if item.name ~= nil and string.lower(item.name) == name then
				item.click("show")
				return true
			end
		end
		return false
	end,

	--Look up a panel registration by its registered name (case-insensitive).
	--Returns the registration args table (name, icon, content, vscroll,
	--minHeight, maxHeight, minWidth, maxWidth, resizableWidth,
	--resizableHeight, dmonly, devonly, ...) or nil. Used by the document
	--system's PanelDocument bridge to host dockable panel content inside
	--document windows.
	GetRegistration = function(name)
		name = string.lower(name)
		for _,v in pairs(dockablePanels) do
			if string.lower(v.name) == name then
				return v
			end
		end
		return nil
	end,

	--Registrations whose new-content alert is currently lit AND which offer
	--a way to retire it (clearNewContent, or markContentSeen as a fallback).
	--Drives the icon rail's "Clear All Alerts" context-menu entry, which only
	--appears when more than one panel has an alert to clear.
	GetAlertedRegistrations = function()
		local result = {}
		for _,p in pairs(dockablePanels) do
			if p.hasNewContent ~= nil and (p.clearNewContent ~= nil or p.markContentSeen ~= nil) and p.hasNewContent() then
				result[#result+1] = p
			end
		end
		return result
	end,

	GetMenuItems = function(flat, includeFiltered)
		local subfolders = {}
		local result = {}
		for k,p in pairs(dockablePanels) do

			local available = PanelPermittedForUser(p)

			--A panel may hide itself from the menus in this context --
			--Maps, for one, which players only get when there is a map
			--they can browse. Same contract the launchable panels have
			--always had. includeFiltered is for by-name lookups, which
			--must still find them.
			if available and (not includeFiltered) and p.filtered ~= nil and p.filtered() then
				available = false
			end

			if available then

				local target = result

				if (not flat) and p.folder ~= nil then
					local folder = subfolders[p.folder]

					if folder == nil then
						folder = {}
						target[#target+1] = {
							id = string.format("Folder%s", p.folder),
							text = p.folder,
							submenu = folder,
						}
						subfolders[p.folder] = folder
					end

					target = folder
				end

				local bind = dmhub.GetCommandBinding(string.format("togglepanel %s", string.lower(p.name)))

				target[#target+1] = {
					id = string.format("Menu%s", p.name),
					--name/identifier/menu/group/ord/hasNewContent/geticon
					--mirror what the launchable-panel menu items carry, so
					--the title bar and the journal's link resolution can
					--treat both registries the same way. `menu` is what
					--sorts a panel into the Codex/Game/Tools menus.
					name = p.name,
					identifier = p.identifier,
					menu = p.menu,
					group = p.group or "",
					ord = p.ord or 0,
					hasNewContent = p.hasNewContent,
					geticon = p.geticon,
					text = p.name,
					icon = p.icon,
					bind = bind,
					--lit while the panel is shown in a rail window.
					check = rawget(_G, "PanelDocument") ~= nil and PanelDocument.IsPanelShown(string.lower(p.name)),

					---@param operation nil|'toggle'|'show'|'hide'
					click = function(operation)
						-- Action registration: activating it IS the action.
						-- No rail or window is touched, so this works
						-- from the lobby too. "hide" means the caller wants
						-- it gone, which for an action is a no-op.
						if p.launch ~= nil then
							if operation ~= "hide" then
								p.launch()
							end
							return
						end

						-- Panels open as rail windows, which exist only once a
						-- game is active. Bail out silently from the lobby.
						if rawget(_G, "gamehud") == nil then
							return
						end

						-- The icon rail registers the open handler that hosts
						-- the panel; there is no dock to fall back to.
						NotifyDockablePanelOpen(p.name, operation)
					end,
				}
			end
		end

		for _,item in ipairs(result) do
			if item.submenu ~= nil then
				table.sort(item.submenu, function(a,b) return a.text < b.text end)
			end
		end

		table.sort(result, function(a,b)
			local asub = a.submenu ~= nil
			local bsub = b.submenu ~= nil
			if asub ~= bsub then
				return bsub
			end

			return a.text < b.text
		end)
		return result
	end,

    --- @param str string
    --- @param operation nil|'toggle'|'show'|'hide'
	LaunchPanelByName = function(str, operation)
		str = string.lower(str)
		local items = DockablePanel.GetMenuItems(true)
		for _,item in ipairs(items) do
			if item.text ~= nil and string.lower(item.text) == str then
				item.click(operation)
				return true
			end
		end

		return false
	end,
}

--- The registration shown in place of one that can't show for this user: the registration
--- itself when it can, else the one registered to stand in for it (standsInFor). Nil when
--- neither can show.
--- @param registration table|nil
--- @return table|nil
DockablePanel.StandIn = function(registration)
	return StandIn(registration)
end

--=============================================================================
--Panel background processes.
--
--A dockable panel can register a "process": a coroutine that keeps running
--after the panel itself is closed. The canonical example is the Monster AI --
--pressing Start AI registers a process, and closing the Monster AI panel does
--not stop the AI from taking turns. While any process for a panel is running,
--the panel's icon-rail button shows a small spinning gear in its bottom-left
--corner (see the iconRailProcessGear panel in DocumentSystem.lua), so the user
--always knows background work is going on and where to go to stop it.
--
--Usage:
--
--    local process = DockablePanel.StartProcess{
--        panel = "Monster AI",          --the DockablePanel.Register name
--        id = "monster-ai",             --unique within the panel; restarting
--                                       --an id replaces the old process
--        coroutine = function(process)  --runs as a dmhub.Coroutine
--            while true do
--                coroutine.yield(0.1)
--                if mod.unloaded or process.stopRequested then
--                    return
--                end
--                --do work
--            end
--        end,
--    }
--
--Stopping is COOPERATIVE: StopProcess / process:Stop() only set
--process.stopRequested; the coroutine must poll it (and its own module's
--mod.unloaded, since a Lua reload abandons this registry) and return. The
--registry entry clears when the coroutine actually returns, so the rail gear
--keeps spinning through a graceful wind-down ("Stopping...") and stops when
--the work truly ends.
--=============================================================================

--lowercase panel name -> { [id] = process }
local panelProcesses = {}

local function ProcessPanelKey(name)
	return string.lower(tostring(name or ""))
end

--- Start (or restart) a background process for a registered dockable panel.
--- args: panel (string, the registered panel name), id (string, defaults to
--- "main"), coroutine (function(process), run as a dmhub.Coroutine).
--- Returns the process handle, which is also passed to the coroutine:
--- { panel, id, stopRequested, finished, Stop() }.
DockablePanel.StartProcess = function(args)
	local panelName = args.panel
	local id = args.id or "main"
	local fn = args.coroutine
	if panelName == nil or fn == nil then
		printf("DockablePanel.StartProcess: 'panel' and 'coroutine' fields are required")
		return nil
	end

	--restarting an id replaces the old process: ask it to stop first.
	DockablePanel.StopProcess(panelName, id)

	local process = {
		panel = panelName,
		id = id,
		stopRequested = false,
		finished = false,
	}

	function process:Stop()
		self.stopRequested = true
	end

	local key = ProcessPanelKey(panelName)
	local procs = panelProcesses[key]
	if procs == nil then
		procs = {}
		panelProcesses[key] = procs
	end
	procs[id] = process

	dmhub.Coroutine(function()
		process.thread = coroutine.running()
		local ok, err = pcall(fn, process)
		process.finished = true
		if procs[id] == process then
			procs[id] = nil
		end
		if not ok then
			printf("DockablePanel process '%s' for panel '%s' error: %s", id, panelName, tostring(err))
		end
	end)

	return process
end

--- Request that a panel's background process stop. With an id, stops that
--- process; with no id, stops every process the panel has. Cooperative -- the
--- coroutine keeps running until it polls process.stopRequested and returns.
DockablePanel.StopProcess = function(panelName, id)
	local procs = panelProcesses[ProcessPanelKey(panelName)]
	if procs == nil then
		return
	end
	if id ~= nil then
		local p = procs[id]
		if p ~= nil then
			p:Stop()
		end
	else
		for _, p in pairs(procs) do
			p:Stop()
		end
	end
end

--- The process handle for a panel's process (id defaults to "main"), or nil
--- if it is not running.
DockablePanel.GetProcess = function(panelName, id)
	local procs = panelProcesses[ProcessPanelKey(panelName)]
	if procs == nil then
		return nil
	end
	return procs[id or "main"]
end

--- True while the panel has any background process whose coroutine has not
--- finished. This is what the icon rail's spinning gear indicator reads.
DockablePanel.HasActiveProcess = function(panelName)
	local procs = panelProcesses[ProcessPanelKey(panelName)]
	if procs == nil then
		return false
	end
	for _, p in pairs(procs) do
		if not p.finished then
			--belt-and-suspenders: if the thread died without the wrapper
			--marking it finished, do not report (and spin the gear) forever.
			if p.thread == nil or coroutine.status(p.thread) ~= "dead" then
				return true
			end
		end
	end
	return false
end

--The engine calls this once while building the hud (SheetHud.cs). The
--engine's own core Lua defines a version that builds the old docks, so
--this no-op has to replace it: panels open as icon-rail windows instead.
function InitDockablePanels()
end

dmhub.RegisterOnUnloadModFunction(function(modid)
	local deleteGuids = {}

	for k,p in pairs(dockablePanels) do
		if p.modid == modid then
			deleteGuids[#deleteGuids+1] = k
		end
	end

	for _,k in ipairs(deleteGuids) do
		dockablePanels[k] = nil
	end
end)
