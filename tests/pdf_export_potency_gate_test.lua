--Run from the draw-steel-codex root with ../dependencies/lua/bin/lua.exe tests/pdf_export_potency_gate_test.lua
--The PDF character sheet's CleanText must strip rich-text tags without eating a
--potency gate's "<" comparison (report WX9CUMJC).
local path = 'Draw Steel V/CharSheetPDFExportMCDM.lua'
local f = assert(io.open(path, 'rb'))
local source = f:read('*a'):gsub('\r\n', '\n'); f:close()
local start = assert(source:find('local g_textReplacements = {', 1, true), 'g_textReplacements not found')
local stop = assert(source:find('\n--Maps an ability to the "Ability Type"', start, true), 'end of CleanText not found')
local chunk = source:sub(start, stop) .. '\nreturn CleanText\n'
local CleanText = assert(load(chunk, 'CleanText'))()

local checks = 0
local function eq(input, expected, msg)
    local got = CleanText(input)
    assert(got == expected, string.format('%s: expected %q, got %q', msg, expected, got))
    checks = checks + 1
end

--Exactly what DisplayRuleTextForCreature emits for "P < weak, slowed (save ends)".
eq('<color=#ff4444><uppercase>P</uppercase> < 2</color>, slowed (save ends)',
   'P < 2, slowed (save ends)', 'potency gate must survive tag stripping')
eq('8 + M damage; <color=#ff4444><uppercase>M</uppercase> < 3</color> prone',
   '8 + M damage; M < 3 prone', 'gate in the middle of a tier')
eq('<color=#ff4444><uppercase>A</uppercase>2</color>', 'A2', 'bracketed potency form')
eq('<b>Bold</b> <i>it</i> <size=80%>small</size> <alpha=#88>x', 'Bold it small x', 'real tags are stripped')
eq('**Effect:** none', 'Effect: none', 'markdown bold unwrapped')
eq(nil, nil, 'nil passes through')

print(string.format('pdf_export_potency_gate: %d checks passed', checks))
