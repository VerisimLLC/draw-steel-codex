--Run from the draw-steel-codex root with ../dependencies/lua/bin/lua.exe tests/weather_color_param_test.lua
--A map script "color" parameter (Map Settings > Weather) must be saved as a
--"#rrggbb(aa)" string. tostring() of a Color userdata is a rich-text display
--string that core.Color cannot parse, so the picker must commit .tostring.
local path = 'Draw Steel Core Rules/MapScript.lua'
local f = assert(io.open(path, 'rb'))
local source = f:read('*a'):gsub('\r\n', '\n'); f:close()

local start = assert(source:find('editor = gui.ColorPicker{', 1, true), 'color picker editor not found')
local stop = assert(source:find('\n        elseif param.type == "number" then', start, true), 'end of color editor not found')
local snippet = source:sub(start + #'editor = ', stop - 1)

local checks = 0
local committed = {}
local env = setmetatable({
    gui = { ColorPicker = function(args) return args end },
}, { __index = _G })
local chunk = assert(load(
    'local value, rec, param, CommitParamValue = ...\nreturn ' .. snippet,
    'MapScript color param editor', 't', env))

local rec = { guid = 'rec-guid' }
local param = { id = 'color', type = 'color' }
local editor = chunk('#00ffff', rec, param, function(guid, paramid, value)
    committed[#committed + 1] = { guid = guid, paramid = paramid, value = value }
end)
assert(type(editor) == 'table' and type(editor.confirm) == 'function', 'color picker has a confirm handler')
checks = checks + 1

--Stand-in for the engine Color userdata: tostring() gives the rich-text
--display form, .tostring gives the hex string.
local colorMeta = {
    __tostring = function() return '<color=#00FFFF><link="api:LuaColor">LuaColor</link></color>{}' end,
    __index = function(_, k)
        if k == 'tostring' then return '#00FFFFFF' end
        return nil
    end,
}
local pickedColor = setmetatable({}, colorMeta)

editor.confirm({ value = pickedColor })
assert(#committed == 1, 'confirm commits exactly one value')
checks = checks + 1
assert(committed[1].guid == 'rec-guid' and committed[1].paramid == 'color', 'commits to the right record and param')
checks = checks + 1
local v = committed[1].value
assert(type(v) == 'string', 'committed color must be a string, got ' .. type(v))
checks = checks + 1
assert(v:match('^#%x%x%x%x%x%x$') or v:match('^#%x%x%x%x%x%x%x%x$'),
    'committed color must be a #rrggbb(aa) hex string core.Color can parse, got: ' .. tostring(v))
checks = checks + 1
assert(v == '#00FFFFFF', 'committed color must be the picked color, got: ' .. v)
checks = checks + 1

print('weather_color_param: ' .. checks .. ' checks passed')
