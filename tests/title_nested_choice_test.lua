--Run from the draw-steel-codex root with ../dependencies/lua/bin/lua.exe tests/title_nested_choice_test.lua
--The hero sheet's Titles window, held card for a title whose benefit choice
--has options that are choices themselves (Elemental Dabbler: a damage type,
--then Blaster / Immunity / Weapons). The nested choice must show once its
--option is picked, count toward "choose one", and a pick must be clearable.
--The stubs below live in a private environment: as plain globals, the type
--checker takes them for the engine's real API and misreads the whole codex.
local _ENV = setmetatable({}, {__index = _G})

local path = 'Draw Steel V/HeroSheetTitles.lua'
local f = assert(io.open(path, 'rb'))
local source = f:read('*a'):gsub('\r\n', '\n'); f:close()

local checks = 0
local function check(ok, message)
    checks = checks + 1
    assert(ok, message)
end

--engine stubs: every widget is its args table.
local function widget(args)
    args = args or {}
    args.valid = true
    return args
end
gui = {
    Panel = widget, Label = widget, Input = widget, SearchInput = widget, Dropdown = widget,
    Tooltip = function() return function() end end,
}
function cond(a, b, c) if a then return b else return c end end
function trim(s) return (string.gsub(s or '', '^%s*(.-)%s*$', '%1')) end
unhidden_pairs = pairs
Title = {tableName = 'titles'}
dmhub = {
    GetModLoading = function() return {} end,
    GetTable = function() return {} end,
    Schedule = function(_, fn) fn() end,
    isDM = true,
}
HeroSheetTheme = {
    CardFrame = function(panel) return panel end,
    HoverCard = function(args) return args end,
}
local shown
HeroSheetWindow = {
    DialogWidth = function(w) return w end,
    TargetSize = function(s) return s end,
    ShowDialog = function(args) shown = args end,
    Toast = function() end,
}

local function obj(t)
    t.try_get = function(self, k, d) if self[k] == nil then return d end return self[k] end
    return t
end
local function feature(name, guid)
    return obj{typeName = 'CharacterFeature', name = name, guid = guid, description = name .. ' text'}
end
local function choice(name, guid, options)
    local result = obj{typeName = 'CharacterFeatureChoice', name = name, guid = guid, description = '', options = options}
    function result:GetOptions() return self.options end
    return result
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

--Master Crafter's shape: a benefit, a choice inside it, then a skill choice.
local function skillChoice(name, guid, numChoices)
    local result = obj{typeName = 'CharacterSkillChoice', name = name, guid = guid, description = '', numChoices = numChoices}
    function result:NumChoices() return self.numChoices end
    return result
end
local craftingSkill = skillChoice('Crafting Skill', 'crafting', 2)
local crafter = obj{id = 'crafter', name = 'Master Crafter', echelon = 1, description = '',
    modifierInfo = {features = {choice('Master Crafter Benefit', 'crafterTop', {
        feature('Masterpiece', 'masterpiece'),
        choice('Skilled Hands', 'skilled', {craftingSkill, feature('Already Have Skill', 'already')}),
    })}}}

local levelChoices = {}
--what the Skills window offers: Forgery is already known.
local reads = 0
local allowed = {cooking = true, forgery = true, tailoring = true}
local capacity = 2
HeroSkillsLanguages = {
    Read = function()
        reads = reads + 1
        return {
            grants = {{guid = 'crafting', capacity = capacity, picks = levelChoices.crafting or {}, allowed = allowed}},
            entries = {{id = 'cooking', name = 'Cooking'}, {id = 'forgery', name = 'Forgery'},
                {id = 'tailoring', name = 'Tailoring'}, {id = 'history', name = 'History'}},
            known = {forgery = 'Career'},
        }
    end,
    --as the real one: what the row allows, less what is known; a slot's own pick stays.
    SlotOptions = function(draft, row, slot)
        local result = {}
        local held = {}
        for _, id in ipairs(row.picks) do held[id] = true end
        for _, entry in ipairs(draft.entries) do
            if entry.id == row.picks[slot] or (not held[entry.id] and draft.known[entry.id] == nil and row.allowed[entry.id]) then
                result[#result+1] = entry
            end
        end
        return result
    end,
}
HeroBuild = {main = {Cached = function(fn) return fn() end}}
local hero = obj{
    Titles = function() return {dabbler, crafter} end,
    GetLevelChoices = function() return levelChoices end,
    Invalidate = function() end,
    Echelon = function() return 1 end,
}
local token = {charid = 'hero', name = 'Hero', properties = hero}
HeroSheet = {Token = function() return token end, Saved = function() end}
HeroSheetWrite = {
    CanWrite = function() return true end,
    Save = function(args) args.execute(hero) end,
    SaveSoon = function() end,
    Flush = function() end,
}
HeroSheetWindows = nil

assert(load(source, path, 't', _ENV))()
HeroSheetWindows.OpenTitles()
check(shown ~= nil, 'the Titles window opened')

--the held list is the first panel under the left column's scroll.
local heldList = shown.body[1][2][1]

local cardIndex = 1
local function card()
    return heldList.children[cardIndex]
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

--a skill choice at the end of the chain shows dropdowns, one a pick.
cardIndex = 2
local function dropdowns()
    local result = {}
    for _, child in ipairs(card().children) do
        if child.options ~= nil then
            result[#result+1] = child
        end
    end
    return result
end
local function heading(text)
    for _, child in ipairs(card().children) do
        if child.text == text then return true end
    end
    return false
end
local function offers(dropdown, id)
    for _, option in ipairs(dropdown.options) do
        if option.id == id then return true end
    end
    return false
end
local function choose(slot, id)
    local dropdown = dropdowns()[slot]
    dropdown.idChosen = id
    dropdown.change(dropdown)
end

check(todo(), 'an unpicked Master Crafter is a todo')
row('Skilled Hands').click()
check(row('Crafting Skill') ~= nil and row('Already Have Skill') ~= nil, 'a choice inside a choice shows its options')
check(todo(), 'with Skilled Hands picked the title is still a todo')
check(#dropdowns() == 0, 'no skill dropdown before the skill choice is picked')

row('Crafting Skill').click()
check(heading('Crafting Skill: choose two'), 'a skill choice is headed with its pick count')
check(#dropdowns() == 2, 'a two-pick skill choice shows two dropdowns')
check(offers(dropdowns()[1], 'cooking'), 'the dropdown offers what the choice allows')
check(not offers(dropdowns()[1], 'forgery'), 'a skill already known is not offered')
check(not offers(dropdowns()[1], 'history'), 'a skill outside the choice is not offered')

choose(1, 'cooking')
check(levelChoices.crafting[1] == 'cooking', 'a skill pick saves under the skill choice guid')
check(todo(), 'with one of two skills picked the title is still a todo')
choose(2, 'tailoring')
check(levelChoices.crafting[2] == 'tailoring', 'the second pick saves beside the first')
check(not todo(), 'with both skills picked the title is no longer a todo')
choose(1, 'cooking')
check(#levelChoices.crafting == 2, 'choosing the same skill again changes nothing')
check(not offers(dropdowns()[2], 'cooking'), 'a slot does not offer what the other slot holds')
check(offers(dropdowns()[1], 'none'), 'a filled slot offers None')

choose(1, 'none')
check(#levelChoices.crafting == 1 and levelChoices.crafting[1] == 'tailoring', 'None clears only that slot')
check(todo(), 'with a slot cleared the title is a todo again')
check(not offers(dropdowns()[2], 'none'), 'an empty slot offers no None')
reads = 0
choose(1, 'cooking')
check(reads == 1, 'a redraw reads the skills once, however many titles it draws')

--every allowed skill already known: nothing to pick, so nothing is owed.
levelChoices.crafting = nil
allowed = {forgery = true}
row('Already Have Skill').click()
row('Crafting Skill').click()
check(not todo(), 'a skill choice with nothing left to offer is not a todo')
allowed = {cooking = true, forgery = true, tailoring = true}

--a formula count: the row's own capacity sets the heading.
capacity = 3
craftingSkill.numChoices = 'Level'
row('Already Have Skill').click()
row('Crafting Skill').click()
check(heading('Crafting Skill: choose three'), 'the heading follows the row, not the raw count')
check(#dropdowns() == 3, 'three picks show three dropdowns')
capacity = 2
craftingSkill.numChoices = 2
choose(1, 'cooking')
choose(2, 'tailoring')

row('Skilled Hands').click()
check(levelChoices.crafterTop == nil and levelChoices.skilled == nil, 'clearing the option clears the choice inside it')
check(levelChoices.crafting == nil, 'clearing the option clears the skill picks at the end of the chain')
check(todo(), 'a cleared Master Crafter is a todo again')

print('title_nested_choice: ' .. checks .. ' checks passed')
