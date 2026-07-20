local mod = dmhub.GetModLoading()

--Tweak-placement mode for summoned creatures.
--
--When a summon behavior has tweakPlacement enabled, creatures are auto-placed
--around their anchor (usually the ability's target) and spawned hidden from
--players (invisibleToPlayers). This module then runs an interactive "rearrange"
--mode: the legal placement radius for each group is marked on the map, the
--pending creatures render ghosted (the DM-hidden 40% alpha look) with a
--four-way move icon, and the user may drag each creature within its group's
--radius. Moves are made with token:ChangeLocation, which is a raw location
--patch: no movement path is executed, so no triggers (opportunity attacks,
--auras, move events) fire. Pressing Continue reveals all creatures and play
--resumes.
--
--This is designed as a reusable model for any summoning that places creatures
--"around" something rather than asking the user to click out each placement.

CreaturePlacementTweaker = {
    --true while a tweak session is running; checked by token hud elements.
    active = false,

    --charid -> true for tokens pending placement in the current session.
    pendingTokens = {},
}

--is this token one of the creatures pending placement right now? Used by the
--token hud to swap the hidden-from-players eye for a move icon.
function CreaturePlacementTweaker.IsPending(token)
    if not CreaturePlacementTweaker.active then
        return false
    end
    return token ~= nil and token.valid and CreaturePlacementTweaker.pendingTokens[token.charid] == true
end

--a four-way move icon centered on tokens that are pending placement.
--
--NOTE: the icon itself starts with the "hidden" class, which deactivates the
--panel -- and a deactivated panel never receives think events, so it could
--never unhide itself. The think therefore lives on an always-active, invisible
--wrapper (no bgimage) that toggles the icon child.
TokenHud.RegisterPanel{
    id = "tweakPlacementIcon",
    create = function(token, sharedInfo)
        if token.isObject then
            return nil
        end

        return gui.Panel{
            interactable = false,
            blocksGameInteraction = false,
            halign = "center",
            valign = "center",
            width = 48,
            height = 48,
            thinkTime = 0.25,
            create = function(element)
                element:FireEvent("think")
            end,
            think = function(element)
                local icon = element.children[1]
                if icon == nil or not icon.valid then
                    return
                end
                --early-out field read keeps this trivial when no tweak is running.
                local pending = CreaturePlacementTweaker.active and CreaturePlacementTweaker.IsPending(token)
                icon:SetClass("hidden", not pending)
            end,

            gui.Panel{
                classes = {"hidden"},
                interactable = false,
                blocksGameInteraction = false,
                width = "100%",
                height = "100%",
                bgimage = "ui-icons/icon-translate.png",
                bgcolor = "#ffffffdd",
            },
        }
    end,
}

local function LocsEqual(a, b)
    return a.x == b.x and a.y == b.y and a.floor == b.floor
end

--is the loc occupied by any live token other than exceptToken?
local function LocOccupied(loc, exceptToken)
    for _,tok in ipairs(dmhub.allTokens) do
        if tok.valid and (exceptToken == nil or tok.charid ~= exceptToken.charid) then
            for _,l in ipairs(tok.locsOccupying) do
                if LocsEqual(l, loc) then
                    return true
                end
            end
        end
    end
    return false
end

--is the loc within the group's legal radius (measured from the anchor's footprint)?
local function LocInGroupRadius(group, loc)
    for _,anchorLoc in ipairs(group.anchorLocs) do
        if anchorLoc:DistanceInTiles(loc) <= group.radius then
            return true
        end
    end
    return false
end

--find which pending token (if any) occupies the given loc.
--returns token, group.
local function FindPendingTokenAt(groups, loc)
    for _,group in ipairs(groups) do
        for _,tok in ipairs(group.tokens) do
            if tok.valid then
                for _,l in ipairs(tok.locsOccupying) do
                    if LocsEqual(l, loc) then
                        return tok, group
                    end
                end
            end
        end
    end
    return nil, nil
end

--options:
--  groups: array of { tokens = CharacterToken[], anchorLocs = Loc[], radius = number, validLocs = Loc[] }
--          validLocs is used for the radius display; anchorLocs+radius gate drops.
--  message: instruction text shown above the map, e.g.
--           "2 Demon Ensnarers placed around targets. Rearrange positions before continuing."
--
--Must be called from within a coroutine (e.g. an ability behavior's Cast).
--Blocks until the user presses Continue, then reveals every token
--(invisibleToPlayers = false) and returns.
function CreaturePlacementTweaker.Run(options)
    local groups = options.groups or {}
    if #groups == 0 then
        return
    end

    CreaturePlacementTweaker.active = true
    CreaturePlacementTweaker.pendingTokens = {}
    for _,group in ipairs(groups) do
        for _,tok in ipairs(group.tokens) do
            if tok.valid then
                CreaturePlacementTweaker.pendingTokens[tok.charid] = true
            end
        end
    end

    --refresh token huds now that the session is active: removes the
    --hidden-from-players eye from pending tokens (see TokenUI.lua) and lets
    --the move icons appear immediately.
    game.UpdateCharacterTokens()

    local finished = false
    local dragToken = nil
    local dragGroup = nil
    local lastHoverLoc = nil

    --perimeter markers showing each group's legal placement radius.
    local radiusMarkers = {}
    for _,group in ipairs(groups) do
        if group.validLocs ~= nil and #group.validLocs > 0 then
            radiusMarkers[#radiusMarkers+1] = dmhub.MarkLocs{
                locs = group.validLocs,
                color = "#22cc66",
            }
        end
    end

    local hoverMarker = nil
    local function DestroyHoverMarker()
        if hoverMarker ~= nil then
            hoverMarker:Destroy()
            hoverMarker = nil
        end
    end

    local statusLabel

    local function StatusText()
        if dragToken ~= nil and dragToken.valid then
            return tr("Drag within radius to place summons.")
        end
        return tr("Drag creatures to move them. Press Continue to lock in positions.")
    end

    local function RefreshStatus()
        if statusLabel ~= nil and statusLabel.valid then
            statusLabel.text = StatusText()
        end
    end

    local function EndDrag(dropLoc)
        if dragToken == nil then
            return
        end

        if dropLoc ~= nil and dragToken.valid and dragGroup ~= nil
                and LocInGroupRadius(dragGroup, dropLoc) and not LocOccupied(dropLoc, dragToken) then
            dragToken:ChangeLocation(dropLoc)
            game.UpdateCharacterTokens()
        end

        dragToken = nil
        dragGroup = nil
        DestroyHoverMarker()
        RefreshStatus()
    end

    local pickerContent = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "center",
        interactable = true,

        gui.Label{
            halign = "center",
            width = "auto",
            minWidth = 260,
            maxWidth = 700,
            height = "auto",
            bold = true,
            fontSize = 16,
            textAlignment = "center",
            text = options.message or tr("Creatures placed. Rearrange positions before continuing."),
            vmargin = 2,
        },
        gui.Label{
            create = function(element)
                statusLabel = element
                element.text = StatusText()
            end,
            halign = "center",
            width = "auto",
            height = "auto",
            fontSize = 13,
            color = "#cccccc",
            textAlignment = "center",
            vmargin = 2,
        },
        gui.PrettyButton{
            text = tr("Continue"),
            halign = "center",
            vmargin = 6,
            width = 180,
            height = 40,
            fontSize = 20,
            click = function(element)
                finished = true
            end,
        },
    }

    local picker
    picker = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        halign = "left",
        valign = "top",
        bgcolor = "clear",
        interactable = true,
        mapfocus = true,
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_DIALOG,

        gui.TooltipFrame(pickerContent, { vmargin = 85 }),

        mappress = function(element, loc, point)
            if loc == nil or dragToken ~= nil then
                return
            end

            --begin dragging the pending creature under the cursor, if any.
            local tok, group = FindPendingTokenAt(groups, loc)
            if tok ~= nil then
                dragToken = tok
                dragGroup = group
                lastHoverLoc = loc
                RefreshStatus()
            end
        end,

        --the mouse was released: complete any drag at the last hovered space.
        unpress = function(element)
            EndDrag(lastHoverLoc)
        end,

        maphover = function(element, loc, point)
            DestroyHoverMarker()
            if loc == nil then
                return
            end

            lastHoverLoc = loc

            if dragToken ~= nil then
                local legal = dragToken.valid and dragGroup ~= nil and LocInGroupRadius(dragGroup, loc) and not LocOccupied(loc, dragToken)
                hoverMarker = dmhub.MarkLocs{
                    locs = { loc },
                    color = legal and "#ffffffcc" or "#cc2222cc",
                }
            else
                local tok = FindPendingTokenAt(groups, loc)
                if tok ~= nil then
                    hoverMarker = dmhub.MarkLocs{
                        locs = { loc },
                        color = "#ffffffcc",
                    }
                end
            end
        end,

        escape = function(element)
            --escape cancels an in-progress drag; it does not cancel the tweak mode.
            if dragToken ~= nil then
                dragToken = nil
                dragGroup = nil
                DestroyHoverMarker()
                RefreshStatus()
            end
        end,

        destroy = function(element)
            DestroyHoverMarker()
            for _,m in ipairs(radiusMarkers) do
                m:Destroy()
            end
            radiusMarkers = {}
        end,
    }

    gamehud.popupPanel:AddChild(picker)

    while not finished do
        coroutine.yield(0.1)
    end

    picker:DestroySelf()

    CreaturePlacementTweaker.active = false
    CreaturePlacementTweaker.pendingTokens = {}

    --lock in: reveal every pending creature to players.
    for _,group in ipairs(groups) do
        for _,tok in ipairs(group.tokens) do
            if tok.valid then
                tok.invisibleToPlayers = false
            end
        end
    end

    game.UpdateCharacterTokens()
end
