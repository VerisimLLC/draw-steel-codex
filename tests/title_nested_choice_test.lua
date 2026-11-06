--Run from the draw-steel-codex root with ../dependencies/lua/bin/lua.exe tests/title_nested_choice_test.lua
--The hero sheet's Titles window, held card for a title whose benefit choice
--has options that are choices themselves (Elemental Dabbler: a damage type,
--then Blaster / Immunity / Weapons). The nested choice must show once its
--option is picked, count toward "choose one", and a pick must be clearable.
local path = 'Draw Steel V/HeroSheetTitles.lua'
local f = assert(io.open(path, 'rb'))
local source = f:read('*a'):gsub('\r\n', '\n'); f:close()

local checks = 0
local function check(ok, message)
    checks = checks + 1
    assert(ok, message)
end

--Engine stubs are set through stub(): LuaLS reads a global assignment here,
--even a rawset with a literal name, as another definition of the real global
--and retypes it across the codex (HeroSheetWrite.Save lost its boolean return).
local function stub(name, value) rawset(_G, name, value) end
--every widget is its args table.
local function widget(args)
    args = args or {}
    args.valid = true
    return args
end
stub('gui', {
    Panel = widget, Label = widget, Input = widget, SearchInput = widget,
    Tooltip = function() return function() end end,
})
stub('cond', function(a, b, c) if a then return b else return c end end)
stub('trim', function(s) return (string.gsub(s or '', '^%s*(.-)%s*$', '%1')) end)
stub('unhidden_pairs', pairs)
stub('Title', {tableName = 'titles'})
stub('dmhub', {
    GetModLoading = function() return {} end,
    GetTable = function() return {} end,
    Schedule = function() end,
    isDM = true,
})
stub('HeroSheetTheme', {
    CardFrame = function(panel) return panel end,
    HoverCard = function(args) return args end,
})
local shown
stub('HeroSheetWindow', {
    DialogWidth = function(w) return w end,
    TargetSize = function(s) return s end,
    ShowDialog = function(args) shown = args end,
    Toast = function() end,
})

local function obj(t)
    t.try_get = function(self, k, d) if self[k] == nil then return d end return self[k] end
    return t
end
local function feature(name, guid)
    return obj{typeName = 'CharacterFeature', name = name, guid = guid, description = name .. ' text'}
end
local function choice(name, guid, options)
    return obj{typeName = 'CharacterFeatureChoice', name = name, guid = guid, description = '', options = options}
end
local damageTypes = {}
for _, damage in ipairs{'Acid', 'Cold', 'Fire'} do
    damageTypes[#damageTypes+1] = choice(damage, damage, {
        feature('Elemental Blaster - ' .. damage, 'blaster-' .. damage),
        feature('Elemental Immunity - ' .. damage, 'immunity-' .. damage),
        feature('Elemental Weapons - ' .. damage, 'weapons-' .. damage),
    })
end
local top = choice('Elemental Dabbler Choice', 'top', damageTypes)
local dabbler = obj{id = 'dabbler', name = 'Elemental Dabbler', echelon = 1, description = '',
    modifierInfo = {features = {top}}}

local levelChoices = {}
local hero = obj{
    Titles = function() return {dabbler} end,
    GetLevelChoices = function() return levelChoices end,
    Echelon = function() return 1 end,
}
local token = {charid = 'hero', name = 'Hero', properties = hero}
stub('HeroSheet', {Token = function() return token end, Saved = function() end})
stub('HeroSheetWrite', {
    CanWrite = function() return true end,
    Save = function(args) args.execute(hero) end,
    SaveSoon = function() end,
    Flush = function() end,
})
stub('HeroSheetWindows', nil)

assert(load(source, path))()
HeroSheetWindows.OpenTitles()
check(shown ~= nil, 'the Titles window opened')

--the held list is the first panel under the left column's scroll.
local heldList = shown.body[1][2][1]

local function card()
    return heldList.children[1]
end
local function rows()
    local result = {}
    for _, child in ipairs(card().children) do
        for _, class in ipairs(child.classes or {}) do
            if class == 'heroSheetBenefit' then
                result[#result+1] = child
            end
        end
    end
    return result
end
local function rowName(row) return row[2][1].text end
local function row(name)
    for _, r in ipairs(rows()) do
        if rowName(r) == name then return r end
    end
    return nil
end
local function todo()
    for _, class in ipairs(card().classes) do
        if class == 'heroSheetTitleTodo' then return true end
    end
    return false
end

check(#rows() == 3, 'before any pick only the damage types show')
check(todo(), 'an unpicked title is a todo')

row('Fire').click()
check(levelChoices.top ~= nil and levelChoices.top[1] == 'Fire', 'picking Fire saves it under the title choice')
check(row('Elemental Immunity - Fire') ~= nil, 'once Fire is picked its effect choice (Blaster / Immunity / Weapons) shows')
check(row('Elemental Blaster - Cold') == nil, 'only the picked damage type offers its effects')
check(todo(), 'with the effect still unpicked the title is still a todo')

row('Elemental Immunity - Fire').click()
check(levelChoices.Fire ~= nil and levelChoices.Fire[1] == 'immunity-Fire', 'the effect pick is saved under the nested choice guid')
check(not todo(), 'with both picks made the title is no longer a todo')

row('Fire').click()
check(levelChoices.top == nil, 'clicking the selected damage type clears it')
check(levelChoices.Fire == nil, 'clearing the damage type clears its effect pick too')
check(row('Elemental Immunity - Fire') == nil, 'after clearing, the effect choice is hidden again')
check(todo(), 'a cleared title is a todo again')

print('title_nested_choice: ' .. checks .. ' checks passed')
