--Run from the draw-steel-codex root with ../dependencies/lua/bin/lua.exe tests/dockable_find_instance_test.lua
--DockablePanel.FindInstance must skip gamehud docks (and dock children) that were destroyed
--during HUD teardown: a destroyed panel reads valid=false and data=nil.
local path = 'DMHub Core UI/DockablePanel.lua'
local f = assert(io.open(path, 'rb'))
local source = f:read('*a'):gsub('\r\n', '\n'); f:close()

local start = assert(source:find('\tFindInstance = function(identifier)', 1, true), 'FindInstance not found')
local stop = assert(source:find('\tGetAllInstancesByIdentifier = function()', start, true), 'end marker not found')
local DockablePanel = assert(load('return {\n' .. source:sub(start, stop - 1) .. '\n}', 'FindInstance'))()

local checks = 0
local function check(c, msg) assert(c, msg); checks = checks + 1 end

local function instance(id) return {valid = true, data = {identifier = id}} end
local function child(instances) return {valid = true, data = {GetPanelInstances = function() return instances end}} end
local function dock(children) return {valid = true, data = {GetChildren = function() return children end}} end
local destroyed = {valid = false}

local chat = instance('chat')
local history = instance('history')

--A destroyed left dock must not stop the search reaching the right dock.
gamehud = {leftDock = destroyed, rightDock = dock{child{chat}}, floatingDock = dock{}}
local ok, result = pcall(DockablePanel.FindInstance, 'chat')
check(ok, 'FindInstance must not error on a destroyed dock: ' .. tostring(result))
check(result == chat, 'FindInstance must still find the panel in a live dock')

--Every dock destroyed: nil, no error.
gamehud = {leftDock = destroyed, rightDock = destroyed, floatingDock = destroyed}
ok, result = pcall(DockablePanel.FindInstance, 'chat')
check(ok, 'FindInstance must not error when every dock is destroyed: ' .. tostring(result))
check(result == nil, 'FindInstance must return nil when every dock is destroyed')

--A destroyed child inside a live dock is skipped.
gamehud = {leftDock = dock{destroyed, child{history}}, rightDock = dock{}, floatingDock = nil}
ok, result = pcall(DockablePanel.FindInstance, 'history')
check(ok, 'FindInstance must not error on a destroyed dock child: ' .. tostring(result))
check(result == history, 'FindInstance must find the panel past a destroyed child')

--Healthy HUD: unchanged behaviour.
gamehud = {leftDock = dock{child{chat}}, rightDock = dock{child{history}}, floatingDock = dock{}}
check(DockablePanel.FindInstance('history') == history, 'FindInstance must find a panel in a healthy HUD')
check(DockablePanel.FindInstance('missing') == nil, 'FindInstance must return nil for an unknown identifier')

print('dockable_find_instance: ' .. checks .. ' checks passed')
