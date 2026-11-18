--Run from the draw-steel-codex root with ../dependencies/lua/bin/lua.exe tests/eotw_recruit_xp_reset_test.lua
--A titlescreen hero recruited into the EotW town comes in at level 1; its
--total XP must reset too, or the Training Grounds offers repeated level-ups.
local function readSource(path)
    local f = assert(io.open(path, 'rb'))
    local s = f:read('*a'):gsub('\r\n', '\n'); f:close()
    return s
end

local function extract(source, header, label)
    local start = assert(source:find(header, 1, true), 'cannot find ' .. label)
    local stop = assert(source:find('\nend\n', start, true), 'cannot find end of ' .. label)
    return source:sub(start, stop + 4)
end

local function obj(t)
    t.try_get = function(self, k, d) if rawget(self, k) == nil then return d end return rawget(self, k) end
    return t
end

local checks = 0
local function check(ok, msg)
    assert(ok, msg)
    checks = checks + 1
end

--stubs for the engine globals and the file locals the functions touch.
--A plain table, so the type check allows stubs with only the fields used here.
---@type table<string, any>
local env = setmetatable({}, { __index = _G })
env.EotwRoster = { CanAddHero = function() return true end }
env.EotwHeroSheet = {}
env.Fail = function(m) error('Fail called: ' .. tostring(m)) end
env.T = function(k) return k end
env.m_pendingCreates = {}
env.GameSystem = { numLevels = 10 }

local imported
local sourceProps = obj{
    xp = 48, --level 4 worth of XP at 16 per level
    victories = 5,
    levelOverride = 4,
    classes = { { classid = 'fury', level = 4 } },
    inventory = { a = 1 }, equipment = { b = 2 }, equipmentMeta = {},
}
local copyProps
env.dmhub = {
    ExportCharacter = function(tok) return { record = tok.properties, assets = {} } end,
    ImportCharacter = function(args) imported = args; return 'copyid' end,
    GetSettingValue = function(k) if k == 'xpperlevel' then return 16 end return nil end,
}
local joined = false
env.WhenCharacterExists = function(charid, fn)
    copyProps = obj{
        xp = sourceProps.xp,
        victories = sourceProps.victories,
        levelOverride = sourceProps.levelOverride,
        classes = { { classid = 'fury', level = 4 } },
        inventory = {}, equipment = {}, equipmentMeta = {},
    }
    local tok = { charid = charid, properties = copyProps }
    tok.ModifyProperties = function(_, args) args.execute() end
    fn(tok)
end
env.JoinRoster = function() joined = true end

local roster = readSource('Codex Titlescreen/EotwRoster.lua')
assert(load(extract(roster, 'function EotwRoster.RecruitTitlescreenHero(', 'RecruitTitlescreenHero'),
    'RecruitTitlescreenHero', 't', env))()
local sheet = readSource('Codex Titlescreen/EotwHeroSheetData.lua')
assert(load(extract(sheet, 'function EotwHeroSheet.XpProgress(', 'XpProgress'),
    'XpProgress', 't', env))()

local source = { valid = true, charid = 'srcid', properties = sourceProps }
env.EotwRoster.RecruitTitlescreenHero(source, 'Copy', function() end)

check(imported ~= nil and joined, 'recruit should import the copy and join the roster')
check(copyProps.eotwSourceId == 'srcid', 'copy should remember its source')
check(copyProps.levelOverride == 1 and copyProps.classes[1].level == 1, 'copy should be level 1')
check(copyProps.victories == 0, 'copy should start with no Victories, got ' .. tostring(copyProps.victories))
check(sourceProps.xp == 48 and sourceProps.victories == 5, 'the titlescreen hero must not be touched')

--the level as CharacterLevel() works it out on the copy: the higher of
--levelOverride and its class levels.
local copyLevel = copyProps.levelOverride
for _, entry in ipairs(copyProps.classes) do
    copyLevel = math.max(copyLevel, entry.level)
end
local hero = obj{ xp = copyProps.xp }
hero.CharacterLevel = function() return copyLevel end
local state = env.EotwHeroSheet.XpProgress(hero)
check(state.xp == 0, 'recruited copy should start with 0 XP, got ' .. tostring(state.xp))
check(not state.readyToLevel, 'recruited level-1 copy must not be ready to level (xpIntoLevel=' .. tostring(state.xpIntoLevel) .. ')')

print('eotw_recruit_xp_reset: ' .. checks .. ' checks passed')
