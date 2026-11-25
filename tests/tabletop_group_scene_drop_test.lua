--Run from the draw-steel-codex root with ../dependencies/lua/bin/lua.exe tests/tabletop_group_scene_drop_test.lua
--A selected group of table cards dragged into a scene must carry every
--selected card, not only the one grabbed (issue QNZE34J2).
local path = 'DMHub Game Hud/Tabletop.lua'
local f = assert(io.open(path, 'rb'))
local source = f:read('*a'):gsub('\r\n', '\n'); f:close()

local checks = 0
local function check(ok, msg)
    checks = checks + 1
    assert(ok, msg)
end

--the text of the field `name = function(element) ... end,` in the hero
--card's panel (8-space indent), as a chunk returning that function.
local function Handler(name)
    local head = '\n        ' .. name .. ' = function(element)\n'
    --the hero card's handlers follow its beginDrag, which starts the group.
    local from = assert(source:find('\n            g_cs.BeginCardGroup(card)\n', 1, true), 'hero card beginDrag not found')
    local start = assert(source:find(head, from, true), 'handler not found: ' .. name)
    local stop = assert(source:find('\n        end,\n', start + #head, true), 'handler end not found: ' .. name)
    return 'return function(element)\n' .. source:sub(start + #head, stop) .. 'end\n'
end

--the real group functions, MoveCardGroup and TakeCardGroup.
local function GroupFunctions()
    local start = assert(source:find('\nfunction g_cs.MoveCardGroup(card, dx, dy, follow)\n', 1, true))
    local stop = assert(source:find('\nfunction g_cs.LandCardGroup(group, dx, dy)\n', start, true))
    return source:sub(start, stop)
end

local function Setup(opts)
    local env = setmetatable({}, {__index = _G})
    local function Card(charid, x)
        return {charid = charid, x = x, y = 100, panel = {valid = true, x = x, y = 100}}
    end
    local a, b, c = Card('a', 10), Card('b', 200), Card('c', 400)
    env.closed = {}
    env.offered = nil
    env.dropped = nil
    env.g_cs = {}
    if opts.group then
        env.g_cs.group = {card = a, members = {{card = b, x = 200, y = 100}, {card = c, x = 400, y = 100}}}
    end
    env.card = a
    env.g_cardDrag = nil
    env.CARD_TITLE_HEIGHT = 20
    env.LayerSize = function() return 2000, 2000 end
    env.CloseCard = function(cd) env.closed[cd.charid] = true end
    env.EndCardDrag = function() end
    env.ChatItemLinks = {
        Dragging = function(items) env.offered = items() end,
        Dropped = function() return opts.toChat == true end,
        CharacterItem = function(charid) return {kind = 'character', id = charid} end,
    }
    env.SceneElements = {
        TookCharacter = function(charid) return opts.took ~= nil and opts.took[charid] == true end,
        DropOnBackground = function(charids)
            env.dropped = charids
            return opts.background == true
        end,
    }
    env.dmhub = {tabletopDragSurface = 'table', panelDropSurface = opts.surface or 'table', isDM = false}
    env.DirectorScreen = {ItemDragging = function() end, ItemDropped = function() end}
    env.g_heroCards = {ScreenKey = function() return 'k' end, Detach = function() end}
    env.g_chrome = {CreatureDropClaimed = function() return false end}
    assert(load(GroupFunctions(), 'g_cs group functions', 't', env))()
    env.dragging = assert(load(Handler('dragging'), 'dragging handler', 't', env))()
    env.drag = assert(load(Handler('drag'), 'drag handler', 't', env))()
    env.element = {xdrag = 50, ydrag = 150, x = 10, y = 100, SetClass = function() end, SetAsLastSibling = function() end}
    return env
end

local function Ids(items)
    local r = {}
    for _, item in ipairs(items or {}) do r[item.id] = true end
    return r
end

--1. While dragging a group, every selected card is offered as a link.
do
    local env = Setup{group = true}
    env.dragging(env.element)
    local ids = Ids(env.offered)
    check(ids.a and ids.b and ids.c, 'dragging a group must offer a CharacterItem for every selected card, got ' .. #(env.offered or {}))
end

--2. A group dropped on the bare table over a background scene: all go in.
do
    local env = Setup{group = true, background = true}
    env.drag(env.element)
    local ids = {}
    for _, id in ipairs(env.dropped or {}) do ids[id] = true end
    check(ids.a and ids.b and ids.c, 'DropOnBackground must receive every selected charid, got ' .. #(env.dropped or {}))
    check(env.closed.a and env.closed.b and env.closed.c, 'every card moved into the background scene must close')
end

--3. A group dropped on a scene window: each card the scene took closes.
do
    local env = Setup{group = true, toChat = true, took = {a = true, b = true, c = true}}
    env.drag(env.element)
    check(env.closed.a and env.closed.b and env.closed.c, 'every card a scene window took must close')
end

--4. A scene window that took only some: the rest stay on the table.
do
    local env = Setup{group = true, toChat = true, took = {a = true, b = true}}
    env.drag(env.element)
    check(env.closed.a and env.closed.b, 'the cards the scene took must close')
    check(not env.closed.c, 'a card the scene did not take must stay on the table')
end

--5. A single card (no group) still goes in alone.
do
    local env = Setup{group = false}
    env.dragging(env.element)
    check(#env.offered == 1 and env.offered[1].id == 'a', 'a single card offers only itself')
    env = Setup{group = false, background = true}
    env.drag(env.element)
    check(#env.dropped == 1 and env.dropped[1] == 'a', 'a single card drops only itself')
    check(env.closed.a and not env.closed.b, 'a single card closes only itself')
end

--6. A group dropped on the chat (not a scene): no card closes.
do
    local env = Setup{group = true, toChat = true}
    env.drag(env.element)
    check(next(env.closed) == nil, 'a chat drop must not close any card')
end

print('tabletop_group_scene_drop: ' .. checks .. ' checks passed')
