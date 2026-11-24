local mod = dmhub.GetModLoading()

--- @class TargetableObject : creature
--- @field new fun(o?: table): TargetableObject
--- @field custom_collision? ActivatedAbility Custom Collision Behavior cast when something collides with the object; replaces collision damage.
TargetableObject = RegisterGameType("TargetableObject", "creature")
TargetableObject.resourceid = CharacterResource.maliceResourceId

--GoblinScript evaluated with the "ability" symbol bound to an ability that
--does not normally target objects; if it passes, the ability can target this
--object anyway. Empty = normal targeting rules only. Consumed by
--ActivatedAbility:ObjectGrantsTargeting.
TargetableObject.additionalTargetFilter = ""

--When true this object is exempt from the standard collision damage exchange in
--both directions: the creature knocked into it takes no damage from the Collision
--global rule, and the object itself takes none either. Collision triggers still
--fire on both sides, so the object's Custom Collision Behavior (custom_collision)
--is the sole source of damage and effects for the crash. Consumed by
--TargetableObject.TokenSuppressesCollisionDamage.
TargetableObject.no_collision_damage = false

--When true, push, pull and slide never move this object.
TargetableObject.immune_to_forced_movement = false

--- @return boolean
function TargetableObject:CannotBeForceMoved()
    return self:try_get("immune_to_forced_movement", false) == true or creature.CannotBeForceMoved(self)
end

--True if the given token is an object flagged to skip standard collision damage.
--Safe to call with any token: nil, non-objects and plain creatures return false.
function TargetableObject.TokenSuppressesCollisionDamage(token)
    if token == nil or not token.isObject or token.properties == nil then
        return false
    end

    return token.properties:try_get("no_collision_damage", false) == true
end

--Custom banner text for hidden traps, keyed by the object's lower-cased
--name; any other hidden object with "trap" in its name gets "<Name>!".
--Only a trap the players cannot see gets one: a visible trap was walked
--into knowingly. bannerType defaults to "malice", the Director's menace.
TargetableObject.hiddenTrapBanners = {
    ["snare trap"] = { text = "Snare Trap!", subtitle = "You have stepped into a trap!" },
}

--The engine dispatches "pressureplate" on the mover's own client only, so
--each springing shows the (game-wide) banner once.
local function ShowHiddenTrapBanner(self, args)
    local token = dmhub.LookupToken(self)
    if token == nil or not token.objectInvisibleToPlayers then
        return
    end
    local name = nil
    pcall(function() name = token.objectInstance.description end)
    if type(name) ~= "string" or name == "" then
        name = token.name
    end
    local banner = TargetableObject.hiddenTrapBanners[string.lower(tostring(name or ""))]
    if banner == nil then
        --an unlisted hidden trap still announces itself, by its own name.
        --Objects have no trap flag, and hidden teleporters and switches are
        --pressure plates too, so only a name with "trap" in it counts.
        if type(name) ~= "string" or not string.find(string.lower(name), "trap", 1, true) then
            return
        end
        banner = { text = name .. "!", subtitle = "You have stepped into a trap!" }
    end
    local victim = args ~= nil and args.target ~= nil and dmhub.LookupToken(args.target) or nil
    DramaticBanner.Show{
        tokenid = victim ~= nil and victim.charid or nil,
        text = banner.text,
        subtitle = banner.subtitle,
        bannerType = banner.bannerType or "malice",
    }
end

--A hidden trap that has been sprung is no longer hidden: once a creature walks
--into a Spike Trap or Bear Trap, everyone can see it. Only objects whose own
--triggered ability springs on "pressureplate" count, so hidden plates that just
--fire something else (a Dart Trap's plate), teleporters and switches stay hidden.
--- @param self TargetableObject the sprung object's properties
local function RevealSprungTrap(self)
    if not self:HasTriggerFor("pressureplate") then
        return
    end
    local token = dmhub.LookupToken(self)
    if token == nil or not token.valid or not token.objectInvisibleToPlayers then
        return
    end
    local obj = token.objectInstance
    if obj == nil or not obj.valid then
        return
    end
    local coreComponent = obj:GetComponent("Core")
    if coreComponent == nil then
        return
    end
    coreComponent:SetProperty("sprite_invisible_to_players", false)
    obj:Upload()
end

--A trap set off by another object (a Dart Trap fired by a pressure plate)
--carries a triggered ability on this trigger. Link the two the usual way: in
--the plate's Trigger component, connect "Pressure Plate On" to any event the
--trap exposes. TargetableObject.FireLinkedTriggers then dispatches it.
TriggeredAbility.RegisterTrigger{
    id = "linkedtrigger",
    text = "Linked Trigger Activated",
    symbols = {
        target = {
            name = "Target",
            type = "creature",
            desc = "The creature that set off the linked trigger.",
        },
    },
}

--Object ids this object's Trigger component connects to for one of its
--triggers (e.g. "plateon"). The Lua view of the component hides connections,
--so they are read from the component's JSON.
--- @param objectToken CharacterToken
--- @param triggerid string
--- @return string[]
function TargetableObject.GetLinkedObjectIds(objectToken, triggerid)
    local result = {}
    local obj = objectToken.objectInstance
    if obj == nil then
        return result
    end
    for key,_ in pairs(obj.components or {}) do
        local doc = obj:ComponentToJson(key)
        if type(doc) == "table" and doc["@class"] == "ObjectComponentTrigger" then
            for _,trigger in ipairs(doc.triggers or {}) do
                if trigger.triggerid == triggerid then
                    for _,connection in ipairs(trigger.connections or {}) do
                        if type(connection.objid) == "string" then
                            result[#result+1] = connection.objid
                        end
                    end
                end
            end
        end
    end
    return result
end

--- Fires "linkedtrigger" on every object this object's triggerid links to,
--- with the creature that set it off as the target. An object linked through
--- several of the given triggers still fires once.
--- @param objectToken CharacterToken the plate (or switch) that was set off
--- @param triggerid string|string[] the Trigger component trigger(s), e.g. "plateon"
--- @param target creature|nil the creature that set it off
function TargetableObject.FireLinkedTriggers(objectToken, triggerid, target)
    local triggerids = triggerid
    if type(triggerids) == "string" then
        triggerids = {triggerids}
    end
    local wanted = {}
    local any = false
    for _,tid in ipairs(triggerids) do
        for _,id in ipairs(TargetableObject.GetLinkedObjectIds(objectToken, tid)) do
            wanted[id] = true
            any = true
        end
    end
    if not any then
        return
    end
    for _,tok in ipairs(dmhub.allObjectTokens or {}) do
        local obj = tok.valid and tok.objectInstance or nil
        if obj ~= nil and wanted[obj.id] and tok.properties ~= nil then
            local props = tok.properties --[[@as TargetableObject]]
            if props:HasTriggerFor("linkedtrigger") then
                props:DispatchEvent("linkedtrigger", {target = target})
            end
        end
    end
end

--Trigger ids a switch or plate links through: a Button's Pressed / Switch On /
--Switch Off and a pressure plate's Pressure Plate On.
TargetableObject.setOffTriggerIds = {"press", "buttonon", "buttonoff", "plateon"}

--- Sets off a switch or pressure plate from an ability (a Switch's maneuver, a
--- failed Deactivate). A Button component is pressed, so the engine's own links
--- (Make Visible, door toggles, sounds) fire too; then every linked object's
--- "linkedtrigger" ability fires. A plate's engine links only fire on a real step.
--- @param objectToken CharacterToken the switch or plate
--- @param setter creature|nil the creature that set it off
function TargetableObject.SetOff(objectToken, setter)
    local obj = objectToken.objectInstance
    if obj ~= nil and obj.valid then
        local button = obj:GetComponent("Button")
        if button ~= nil then
            button:Execute("Press Button")
        end
    end
    TargetableObject.FireLinkedTriggers(objectToken, TargetableObject.setOffTriggerIds, setter)
end

--Ability behavior "Set Off Linked Mechanisms": the targeted switch or plate
--fires everything it is linked to, as if pressed or stepped on. With
--springTarget, the targeted mechanism itself springs instead (its own Linked
--Trigger Activated ability), e.g. a failed Deactivate on a Portcullis.
--- @class ActivatedAbilitySetOffLinksBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilitySetOffLinksBehavior
--- @field springTarget boolean
ActivatedAbilitySetOffLinksBehavior = RegisterGameType("ActivatedAbilitySetOffLinksBehavior", "ActivatedAbilityBehavior")
ActivatedAbilitySetOffLinksBehavior.summary = "Set Off Linked Mechanisms"
ActivatedAbilitySetOffLinksBehavior.springTarget = false

ActivatedAbility.RegisterType{
    id = "setofflinks",
    text = "Set Off Linked Mechanisms",
    createBehavior = function()
        return ActivatedAbilitySetOffLinksBehavior.new{}
    end,
}

function ActivatedAbilitySetOffLinksBehavior:Cast(ability, casterToken, targets, options)
    ability:CommitToPaying(casterToken, options)
    for _,target in ipairs(targets) do
        local tok = target.token
        if tok ~= nil and tok.valid and tok.isObject then
            local ok, err = pcall(function()
                if self.springTarget then
                    local props = tok.properties --[[@as TargetableObject|nil]]
                    if props ~= nil and props:HasTriggerFor("linkedtrigger") then
                        props:DispatchEvent("linkedtrigger", {target = casterToken.properties})
                    end
                else
                    TargetableObject.SetOff(tok, casterToken.properties)
                end
            end)
            if not ok then
                printf("TargetableObject: setting off linked mechanisms failed: %s", tostring(err))
            end
        end
    end
end

function ActivatedAbilitySetOffLinksBehavior:EditorItems(parentPanel)
    local result = {}
    self:ApplyToEditor(parentPanel, result)
    self:FilterEditor(parentPanel, result)
    result[#result+1] = gui.Check{
        text = "Spring the Target Itself",
        value = self.springTarget,
        change = function(element)
            self.springTarget = element.value
        end,
    }
    return result
end

--Ability behavior "Mechanism Step": one step of a mechanism springing (a
--Portcullis dropping, a Ram slamming out). List the steps in order in the
--mechanism's own triggered ability. Every step except "slideaside" acts on the
--mechanism itself (the ability's caster); "slideaside" moves the targets.
--Directions are the object's own, at rotation 0: it moves forward toward the
--west (a ram's head is drawn on the left), and its sides are north and south
--(a portcullis drawn left to right). They turn with the object's rotation.
--- @class ActivatedAbilityMechanismBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityMechanismBehavior
--- @field mode string which step this is (see ActivatedAbilityMechanismBehavior.modes)
--- @field distance number squares moved (advance) or looked ahead (targetpath)
ActivatedAbilityMechanismBehavior = RegisterGameType("ActivatedAbilityMechanismBehavior", "ActivatedAbilityBehavior")
ActivatedAbilityMechanismBehavior.summary = "Mechanism Step"
ActivatedAbilityMechanismBehavior.mode = "reveal"
ActivatedAbilityMechanismBehavior.distance = 3

ActivatedAbilityMechanismBehavior.modes = {
    {id = "reveal", text = "Reveal"},
    {id = "targetfootprint", text = "Target Everything Beneath"},
    {id = "targetpath", text = "Target Everything in Its Path"},
    {id = "slideaside", text = "Slide Targets to a Random Side"},
    {id = "advance", text = "Move Forward"},
    {id = "solid", text = "Become Solid"},
    {id = "reset", text = "Reset"},
    {id = "remove", text = "Remove"},
    {id = "fallen", text = "Place Fallen Look"},
}

--"fallen" places this object (e.g. a collapsed pillar picture) along the
--ability's target area, turned to lie along it. Empty = nothing placed.
ActivatedAbilityMechanismBehavior.objectid = ""
--Size to place it at; 0 keeps the object's own scale. The artist's prints
--are 300 px per square but were uploaded smaller, so each needs its own.
ActivatedAbilityMechanismBehavior.fallenScale = 0

ActivatedAbility.RegisterType{
    id = "mechanism",
    text = "Mechanism Step",
    createBehavior = function()
        return ActivatedAbilityMechanismBehavior.new{}
    end,
}

local function MechanismLocKey(x, y, floor)
    return string.format("%d:%d:%d", x, y, floor or 0)
end

--- Turns an object-local direction by the object's rotation (counter-clockwise,
--- as object rotation is) and snaps it to the grid (-1, 0 or 1 on each axis).
--- @param x number
--- @param y number
--- @param degrees number
--- @return integer, integer
local function MechanismRotateDir(x, y, degrees)
    local r = math.rad(degrees or 0)
    local c, s = math.cos(r), math.sin(r)
    return math.floor(x*c - y*s + 0.5), math.floor(x*s + y*c + 0.5)
end

--- @param objectToken CharacterToken
--- @return number
local function MechanismRotation(objectToken)
    local obj = objectToken.objectInstance
    if obj == nil then
        return 0
    end
    return tonumber(obj.rotation) or 0
end

--- The mechanism's squares, shifted by (dx, dy), as a set keyed by MechanismLocKey.
--- @param objectToken CharacterToken
--- @param dx integer
--- @param dy integer
--- @param into table|nil set to add to
--- @return table<string, boolean>
local function MechanismSquares(objectToken, dx, dy, into)
    local result = into or {}
    for _,loc in ipairs(objectToken.locsOccupying or {}) do
        result[MechanismLocKey(loc.x + dx, loc.y + dy, loc.floor)] = true
    end
    return result
end

--- Creatures and attackable objects with any square in `squares`, except the mechanism.
--- @param squares table<string, boolean>
--- @param mechanismToken CharacterToken
--- @param creaturesOnly boolean|nil
--- @return {loc: Loc, token: CharacterToken}[]
local function MechanismTokensOn(squares, mechanismToken, creaturesOnly)
    local result = {}
    for _,tok in ipairs(dmhub.allTokensIncludingObjects or {}) do
        local counts = tok.valid and tok.charid ~= mechanismToken.charid
        if counts and tok.isObject then
            counts = (not creaturesOnly) and tok.isAttackableObject
        end
        if counts then
            for _,loc in ipairs(tok.locsOccupying or {}) do
                if squares[MechanismLocKey(loc.x, loc.y, loc.floor)] then
                    result[#result+1] = {loc = tok.loc, token = tok}
                    break
                end
            end
        end
    end
    return result
end

--- Swaps the cast's targets for `newTargets`, so the steps after this one (the
--- power roll) hit them. Same approach as Manipulate Targets' "replace".
local function MechanismReplaceTargets(options, newTargets)
    if options.targets == nil then
        return
    end
    for i = #options.targets, 1, -1 do
        options.targets[i] = nil
    end
    for _,t in ipairs(newTargets) do
        options.targets[#options.targets+1] = t
    end
end

--- @param objectToken CharacterToken
--- @param componentName string
--- @param field string
--- @param value any
local function MechanismSetComponent(objectToken, componentName, field, value)
    local obj = objectToken.objectInstance
    if obj == nil or not obj.valid then
        return
    end
    local component = obj:GetComponent(componentName)
    if component == nil then
        return
    end
    component:SetProperty(field, value)
    --Only this component: a whole-object upload carries the object's position
    --and would undo a slide still in flight.
    component:Upload()
end

--- Moves the mechanism by (dx, dy) squares, sliding it on every client.
--- @param objectToken CharacterToken
--- @param dx integer
--- @param dy integer
local function MechanismSlide(objectToken, dx, dy)
    if dx == 0 and dy == 0 then
        return
    end
    local obj = objectToken.objectInstance
    local goalX, goalY = nil, nil
    if obj ~= nil then
        goalX, goalY = obj.x + dx, obj.y + dy
    end
    objectToken:Move(objectToken.loc:dir(dx, dy), {
        straightline = true,
        ignorecreatures = true,
        ignoreFalling = true,
        freeMovement = true,
        objectSpeed = 12,
        objectEase = "in",
    })

    --Wait for the slide to finish: an object upload while it is still moving
    --(the next step switching its Solid on) puts it back where it started.
    if obj ~= nil and goalX ~= nil and coroutine.isyieldable() then
        local waited = 0
        while waited < 3 and obj.valid and (obj.x ~= goalX or obj.y ~= goalY) do
            coroutine.yield(0.05)
            waited = waited + 0.05
        end
    end
end

function ActivatedAbilityMechanismBehavior:Cast(ability, casterToken, targets, options)
    ability:CommitToPaying(casterToken, options)

    local mechanism = casterToken
    if mechanism == nil or not mechanism.valid or not mechanism.isObject then
        return
    end

    local mode = self.mode
    local rotation = MechanismRotation(mechanism)
    local fx, fy = MechanismRotateDir(-1, 0, rotation)
    local sx, sy = MechanismRotateDir(0, 1, rotation)
    local distance = math.max(0, math.floor(tonumber(self.distance) or 0))

    if mode == "reveal" then
        if mechanism.objectInvisibleToPlayers then
            MechanismSetComponent(mechanism, "Hover Text", "hideFromPlayers", false)
            MechanismSetComponent(mechanism, "Core", "sprite_invisible_to_players", false)
        end

    elseif mode == "targetfootprint" then
        MechanismReplaceTargets(options, MechanismTokensOn(MechanismSquares(mechanism, 0, 0), mechanism))

    elseif mode == "targetpath" then
        --The squares it sweeps through: each step's squares, minus where it starts.
        local path = {}
        for k = 1, distance do
            MechanismSquares(mechanism, fx*k, fy*k, path)
        end
        for key,_ in pairs(MechanismSquares(mechanism, 0, 0)) do
            path[key] = nil
        end
        MechanismReplaceTargets(options, MechanismTokensOn(path, mechanism))

        --Pushes go the way the mechanism is moving: from a point far behind it.
        if options.symbols ~= nil then
            options.symbols.forcedMovementOrigin = mechanism.loc:dir(-fx*30, -fy*30)
            options.symbols.forcedMovementOriginTokenId = nil
        end

    elseif mode == "slideaside" then
        --Each target goes to one side of the mechanism or the other, at random,
        --just far enough to be clear of it; the other side if that one is taken.
        local footprint = MechanismSquares(mechanism, 0, 0)
        for _,target in ipairs(targets) do
            local tok = target.token
            if tok ~= nil and tok.valid and not tok.isObject then
                local first = cond(math.random(2) == 1, 1, -1)
                for _,sign in ipairs({first, -first}) do
                    local dest = nil
                    for k = 1, 4 do
                        local candidate = tok.loc:dir(sx*sign*k, sy*sign*k)
                        local clear = true
                        local squares = {}
                        for _,loc in ipairs(tok:LocsOccupyingWhenAt(candidate) or {}) do
                            local key = MechanismLocKey(loc.x, loc.y, loc.floor)
                            squares[key] = true
                            if footprint[key] or not loc.isOnMap then
                                clear = false
                            end
                        end
                        if clear then
                            local occupants = MechanismTokensOn(squares, tok, true)
                            if #occupants == 0 then
                                dest = candidate
                            end
                            break
                        end
                    end
                    if dest ~= nil then
                        local path = tok:Move(dest, {straightline = true, ignorecreatures = true, freeMovement = true})
                        if path == nil then
                            tok:Teleport(dest.withGroundAltitude)
                        end
                        break
                    end
                end
            end
        end

    elseif mode == "advance" then
        --Moves forward up to `distance` squares, stopping short of a creature
        --still in the way (one slid aside into the path, or too big to push).
        local steps = 0
        for k = 1, distance do
            local squares = MechanismSquares(mechanism, fx*k, fy*k)
            local blocked = #MechanismTokensOn(squares, mechanism, true) > 0
            for _,loc in ipairs(mechanism.locsOccupying or {}) do
                if not loc:dir(fx*k, fy*k).isOnMap then
                    blocked = true
                end
            end
            if blocked then
                break
            end
            steps = k
        end
        if steps > 0 then
            --Remember where it started, so Reset can bring it back.
            local props = mechanism.properties
            if props ~= nil and props:try_get("mechanismHome") == nil then
                local home = {x = mechanism.loc.x, y = mechanism.loc.y}
                mechanism:ModifyProperties{
                    description = "Mechanism moved",
                    undoable = false,
                    execute = function()
                        props.mechanismHome = home
                    end,
                }
            end
            MechanismSlide(mechanism, fx*steps, fy*steps)
        end

    elseif mode == "solid" then
        MechanismSetComponent(mechanism, "Solid", "disabled", false)

    elseif mode == "reset" then
        --Back where it started and no longer solid, ready to spring again.
        MechanismSetComponent(mechanism, "Solid", "disabled", true)
        local props = mechanism.properties
        local home = props ~= nil and props:try_get("mechanismHome") or nil
        if home ~= nil then
            MechanismSlide(mechanism, home.x - mechanism.loc.x, home.y - mechanism.loc.y)
            mechanism:ModifyProperties{
                description = "Mechanism reset",
                undoable = false,
                execute = function()
                    --Read it fresh: the slide's update replaces the properties table.
                    local current = mechanism.properties
                    if current ~= nil then
                        current.mechanismHome = nil
                    end
                end,
            }
        end

    elseif mode == "remove" then
        --Gone without its Destroyed trigger (a pillar that has already fallen).
        if mechanism.objectComponent ~= nil then
            mechanism.objectComponent:OnDeath()
        end

    elseif mode == "fallen" then
        --The picture's long side is drawn left to right, so it is turned to the
        --angle from the area's near end (by the line's origin) to its far end.
        local area = options.targetArea
        local locations = area ~= nil and area.locations or nil
        if self.objectid == "" or locations == nil or #locations == 0 then
            return
        end
        local nearLoc, farLoc = locations[1], locations[#locations]
        local origin = area.origin
        if origin ~= nil then
            local nearDist, farDist = nil, nil
            for _,loc in ipairs(locations) do
                local d = loc:DistanceInTiles(origin)
                if nearDist == nil or d < nearDist then
                    nearDist, nearLoc = d, loc
                end
                if farDist == nil or d > farDist then
                    farDist, farLoc = d, loc
                end
            end
        end
        local minx, maxx, miny, maxy = nil, nil, nil, nil
        for _,loc in ipairs(locations) do
            minx = math.min(minx or loc.x, loc.x)
            maxx = math.max(maxx or loc.x, loc.x)
            miny = math.min(miny or loc.y, loc.y)
            maxy = math.max(maxy or loc.y, loc.y)
        end
        local floor = game.currentMap:GetFloorFromLoc(nearLoc)
        if floor == nil then
            return
        end
        local obj = floor:SpawnObjectLocal(self.objectid)
        if obj == nil then
            return
        end
        obj.x = (minx + maxx)/2
        obj.y = (miny + maxy)/2
        obj.rotation = math.deg(math.atan(farLoc.y - nearLoc.y, farLoc.x - nearLoc.x))
        if self.fallenScale > 0 then
            obj.scale = self.fallenScale
        end
        obj:Upload()
    end
end

function ActivatedAbilityMechanismBehavior:EditorItems(parentPanel)
    local result = {}
    self:ApplyToEditor(parentPanel, result)
    self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Step:",
        },
        gui.Dropdown{
            classes = {"formDropdown"},
            options = ActivatedAbilityMechanismBehavior.modes,
            idChosen = self.mode,
            change = function(element)
                ---@cast element Dropdown
                self.mode = tostring(element.idChosen)
            end,
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Distance:",
        },
        gui.Input{
            classes = {"formInput"},
            text = tostring(self.distance),
            change = function(element)
                self.distance = tonumber(element.text) or self.distance
                element.text = tostring(self.distance)
            end,
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Fallen Object Id:",
        },
        gui.Input{
            classes = {"formInput"},
            text = self.objectid,
            change = function(element)
                self.objectid = element.text
            end,
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Fallen Scale:",
        },
        gui.Input{
            classes = {"formInput"},
            text = tostring(self.fallenScale),
            change = function(element)
                self.fallenScale = tonumber(element.text) or self.fallenScale
                element.text = tostring(self.fallenScale)
            end,
        },
    }

    return result
end

--Hooked on creature.DispatchEvent, not TargetableObject:DispatchEvent: the
--engine's pressure plate looks DispatchEvent up on the MOVER's properties and
--calls it with the object's properties as self, so the object's own
--override never runs. Chained like every other DispatchEvent wrapper.
local g_baseDispatchEvent = creature.DispatchEvent
function creature:DispatchEvent(eventName, args)
    if eventName == "pressureplate" and self.isMapObject then
        local ok, err = pcall(ShowHiddenTrapBanner, self, args)
        if not ok then
            printf("TargetableObject: hidden trap banner failed: %s", tostring(err))
        end
    end
    local result = g_baseDispatchEvent(self, eventName, args)
    --after the plate's own triggers, so its banner and effects come first.
    if eventName == "pressureplate" and self.isMapObject then
        local ok, err = pcall(function()
            local token = dmhub.LookupToken(self)
            if token ~= nil then
                TargetableObject.FireLinkedTriggers(token, "plateon", args ~= nil and args.target or nil)
            end
        end)
        if not ok then
            printf("TargetableObject: linked triggers failed: %s", tostring(err))
        end

        ok, err = pcall(RevealSprungTrap, self)
        if not ok then
            printf("TargetableObject: revealing a sprung trap failed: %s", tostring(err))
        end
    end
    return result
end

function TargetableObject:DispatchEvent(eventName, args)
    creature.DispatchEvent(self, eventName, args)
end

--Lets the shared creature damage path tell objects apart (see creature.isMapObject).
TargetableObject.isMapObject = true

--- Fires an event on every map object that has a trigger for it: a table-wide
--- moment (a new round, the end of combat) or the end of one creature's turn.
--- Objects have no initiative entry, so the round and combat code that walks the
--- initiative queue never reaches them. Only objects with a matching trigger are
--- dispatched to: a map can hold hundreds of them, and an event with no subject
--- also notifies every token.
--- @param eventName string a trigger id, e.g. "beginround" or "endcombat"
--- @param info nil|table event arguments (copied per object); info.subject makes it an event about that creature
function TargetableObject.DispatchToObjects(eventName, info)
    local aboutOther = info ~= nil and info.subject ~= nil
    for _, tok in ipairs(dmhub.allObjectTokens or {}) do
        --An object only has properties when it has a Targetable component.
        local props = tok.valid and tok.properties --[[@as TargetableObject|nil]] or nil
        if props ~= nil and props:HasTriggerFor(eventName, aboutOther) then
            props:DispatchEvent(eventName, info ~= nil and shallow_copy_table(info) or {})
        end
    end
end

--Map objects that act at the start of every turn (a Rapid Repeating Ram
--resetting) use this trigger. It fires once per turn taken in initiative, on
--the client that starts the turn, after that turn's own start-of-turn triggers.
TriggeredAbility.RegisterTrigger{
    id = "objectturnstart",
    text = "Start of Any Turn (Objects)",
}

do
    local queue = rawget(_G, "InitiativeQueue")
    if queue ~= nil and queue.BeginTurnForEntry ~= nil then
        local g_baseBeginTurnForEntry = queue.BeginTurnForEntry
        queue.BeginTurnForEntry = function(initiativeid)
            g_baseBeginTurnForEntry(initiativeid)
            local ok, err = pcall(TargetableObject.DispatchToObjects, "objectturnstart")
            if not ok then
                printf("TargetableObject: start of turn for objects failed: %s", tostring(err))
            end
        end
    end
end

--Map objects that act at the end of each creature's turn (a lit grenade's fuse) use this
--trigger. Its subject is the creature whose turn ended, so pick e.g. "Any Hero (Not Self)":
--with "Self" it never fires. Make it Automatic and Local so the ending turn waits for it.
TriggeredAbility.RegisterTrigger{
    id = "objectturnend",
    text = "End of Any Turn (Objects)",
}

local g_baseEndTurn = creature.EndTurn
function creature:EndTurn(token)
    g_baseEndTurn(self, token)
    --If only this file is reloaded, the old copy of this function is still wrapped inside
    --the new one. It stops here so objects hear each turn end once, not twice.
    if mod.unloaded then
        return
    end
    local ok, err = pcall(TargetableObject.DispatchToObjects, "objectturnend", { subject = self })
    if not ok then
        printf("TargetableObject: end of turn for objects failed: %s", tostring(err))
    end
end

--True if any of this object's modifiers has a triggered ability for eventName.
--Pass aboutOther when the event is about another creature (it has a subject), so
--triggers with a subject like "Any Hero (Not Self)" count, as they do for creatures.
--- @param eventName string
--- @param aboutOther? boolean
--- @return boolean
function TargetableObject:HasTriggerFor(eventName, aboutOther)
    for _, entry in ipairs(self:GetActiveModifiers()) do
        if entry.mod:HasTriggeredEvent(self, eventName, aboutOther) then
            return true
        end
    end
    return false
end

--At 0 Stamina the object fires "objectdestroyed" (the Destroyed trigger), and only
--then runs the engine's onDeath (delete/disable/open). With a Destroyed trigger the
--onDeath waits until that cast has finished, so a pillar is still on the map while
--its Toppling Pillar resolves. The wait is a detached coroutine: the attack that
--broke the object carries on without waiting for the object's own ability.
function TargetableObject.TakeDamage(self, amount, note, info)
    local staminaBefore = self:CurrentHitpoints()
    creature.TakeDamage(self, amount, note, info)
    local staminaAfter = self:CurrentHitpoints()
    if staminaBefore > 0 and staminaAfter <= 0 then
        local token = dmhub.LookupToken(self)
        --Damage is only dealt to properties that belong to a live object token.
        ---@cast token -nil

        if not self:HasTriggerFor("objectdestroyed") then
            token.objectComponent:OnDeath()
            return
        end

        info = info or {}
        local args = {
            damage = cond(type(amount) == "number", amount, staminaBefore - staminaAfter),
            damagetype = info.damagetype or "untyped",
            attacker = info.attacker,
            hasattacker = info.attacker ~= nil,
        }

        local charid = token.charid
        dmhub.Coroutine(function()
            self:DispatchEventAndWait("objectdestroyed", args, {ignoreTurn = true})

            --Re-resolve: the token may have been replaced by a synced write while we waited.
            local tok = dmhub.GetTokenById(charid) or dmhub.LookupToken(self)
            if tok ~= nil and tok.valid and tok.objectComponent ~= nil then
                tok.objectComponent:OnDeath()
            end
        end)
    end
end

--Engine hook (ObjectComponentTargetable.GenerateOperateCommand), asked while the
--object is hovered: can `token` operate this object (a Field Ballista with
--adjacent-creature abilities)? Returns the hover text and cursor to show, or
--nil for no command. Clicking runs TargetableObject:Operate.
--- @param token CharacterToken the local user's current token
--- @param objectToken CharacterToken this object's token
--- @return nil|{text: string, cursor: string}
function TargetableObject:GetOperateCommand(token, objectToken)
    local actionBar = rawget(_G, "DrawSteelActionBar")
    if actionBar == nil or token == nil or not token.canControlAsUser then
        return nil
    end

    local operation = actionBar.GetOperation()
    if operation ~= nil and operation.object.charid == objectToken.charid then
        return nil
    end

    if not ActivatedAbility.CanOperate(token, objectToken) then
        return nil
    end

    --An object with just one ability (a Candelabra's Throw) names it: the
    --click casts it directly. When the rules won't allow it right now, the
    --hover says why and the click does nothing.
    local single = ActivatedAbility.GetSingleAdjacentAbility(objectToken, token)
    if single ~= nil then
        local reason = ActivatedAbility.AdjacentAbilityBlockedReason(single, token, objectToken)
        return {
            text = cond(reason == nil, single.name, string.format("%s (%s)", single.name, reason)),
            cursor = "hand",
        }
    end

    --"Use" for an object that only grants abilities (a Candelabra to throw).
    local verb = cond(ActivatedAbility.HasOperatedAbilities(objectToken), "Operate", "Use")
    return {
        text = string.format("%s %s", verb, creature.GetTokenDescription(objectToken)),
        cursor = "hand",
    }
end

--Engine hook: the Operate command was clicked. An object with one ability
--casts it straight away (Escape cancels; the action bar is never taken
--over); one with several switches the action bar to them, operated by `token`.
--- @param token CharacterToken
--- @param objectToken CharacterToken
function TargetableObject:Operate(token, objectToken)
    local actionBar = rawget(_G, "DrawSteelActionBar")
    if actionBar == nil then
        return
    end

    local single = ActivatedAbility.GetSingleAdjacentAbility(objectToken, token)
    if single ~= nil then
        if ActivatedAbility.AdjacentAbilityBlockedReason(single, token, objectToken) == nil then
            actionBar.CastAdjacentAbility(token, objectToken, single)
        end
        return
    end

    actionBar.BeginOperating(token, objectToken)
end

dmhub.CreateTargetableComponent = function()
    return TargetableObject.new{
        attributes = creature.CreateAttributes(),
    }
end

--True when this "creature" is really a map object (a Targetable component on a
--LevelObject: a hazard, destructible prop, wall voxel...) rather than an actual
--creature. Objects bind as creature-typed properties and are indistinguishable
--from creatures in GoblinScript otherwise, which matters for effects that
--should treat the battlefield's furniture differently from its combatants.
--
--The motivating case: an area hazard that grants its allies cover via an aura.
--The aura's "friends" filter with no caster means "everything not aligned with
--the players", which includes the hazard object itself, so the hazard was
--granting itself cover. Putting `not IsObject` on the granting modifier's
--filterCondition withholds it from the object while leaving the aura otherwise
--untouched. Filtering the MODIFIER rather than narrowing the aura matters:
--scripts that watch their own object's auras to detect that the registration
--is still live rely on the aura continuing to apply to the object.
--
--Fails safe: a creature whose token cannot be resolved reads as NOT an object,
--so filters written against this keep applying to real creatures.
GameSystem.RegisterGoblinScriptField{
    name = "Is Object",

    type = "boolean",
    desc = "True if this is a map object (such as a hazard, destructible prop, or wall voxel) rather than a real creature.",
    examples = {"not IsObject"},

    calculate = function(c)
        local token = dmhub.LookupToken(c)
        return token ~= nil and token.valid and token.objectInstance ~= nil
    end,
}

--Wall voxels spawned by abilities are stamped with the creating creature's
--charid in the "wallcreator" property (see AbilityBuildWall.lua). Expose it to
--GoblinScript hashed the same way as creature ids, so targeting filters can
--say e.g. "Target.WallCreator = Caster.ID" (the Wallmaster targeting only
--walls made by its own Living Labyrinth trait). Registered on creature (the
--base type of TargetableObject); non-walls return 0, which never matches an id.
GameSystem.RegisterGoblinScriptField{
    name = "Wall Creator",

    type = "number",
    desc = "The id of the creature that created this wall object, or 0 if it was not created by a creature. Compare against a creature's ID field.",
    examples = {"Target.WallCreator = Caster.ID"},

    calculate = function(c)
        return Utils.HashGuidToNumber(c:try_get("wallcreator", ""))
    end,
}

--The creature whose ability made this object, or nil if none did.
local function GetObjectCreator(c)
    local creatorid = c:try_get("objectcreator") or c:try_get("wallcreator")
    if creatorid == nil then
        return nil
    end

    local creatorToken = dmhub.GetCharacterById(creatorid)
    if creatorToken == nil then
        return nil
    end

    return creatorToken.properties
end

--Lets an object's formulas use its creator's stats, such as
--Caster.Creator.Reason for extra damage when something hits a wall.
GameSystem.RegisterGoblinScriptField{
    name = "Creator",

    type = "creature",
    desc = "The creature that created this object with an ability.\n\n<color=#ffaaaa><i>This field is only available for objects created by a creature's ability.</i></color>",
    examples = {"Caster.Creator.Reason", "Target.Creator.ID = Caster.ID"},

    calculate = GetObjectCreator,
}

--True for the topmost wall voxel of its tile's column. Wall abilities that
--detach/topple "a square of wall" (e.g. the Wallmaster's Wall Slam) use this
--to only offer the exposed top cube of a stacked column as a target.
GameSystem.RegisterGoblinScriptField{
    name = "Wall Top",

    type = "boolean",
    desc = "True if this object is the topmost wall voxel on its tile. Also true for anything that is not a wall voxel.",
    examples = {"Target.WallCreator = Caster.ID and Target.WallTop"},

    calculate = function(c)
        local token = dmhub.LookupToken(c)
        if token == nil or not token.valid or token.objectInstance == nil then
            return true
        end

        local loc = token.loc
        local voxelFloor = game.currentMap:GetFloorFromLoc(loc)
        if voxelFloor == nil then
            return true
        end

        local voxels = voxelFloor:GetWallVoxelsAt(loc)
        if voxels == nil or #voxels == 0 then
            return true
        end

        local top = voxels[#voxels]
        return top ~= nil and top.objid == token.objectInstance.objid
    end,
}

--The custom behavior runs alongside the standard damage rather than replacing it:
--only "No Collision Damage" opts the object out of taking collision damage.
function TargetableObject:OnCollide(collidingToken, symbols)
    local token = dmhub.LookupToken(self)
    if token == nil then
        return
    end

    if self:has_key("custom_collision") then
        --Collision formulas can write Creator as a short form of Caster.Creator.
        local castSymbols = {
            creator = GetObjectCreator(self),
        }

        self.custom_collision:Cast(token, { { token = collidingToken } }, { symbols = castSymbols })
    end

    if symbols.speed and not self:try_get("no_collision_damage", false) then
        token:ModifyProperties{
            description = "Collision",
            undoable = false,
            execute = function()
                token.properties:InflictDamageInstance(symbols.speed, "untyped", {}, "Collision", {})
            end,
        }
    end
end

function TargetableObject.CreatePropertiesEditor(component)
    return TargetableObject.CreateMultiPropertiesEditor{component}
end

function TargetableObject.CreateMultiPropertiesEditor(components)
    --local self = component.properties
    print("Target:: CreatePropertiesEditor", components)
    local resultPanel
    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        styles = {
            {
                classes = {"field-editor-label"},
                fontSize = 12,
                minFontSize = 10,
                width = "auto",
                height = "auto",
                maxWidth = 120,
            },
            {
                classes = {"field-editor-panel"},
                flow = "horizontal",
            },
            {
                classes = {"field-editor-input"},
                fontSize = 12,
            },
        },
        gui.Panel{
            classes = {"field-editor-panel"},
            flow = "horizontal",
            minHeight = 0,
            gui.Label{
                classes = {"field-editor-label"},
                text = "Stamina",
                halign = "left",
                valign = "center",
            },
            gui.Input{
                classes = {"field-editor-input"},
                halign = "right",
                valign = "center",
                text = tostring((components[1].properties.max_hitpoints or 1) - (components[1].properties.damage_taken or 0)),
                width = 30,
                characterLimit = 3,
                events = {
                    refresh = function(element)
                        local stamina = (components[1].properties.max_hitpoints or 1) - (components[1].properties.damage_taken or 0)
                        element.text = tostring(stamina)
                    end,
                    change = function(element)
                        local n = tonumber(element.text)
                        if n == nil then
                            element:FireEvent("refresh")
                            return
                        end
                        local damage_taken = (components[1].properties.max_hitpoints or 1) - n
                        if damage_taken < 0 then
                            damage_taken = 0
                        end
                        for _, component in ipairs(components) do
                            component:BeginChanges()
                            component.properties.damage_taken = damage_taken
                            component:CompleteChanges("Change object stamina")
                        end
                        resultPanel:FireEventTree("refresh")
                    end,
                },
            },
            gui.Label{
                text = "/",
                fontSize = 14,
                height = "auto",
                width = "auto",
                halign = "right",
                valign = "center",
                hmargin = 8,
            },
            gui.Input{
                classes = {"field-editor-input"},
                text = tostring(components[1].properties.max_hitpoints or 1),
                width = 30,
                halign = "right",
                valign = "center",
                characterLimit = 3,
                events = {
                    refresh = function(element)
                        element.text = tostring(components[1].properties.max_hitpoints or 1)
                    end,
                    change = function(element)
                        local n = tonumber(element.text)
                        if n == nil then
                            element:FireEvent("refresh")
                            return
                        end
                        for _, component in ipairs(components) do
                            component:BeginChanges()
                            component.properties.max_hitpoints = n
                            component:CompleteChanges("Change object stamina")
                        end
                        resultPanel:FireEventTree("refresh")
                    end,
                },
            }
        },

        gui.Panel{
            classes = {"field-editor-panel"},
            flow = "vertical",
            minHeight = 0,
            gui.Label{
                classes = {"field-editor-label"},
                text = "Also Targetable By:",
                halign = "left",
            },
            gui.GoblinScriptInput{
                width = 250,
                halign = "left",
                value = components[1].properties:try_get("additionalTargetFilter", ""),
                change = function(element)
                    for _, component in ipairs(components) do
                        component:BeginChanges()
                        component.properties.additionalTargetFilter = element.value
                        component:CompleteChanges("Change additional targeting filter")
                    end
                end,
                documentation = {
                    help = "Abilities that do not normally target objects can target this object if this GoblinScript passes. Leave blank to use normal targeting rules only.",
                    output = "boolean",
                    subject = creature.helpSymbols,
                    subjectDescription = "This object",
                    symbols = {
                        ability = {
                            name = "Ability",
                            type = "ability",
                            desc = "The ability being checked against this object.",
                            examples = {
                                'Ability.Keywords has "Strike"',
                                'Ability.Keywords has "Melee"',
                            },
                        },
                        caster = {
                            name = "Caster",
                            type = "creature",
                            desc = "The creature using the ability.",
                            examples = {
                                "Caster.Level > 2",
                            },
                        },
                    },
                },
            },
        },

        gui.Panel{
            classes = {"field-editor-panel"},
            flow = "vertical",
            minHeight = 0,
            gui.Check{
                text = "No Collision Damage",
                value = components[1].properties:try_get("no_collision_damage", false),
                fontSize = 14,
                change = function(element)
                    local val = element.value
                    for _, component in ipairs(components) do
                        component:BeginChanges()
                        component.properties.no_collision_damage = val
                        component:CompleteChanges("Change collision damage")
                    end
                end,
            },

            gui.Check{
                text = "Immune to Forced Movement",
                value = components[1].properties:try_get("immune_to_forced_movement", false),
                fontSize = 14,
                change = function(element)
                    local immune = element.value
                    for _, component in ipairs(components) do
                        component:BeginChanges()
                        component.properties.immune_to_forced_movement = immune
                        component:CompleteChanges("Change forced movement immunity")
                    end
                end,
            },

            gui.Check{
                text = "Custom Collision Behavior",
                value = components[1].properties:try_get("custom_collision", false) ~= false,
                fontSize = 14,
                change = function(element)
                    local val = element.value
                    for _, component in ipairs(components) do
                        component:BeginChanges()
                        if val == false then
                            component.properties.custom_collision = nil
                        else
                            component.properties.custom_collision = ActivatedAbility.Create{
                                name = "Custom Collision Behavior",
                                behaviors = {},
                            }
                        end
                        component:CompleteChanges("Change custom collision behavior")
                    end
                    resultPanel:FireEventTree("refresh")
                end,
            },

            gui.Button{
                text = "Edit Behavior",
                width = 200,
                height = 22,
                fontSize = 16,
                refresh = function(element)
                    element:SetClass("collapsed", components[1].properties:try_get("custom_collision", false) == false)
                end,
                press = function(element)
                    element.root:AddChild(components[1].properties.custom_collision:ShowEditActivatedAbilityDialog{
                        close = function()
                            components[1]:Upload()
                            resultPanel:FireEventTree("refresh")
                        end,
                    })
                end,
            },

            gui.Button{
                text = "Object Sheet",
                width = 200,
                height = 22,
                fontSize = 16,
                press = function(element)
                    local token = dmhub.LookupToken(components[1].properties)
                    if token ~= nil then
                        token:ShowSheet()
                    end
                end,
            },
        }
    }

    return resultPanel
end