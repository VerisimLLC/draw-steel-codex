--Run from the draw-steel-codex root with ../dependencies/lua/bin/lua.exe tests/spend_recovery_swallow_press_test.lua
--The EotW hero card opens the character panel on press. The "+" that spends
--a Recovery sits inside the card, so its press must not bubble up to the card:
--the button panel needs swallowPress = true (as CreateTriggerCorner's badge has).
local path = 'Codex Titlescreen/EotwHeroCard.lua'
local f = assert(io.open(path, 'rb'))
local source = f:read('*a'):gsub('\r\n', '\n'); f:close()

local s = source:find('local function CreateSpendRecoveryButton%(', 1)
assert(s, 'CreateSpendRecoveryButton not found in ' .. path)
local e = source:find('\nend\n', s, true)
assert(e, 'end of CreateSpendRecoveryButton not found')
local chunk = source:sub(s, e + 4) .. '\nreturn CreateSpendRecoveryButton\n'

local function Element(kind)
    return function(args)
        args = args or {}
        return { kind = kind, args = args }
    end
end

local env = setmetatable({
    gui = { Panel = Element('Panel'), Label = Element('Label') },
}, { __index = _G })

local CreateSpendRecoveryButton = assert(load(chunk, '@' .. path, 't', env))()
local button = CreateSpendRecoveryButton('char-1', { selfStyle = {} })

local checks = 0
assert(type(button) == 'table' and button.kind == 'Panel', 'CreateSpendRecoveryButton must return a panel')
checks = checks + 1
assert(type(button.args.press) == 'function', 'the spend-recovery button must handle press')
checks = checks + 1
assert(button.args.swallowPress == true,
    'the spend-recovery "+" must set swallowPress = true, or its press bubbles up to the hero card and opens the character panel')
checks = checks + 1

print(string.format('spend_recovery_swallow_press: %d checks passed', checks))
