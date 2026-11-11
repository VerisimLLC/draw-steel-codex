--Run from the draw-steel-codex root with ../dependencies/lua/bin/lua.exe tests/voice_menu_attached_test.lua
--Every panel DiscordVoice.CreateMenu builds must end up in the menu it returns.
--The engine reports a panel created but never attached as an error popup.
local path = 'Draw Steel V/DiscordVoice.lua'
local f = assert(io.open(path, 'rb'))
local source = f:read('*a'):gsub('\r\n', '\n'); f:close()

--a permissive stub: any field read or call yields another stub.
local function Stub()
    local s = {}
    setmetatable(s, {
        __index = function(t, k) local v = Stub(); rawset(t, k, v); return v end,
        __call = function() return Stub() end,
    })
    return s
end

local created = {}
local function Element(kind)
    return function(args)
        args = args or {}
        local el = { kind = kind, args = args }
        el.SetClass = function() end
        el.FireEvent = function() end
        created[#created + 1] = el
        return el
    end
end

for _, name in ipairs{'dmhub', 'Keybinds', 'Commands', 'ThemeEngine'} do
    _G[name] = Stub()
end
function setting(t) return Stub() end
function cond(a, b, c) if a then return b else return c end end
gui = Stub()
gui.Panel = Element('Panel')
gui.Button = Element('Button')
gui.Label = Element('Label')
gui.Slider = Element('Slider')
gui.Input = Element('Input')
gui.Dropdown = Element('Dropdown')
gui.Check = Element('Check')
setmetatable(_G, { __index = function(t, k) local v = Stub(); rawset(t, k, v); return v end })

assert(load(source, '@' .. path))()

created = {}
local menu = DiscordVoice.CreateMenu(function() end)
assert(type(menu) == 'table' and menu.kind == 'Panel', 'CreateMenu must return a panel')

local reached = {}
local function Walk(el)
    if type(el) ~= 'table' or el.args == nil or reached[el] then return end
    reached[el] = true
    for _, child in ipairs(el.args) do Walk(child) end
    if type(el.args.children) == 'table' then
        for _, child in ipairs(el.args.children) do Walk(child) end
    end
end
Walk(menu)

local checks = 0
for _, el in ipairs(created) do
    local text = el.args.text or ''
    assert(reached[el], string.format('%s "%s" was created by CreateMenu but not attached to the menu', el.kind, text))
    checks = checks + 1
end

local found = false
for _, el in ipairs(created) do
    if el.args.text == 'Link Discord' then found = true end
end
assert(found, 'the menu must include the Link Discord button')
checks = checks + 1

print(string.format('voice_menu_attached: %d checks passed', checks))
