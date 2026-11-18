local mod = dmhub.GetModLoading()

--The Hero sheet's top bar:
--  * the switcher: the party's Heroes (yours first; others only as far as the
--    Director's Party Member Controls allows, with a "View" badge on a
--    view-only one), the party's hero tokens, then the tokens you control
--    (followers, a companion, summons) and "+" for the Followers window.
--    The Director sees only the open Hero's party, and an eye at the left
--    shows or hides the open Hero's followers and summons (no group labels,
--    so the eye never changes them);
--  * Edit (Character tab only), the tabs, the Builder button, the sheet
--    actions other mods register (Export). Pop out is on the window's title
--    bar, as on rail windows (HeroSheetWindow).
--It sits over the tab's content in the right-hand column. At 1000 units or
--wider it is one row; narrower, the switcher takes its own row (with the
--actions at its end) and Edit, the tabs and the Builder go
--under it; the Builder takes a third row when the second cannot hold it. When
--the switcher overflows it drops its group labels, then shrinks its
--pictures, then shows arrows that page by what is in view.

HeroSheetTopBar = rawget(_G, "HeroSheetTopBar") or {}

--A switcher picture is a small portrait card (40 x 56),
--shrinking to 32 x 44 when the strip is short of room.
local THUMB = 40
local THUMB_H = 56
local THUMB_SMALL = 32
local THUMB_SMALL_H = 44
--The strip's height: a card with room for the open Hero's outer ring.
local STRIP_H = THUMB_H + 12
--The column width (sheet units) below which the bar splits into rows. The
--Builder drops to a third row whenever the second row cannot hold it (a
--narrow column, a large Font Size, or Edit grown into "Editing" and Done).
local ONE_ROW_AT = 1000
--Edit's slot: as wide as "Editing" and Done at Edit's width (measured 140),
--on every tab.
local EDIT_SLOT = 142
--The Director's followers eye: its design size and side margin. It is
--pinned left of the scrolling row, so its room comes out of the strip's.
local EYE_SIZE = 26
local EYE_MARGIN = 4

----------------------------------------------------------------------
--Who the switcher shows.

--- @class HeroSheetSwitcherEntry
--- @field token CharacterToken
--- @field kind string "hero" or "linked"
--- @field access nil|string a Hero's Party Member Controls access: "edit" or "view"
--- @field type nil|string a linked token's type for its tooltip ("Retainer", "Companion"...)

--The type of a token linked to a Hero, for the switcher's tooltip.
--- @param tok CharacterToken
--- @return string
local function LinkedType(tok)
    local props = tok.properties
    local followerType = props:try_get("followerType")
    if type(followerType) == "string" and followerType ~= "" then
        return string.upper(string.sub(followerType, 1, 1)) .. string.sub(followerType, 2)
    end
    local companion = false
    pcall(function() companion = props:IsCompanion() end)
    if companion then
        return "Companion"
    end
    if tok.summonerid ~= nil and tok.summonerid ~= "" then
        return "Summon"
    end
    return ""
end

--A Hero's followers, companion and summons, as tokens.
--- @param hero CharacterToken
--- @param into CharacterToken[]
--- @param seen table<string, boolean>
local function AddLinked(hero, into, seen)
    local function Add(tok)
        if tok ~= nil and tok.valid and tok.properties ~= nil and not seen[tok.charid] then
            seen[tok.charid] = true
            into[#into+1] = tok
        end
    end
    --try_get, not GetFollowers: that adds an empty list to the Hero, a
    --local change that is never sent.
    for charid, _ in pairs(hero.properties:try_get("followers") or {}) do
        Add(dmhub.GetCharacterById(charid))
    end
    pcall(function() Add(hero.properties:GetCompanionToken()) end)
    for _, tok in ipairs(dmhub.allTokens) do
        if tok.summonerid == hero.charid then
            Add(tok)
        end
    end
end

--Whether the Director's switcher shows the open Hero's followers, companion
--and summons (the eye left of the strip). Players always see theirs.
local g_followersSetting = setting{
    id = "herosheet:switcherfollowers",
    description = "Hero sheet switcher followers",
    storage = "preference",
    default = false,
}

--- The id of the party a character is in, or nil.
--- @param charid string
--- @return nil|string
local function PartyOf(charid)
    for _, partyid in ipairs(GetAllParties()) do
        for _, id in ipairs(dmhub.GetCharacterIdsInParty(partyid) or {}) do
            if id == charid then
                return partyid
            end
        end
    end
    return nil
end

--- The party whose Heroes the switcher shows: for the Director, the open
--- Hero's party (nil when it is in none: only that Hero shows), since a
--- Director with every party in the strip has too much to scan. Players see
--- every party their access allows, so for them it is always "all".
--- @return nil|string
function HeroSheetTopBar.ShownParty()
    local open = HeroSheet.Token()
    if not dmhub.isDM or open == nil then
        return "all"
    end
    return PartyOf(open.charid)
end

--- The switcher's entries for the open Hero: Heroes, then linked tokens, and
--- the label for the linked group ("Yours", or "<Hero>'s" for the Director).
--- @return HeroSheetSwitcherEntry[] heroes
--- @return HeroSheetSwitcherEntry[] linked
--- @return string linkedLabel
--- @return nil|string shownParty the party shown (see ShownParty)
function HeroSheetTopBar.Entries()
    local open = HeroSheet.Token()
    local director = dmhub.isDM
    local shown = HeroSheetTopBar.ShownParty()
    local mine, others = {}, {}
    local seen = {}
    for _, partyid in ipairs(GetAllParties()) do
        --a party the strip does not show is skipped before its members are read.
        local members = {}
        if shown == "all" or shown == partyid then
            members = dmhub.GetCharacterIdsInParty(partyid) or {}
        end
        for _, charid in ipairs(members) do
            local tok = dmhub.GetCharacterById(charid)
            if not seen[charid] and tok ~= nil and HeroSheet.Routes(tok) then
                seen[charid] = true
                local access = CharacterPanel.TokenAccessLevel(tok)
                if access ~= "none" then
                    local entry = {token = tok, kind = "hero", access = access}
                    if director or tok.canControlAsUser then
                        mine[#mine+1] = entry
                    else
                        others[#others+1] = entry
                    end
                end
            end
        end
    end
    --the open Hero may be outside every party (a Hero only on a map).
    if open ~= nil and not seen[open.charid] then
        table.insert(mine, 1, {token = open, kind = "hero", access = "edit"})
    end
    local heroes = mine
    for _, entry in ipairs(others) do
        heroes[#heroes+1] = entry
    end

    local linkedTokens = {}
    local linkedSeen = {}
    local label = "Yours"
    if director then
        --the Director controls everything: only the open Hero's, and only
        --while the eye left of the strip is on.
        if open ~= nil and g_followersSetting:Get() == true then
            AddLinked(open, linkedTokens, linkedSeen)
            label = (open.name or "Hero") .. "'s"
        end
    else
        for _, entry in ipairs(mine) do
            AddLinked(entry.token, linkedTokens, linkedSeen)
        end
        --and any other follower, companion or summon you control in a party.
        for _, partyid in ipairs(GetAllParties()) do
            for _, charid in ipairs(dmhub.GetCharacterIdsInParty(partyid) or {}) do
                local tok = dmhub.GetCharacterById(charid)
                if tok ~= nil and not seen[charid] and not linkedSeen[charid] and tok.canControlAsUser
                        and tok.properties ~= nil and LinkedType(tok) ~= "" then
                    linkedSeen[charid] = true
                    linkedTokens[#linkedTokens+1] = tok
                end
            end
        end
    end
    local linked = {}
    for _, tok in ipairs(linkedTokens) do
        if director or tok.canControlAsUser then
            linked[#linked+1] = {token = tok, kind = "linked", type = LinkedType(tok)}
        end
    end
    return heroes, linked, label, shown
end

--A signature of the entries, so the strip redraws only when they change.
--- @return string
local function EntriesSignature()
    local heroes, linked, label, shown = HeroSheetTopBar.Entries()
    local parts = {label, tostring(shown), tostring(g_followersSetting:Get())}
    for _, list in ipairs({heroes, linked}) do
        for _, entry in ipairs(list) do
            local tok = entry.token
            parts[#parts+1] = string.format("%s:%s:%s:%s", tok.charid, tostring(tok.name), tostring(entry.access), tostring(tok.offTokenPortrait or tok.portrait))
        end
    end
    return table.concat(parts, "|")
end

----------------------------------------------------------------------
--The switcher strip.

--What a thumb shows that is fixed when it is built: a thumb whose key is
--unchanged is kept from one strip to the next.
--- @param entry HeroSheetSwitcherEntry
--- @return string
local function ThumbKey(entry)
    local tok = entry.token
    return table.concat({tok.charid, entry.kind, tostring(entry.access), tostring(entry.type), tostring(tok.name), tostring(tok.offTokenPortrait or tok.portrait)}, "|")
end

--The art a switcher thumb should show: the card art, else the token picture.
--Read from the live token each time.
--- @param charid string
--- @return nil|string
local function ThumbArt(charid)
    local tok = dmhub.GetCharacterById(charid) or dmhub.GetTokenById(charid)
    if tok == nil then
        return nil
    end
    local art = nil
    pcall(function()
        art = tok.offTokenPortrait
        if art == nil or art == "" then
            art = tok.portrait
        end
    end)
    if art == "" then
        return nil
    end
    return art
end

--Paints a switcher thumb from the live token: the card's crop when it has
--card art, else its token picture. Records what it drew in data.paintedArt.
--- @param element Panel
local function PaintThumb(element)
    local charid = element.data.charid
    local tok = dmhub.GetCharacterById(charid) or dmhub.GetTokenById(charid)
    if tok == nil then
        element.data.paintedArt = nil
        return
    end
    if EotwHeroCard.ApplyPortrait(element, tok, THUMB / THUMB_H) then
        element.data.paintedArt = element.bgimage
        return
    end
    local portrait = nil
    pcall(function() portrait = tok.portrait end)
    if type(portrait) == "string" and portrait ~= "" then
        element.bgimage = portrait
        element.selfStyle.bgcolor = "white"
        element.data.paintedArt = ThumbArt(charid)
    else
        element.data.paintedArt = nil
    end
end

--A switcher thumb. setOpen marks it as the open Hero (the gold edge and
--ring) without building it again.
--- @param entry HeroSheetSwitcherEntry
--- @return {panel: Panel, setOpen: fun(open: boolean)}
local function Thumb(entry)
    local tok = entry.token
    local charid = tok.charid
    local viewOnly = entry.kind == "hero" and entry.access == "view"
    local tooltip = tok.name or "Hero"
    if entry.kind == "linked" and entry.type ~= nil and entry.type ~= "" then
        tooltip = string.format("%s, %s", tooltip, entry.type)
    end
    local children = {}
    if viewOnly then
        children[#children+1] = gui.Label{
            classes = {"heroSheetSwitcherBadge"},
            text = "View",
            width = "100%",
            height = 15,
            fontSize = 10.5,
            bold = true,
            valign = "bottom",
            textAlignment = "center",
            interactable = false,
            bgimage = "panels/square.png",
        }
    end
    --the open Hero: a gold edge, then a light ring just outside it.
    local ring = gui.Panel{
        classes = {"heroSheetRingOuter", "collapsed"},
        bgimage = "panels/square.png",
        bgcolor = "clear",
        floating = true,
        border = 2,
        cornerRadius = 9,
        width = "100%+10",
        height = "100%+10",
        halign = "center",
        valign = "center",
        interactable = false,
    }
    children[#children+1] = ring
    local panel = gui.Panel{
        classes = {"heroSheetThumb", "hoverable", "heroSheetThumbRest"},
        bgimage = "panels/square.png",
        bgcolor = "#1d1915ff",
        border = 1,
        cornerRadius = 6,
        width = THUMB,
        height = THUMB_H,
        valign = "center",
        hmargin = 5,
        data = {charid = charid, hm = 5},
        create = function(element)
            PaintThumb(element)
        end,
        --A thumb built while the game is still loading can find the Hero's
        --art not ready yet, or read a token object that is replaced once
        --loading ends. Nothing else repaints a kept thumb, so it checks again
        --while it shows.
        thinkTime = 1,
        think = function(element)
            if ThumbArt(charid) ~= element.data.paintedArt or element.data.eotwPortraitWait ~= nil then
                local before = element.data.paintedArt
                PaintThumb(element)
                if element.data.paintedArt ~= before then
                    print(string.format("HEROSHEET:: switcher picture for %s repainted (%s -> %s)", tostring(tooltip), tostring(before), tostring(element.data.paintedArt)))
                end
            end
        end,
        heroSheetThumbSize = function(element, w, h)
            element.selfStyle.width = w
            element.selfStyle.height = h
        end,
        linger = function(element)
            gui.Tooltip(tooltip)(element)
        end,
        hover = function(element)
            if entry.kind == "hero" then
                HeroSheet.Warm(charid)
            end
        end,
        click = function(element)
            local live = dmhub.GetCharacterById(charid) or dmhub.GetTokenById(charid)
            if live == nil then
                return
            end
            if entry.kind == "hero" then
                local state = HeroSheet.State()
                if state == nil or state.tokenid ~= charid then
                    --the other Hero opens on the tab showing now.
                    HeroSheet.Open(live, state ~= nil and state.tab or nil)
                end
            else
                --a follower, companion or summon opens the classic character
                --sheet over the window, which waits underneath.
                live:ShowSheet()
            end
        end,
        children = children,
    }
    return {
        panel = panel,
        setOpen = function(open)
            panel:SetClass("heroSheetRing", open)
            panel:SetClass("heroSheetThumbRest", not open)
            panel.selfStyle.border = cond(open, 2, 1)
            ring:SetClass("collapsed", not open)
        end,
    }
end

--A group label ("PARTY", "YOURS") in small capitals; dropped first when
--the strip is short of room.
--- @param text string
--- @return Panel
local function GroupLabel(text)
    return gui.Label{
        classes = {"heroSheetMuted", "heroSheetGroupLabel"},
        text = string.upper(text),
        width = "auto",
        height = "auto",
        fontSize = 11,
        bold = true,
        valign = "center",
        hmargin = 6,
        data = {hm = 6},
        interactable = false,
        heroSheetCompact = function(element, compact)
            element:SetClass("collapsed", compact.labels == false or element.data.off == true)
        end,
    }
end

--A thin divider between groups; stays when the labels drop.
--- @return Panel
local function Divider()
    return gui.Panel{
        classes = {"heroSheetDivider"},
        bgimage = "panels/square.png",
        width = 1,
        height = 28,
        hmargin = 6,
        data = {hm = 6},
        valign = "center",
        interactable = false,
    }
end

--The party's hero tokens: the app's icon and the count, click to set.
--- @return Panel
local function HeroTokens()
    local function Get()
        local token = HeroSheet.Token()
        if token == nil then
            return 0
        end
        return token.properties:GetHeroTokens()
    end
    local number = HeroSheetTheme.ClickNumber{
        get = Get,
        set = function(count)
            local token = HeroSheet.Token()
            if token == nil then
                return
            end
            local prev = token.properties:GetHeroTokens()
            --a shared party resource (a document), not a Hero property.
            token.properties:SetHeroTokens(count, "Set manually")
            if count ~= prev and dmhub.GetSettingValue("telemetry_enabled") ~= false then
                --the sheet only ever shows Heroes.
                local classInfo = (token.properties --[[@as character]]):GetClass()
                analytics.Event{
                    type = "hero_token_change",
                    change = count - prev,
                    source = "manual",
                    class = classInfo and classInfo.name or "unknown",
                    dailyLimit = 30,
                    userid = dmhub.userid,
                    gameid = dmhub.gameid,
                    version = dmhub.version,
                }
            end
        end,
        canEdit = function()
            local state = HeroSheet.State()
            return state ~= nil and not state.viewOnly
        end,
        fontSize = 15,
        classes = {"heroSheetCardStrong"},
        tooltip = "Hero tokens",
    }
    --the icon and count in a pill.
    return gui.Panel{
        classes = {"heroSheetTokenPill"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 16,
        width = "auto",
        height = 32,
        lpad = 8,
        rpad = 6,
        borderBox = true,
        flow = "horizontal",
        valign = "center",
        hmargin = 6,
        data = {hm = 6},
        monitorGame = CharacterResource.GlobalResourcePath(),
        refreshGame = function(element)
            element:FireEventTree("refreshNumber")
        end,
        gui.Panel{
            bgimage = "drawsteel/hero-token.png",
            bgcolor = "white",
            width = 22,
            height = 22,
            valign = "center",
            linger = function(element)
                gui.Tooltip("Hero tokens")(element)
            end,
        },
        number,
    }
end

--The switcher: a clipped view onto a row of entries, with arrows when it
--overflows. Its entries redraw when the party, the Hero's followers or Party
--Member Controls change.
--- @return Panel
local function Switcher()
    local viewport
    local inner
    local leftArrow
    local rightArrow
    --- @type nil|Panel
    local viewHolder
    --- @type nil|Panel
    local eye

    --The view takes what the arrows and the Director's eye leave. Its width is
    --set here, never "100% available": the engine re-lays out such a panel's
    --whole subtree every frame.
    local function SizeView()
        if viewHolder == nil or not viewHolder.valid then
            return
        end
        local arrows = 0
        for _, arrow in ipairs({leftArrow, rightArrow}) do
            if not arrow:HasClass("collapsed") then
                arrows = arrows + 24
            end
        end
        if eye ~= nil and not eye:HasClass("collapsed") then
            --Font Size reflows the sheet without rebuilding it: resize the eye
            --here so it matches the room kept for it.
            local size = HeroSheetWindow.TargetSize(EYE_SIZE)
            if eye.selfStyle.width ~= size then
                eye.selfStyle.width = size
                eye.selfStyle.height = size
            end
            arrows = arrows + size + EYE_MARGIN * 2
        end
        local width = string.format("100%%-%d", arrows)
        if viewHolder.selfStyle.width ~= width then
            viewHolder.selfStyle.width = width
        end
    end
    --how far the row is scrolled, in the strip's own units.
    local offset = 0
    local compact = {labels = true, small = false}

    --The left and right edges of each entry in screen pixels, from the
    --row's start (margins included), the row's whole width, and the pixels
    --per strip unit.
    local function Extents()
        local perUnit = nil
        for _, child in ipairs(inner.children) do
            if perUnit == nil and child.valid and not child:HasClass("collapsed") and child:HasClass("heroSheetThumb") and child.renderedWidth > 0 then
                perUnit = child.renderedWidth / (compact.small and THUMB_SMALL or THUMB)
            end
        end
        perUnit = perUnit or 1
        local result = {}
        local x = 0
        for _, child in ipairs(inner.children) do
            if child.valid and not child:HasClass("collapsed") then
                local margin = ((child.data and child.data.hm) or 0) * perUnit
                x = x + margin
                local w = child.renderedWidth
                result[#result+1] = {left = x - margin, right = x + w + margin}
                x = x + w + margin
            end
        end
        return result, x, perUnit
    end

    local function ApplyOffset()
        inner.x = -offset
    end

    --Shows the arrows only while the row overflows, each hidden at its end.
    local function UpdateArrows()
        if viewport == nil or not viewport.valid then
            return
        end
        local _, total, perUnit = Extents()
        local view = viewport.renderedWidth
        local offsetPx = offset * perUnit
        if total <= view + 1 then
            offset = 0
            ApplyOffset()
            leftArrow:SetClass("collapsed", true)
            rightArrow:SetClass("collapsed", true)
            SizeView()
            return
        end
        leftArrow:SetClass("collapsed", offsetPx <= 0.5)
        rightArrow:SetClass("collapsed", offsetPx + view >= total - 0.5)
        SizeView()
    end

    --Pages by what is in view: right brings the first entry
    --not fully in view to the left edge; left brings the entry before the
    --first fully visible one to the right edge.
    --- @param direction number 1 or -1
    local function Page(direction)
        local extents, total, perUnit = Extents()
        local view = viewport.renderedWidth
        local offsetPx = offset * perUnit
        if direction > 0 then
            for _, extent in ipairs(extents) do
                if extent.right > offsetPx + view + 0.5 then
                    offsetPx = math.min(extent.left, total - view)
                    break
                end
            end
        else
            for i, extent in ipairs(extents) do
                if extent.left >= offsetPx - 0.5 then
                    local before = extents[i - 1]
                    if before ~= nil then
                        offsetPx = math.max(0, before.right - view)
                    end
                    break
                end
            end
        end
        offset = offsetPx / perUnit
        ApplyOffset()
        UpdateArrows()
    end

    local function Arrow(direction)
        return gui.Button{
            classes = {"collapsed"},
            icon = cond(direction < 0, "phosphor/caret-left-bold.png", "phosphor/caret-right-bold.png"),
            --a 24-unit hit area.
            width = 24,
            height = THUMB_H,
            valign = "center",
            click = function(element)
                Page(direction)
            end,
        }
    end

    --How much wider the strip would be one step roomier, in screen pixels:
    --full-size pictures, or the group labels back (their text estimated as
    --bold capitals, which a collapsed label cannot measure).
    --- @param perUnit number
    --- @return number
    local function RoomierExtra(perUnit)
        local extra = 0
        for _, child in ipairs(inner.children) do
            if child.valid then
                if compact.small and child:HasClass("heroSheetThumb") then
                    extra = extra + (THUMB - THUMB_SMALL) * perUnit
                elseif not compact.small and child:HasClass("heroSheetGroupLabel") and child.data.off ~= true then
                    extra = extra + (#child.text * 11 * 0.75 + 12) * perUnit
                end
            end
        end
        return extra
    end

    --Fits the strip to its width from the state it is in: while it overflows
    --it drops the labels, then shrinks the pictures; it steps back up only
    --when the roomier state is estimated to fit, and never after shrinking in
    --the same fit. (Starting each fit from the full strip would flash the
    --labels on every Hero switch and jolt the bar.) Each step waits for the
    --last to lay out; a newer fit stops an older one.
    local fitGen = 0
    local function Fit()
        fitGen = fitGen + 1
        local gen = fitGen
        local shrunk = false
        offset = 0
        ApplyOffset()
        local function Apply()
            inner:FireEventTree("heroSheetCompact", compact)
            inner:FireEventTree("heroSheetThumbSize", cond(compact.small, THUMB_SMALL, THUMB), cond(compact.small, THUMB_SMALL_H, THUMB_H))
        end
        local function Step()
            HeroSheetWindow.AfterLayout(function()
                if gen ~= fitGen or viewport == nil or not viewport.valid then
                    return
                end
                local _, total, perUnit = Extents()
                local view = viewport.renderedWidth
                if total > view + 1 and (compact.labels or not compact.small) then
                    shrunk = true
                    if compact.labels then
                        compact.labels = false
                    else
                        compact.small = true
                    end
                    Apply()
                    Step()
                    return
                end
                local roomiest = compact.labels and not compact.small
                if not shrunk and not roomiest and total + RoomierExtra(perUnit) <= view - 4 then
                    if compact.small then
                        compact.small = false
                    else
                        compact.labels = true
                    end
                    Apply()
                    Step()
                    return
                end
                UpdateArrows()
            end)
        end
        Apply()
        Step()
    end

    --The strip's parts, kept from one draw to the next: the labels, the hero
    --tokens, the divider, "+", and a thumb per entry (by ThumbKey). Another
    --Hero moves the gold ring; only new entries are built.
    local partyLabel = GroupLabel("Party")
    local linkedLabel = GroupLabel("")
    local tokens = HeroTokens()
    local divider = Divider()
    --- @type nil|Panel
    local plus = nil
    --- @type table<string, {panel: Panel, setOpen: fun(open: boolean)}>
    local thumbs = {}
    --the strip's children as last set, to tell when they change.
    --- @type Panel[]
    local drawn = {}

    --Sets the strip from the entries; fits it again only when what it holds
    --changed (a new Hero in the party, other followers).
    local function Build()
        local heroes, linked, label = HeroSheetTopBar.Entries()
        local state = HeroSheet.State()
        local openid = state ~= nil and state.tokenid or nil
        local director = dmhub.isDM
        if eye ~= nil then
            eye:FireEvent("paint")
        end
        --The Director's strip has no group labels: the eye starts it and the
        --divider marks the followers, so the eye never changes the labels.
        --They stay attached but collapsed (data.off).
        local labelsToggled = partyLabel.data.off ~= director
        for _, groupLabel in ipairs({partyLabel, linkedLabel}) do
            groupLabel.data.off = director
            groupLabel:SetClass("collapsed", director or compact.labels == false)
        end
        local children = {partyLabel}
        local kept = {}
        local function Add(entry)
            local key = ThumbKey(entry)
            local thumb = kept[key] or thumbs[key] or Thumb(entry)
            kept[key] = thumb
            thumb.setOpen(entry.kind == "hero" and entry.token.charid == openid)
            children[#children+1] = thumb.panel
        end
        for _, entry in ipairs(heroes) do
            Add(entry)
        end
        children[#children+1] = tokens
        children[#children+1] = divider
        linkedLabel.text = string.upper(label)
        children[#children+1] = linkedLabel
        for _, entry in ipairs(linked) do
            Add(entry)
        end
        --"+" opens the Followers window: an empty card the size of a thumb,
        --its edge dashed, a small plus in the middle.
        local followersWindow = rawget(_G, "HeroSheetWindows")
        if followersWindow ~= nil and followersWindow.OpenFollowers ~= nil then
            plus = plus or gui.Panel{
                classes = {"heroSklAdd", "hoverable"},
                bgimage = "panels/square.png",
                border = 1,
                cornerRadius = 6,
                width = THUMB,
                height = THUMB_H,
                valign = "center",
                hmargin = 5,
                data = {hm = 5},
                gui.Panel{
                    classes = {"heroSklAddIcon"},
                    bgimage = "phosphor/plus-bold.png",
                    width = 16,
                    height = 16,
                    halign = "center",
                    valign = "center",
                    interactable = false,
                },
                linger = function(element)
                    gui.Tooltip("Add or manage followers")(element)
                end,
                heroSheetThumbSize = function(element, w, h)
                    element.selfStyle.width = w
                    element.selfStyle.height = h
                end,
                click = function(element)
                    followersWindow.OpenFollowers()
                end,
                --a view-only Hero's followers are not managed here.
                heroSheetHero = function(element)
                    element:SetClass("collapsed", not HeroSheetWrite.CanWrite())
                end,
            }
            plus:SetClass("collapsed", not HeroSheetWrite.CanWrite())
            children[#children+1] = plus
        end
        --thumbs left out are destroyed when the children are set.
        thumbs = kept
        local same = #children == #drawn
        for i = 1, #children do
            if not same then
                break
            end
            same = children[i] == drawn[i]
        end
        if not same then
            drawn = children
            inner.children = children
            Fit()
        elseif labelsToggled then
            Fit()
        end
    end

    inner = HeroSheetRefresh.Block({
        width = "auto",
        height = STRIP_H,
        flow = "horizontal",
        halign = "left",
        valign = "center",
        --Party Member Controls changed: who the switcher may show changes.
        multimonitor = {"partymembercontrols"},
        monitor = function(element)
            Build()
        end,
    }, {
        name = "switcher",
        signature = function(token)
            --followers live on the Hero; the rest is checked here too, so a
            --party change shows on the next change to the Hero.
            return EntriesSignature()
        end,
        refresh = function(panel, token)
            inner = panel
            Build()
        end,
    })

    viewport = gui.Panel{
        classes = {"heroSheetSwitcherView"},
        bgimage = "panels/square.png",
        bgcolor = "clear",
        clip = true,
        clipHidden = true,
        width = "100%",
        height = STRIP_H,
        valign = "center",
        inner,
    }

    leftArrow = Arrow(-1)
    rightArrow = Arrow(1)

    --The Director's eye: shows or hides the open Hero's followers, companion
    --and summons. Pinned left of the scrolling row so the fitting steps never
    --drop it; the same button as the Features tab's "Show hidden features".
    local eyeIcon = gui.Panel{
        classes = {"heroSheetIconButtonIcon"},
        bgimage = "phosphor/eye-closed-light.png",
        width = 15,
        height = 15,
        halign = "center",
        valign = "center",
        interactable = false,
    }
    eye = gui.Panel{
        classes = {"heroSheetIconButton", "hoverable", cond(dmhub.isDM, nil, "collapsed")},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = HeroSheetWindow.TargetSize(EYE_SIZE),
        height = HeroSheetWindow.TargetSize(EYE_SIZE),
        hmargin = EYE_MARGIN,
        valign = "center",
        paint = function(element)
            local on = g_followersSetting:Get() == true
            element:SetClass("collapsed", not dmhub.isDM)
            element:SetClassTree("selected", on)
            eyeIcon.bgimage = cond(on, "phosphor/eye-light.png", "phosphor/eye-closed-light.png")
        end,
        linger = function(element)
            --says what a click will do.
            gui.Tooltip(cond(g_followersSetting:Get() == true, "Hide followers and summons", "Show followers and summons"))(element)
        end,
        click = function(element)
            g_followersSetting:Set(g_followersSetting:Get() ~= true)
            if inner ~= nil and inner.valid then
                Build()
            end
        end,
        eyeIcon,
    }

    --the view takes what the arrows leave of the switcher's width (SizeView).
    viewHolder = gui.Panel{
        --until the first fit sizes it: what the Director's eye takes.
        width = cond(dmhub.isDM, string.format("100%%-%d", HeroSheetWindow.TargetSize(EYE_SIZE) + EYE_MARGIN * 2), "100%"),
        height = STRIP_H,
        valign = "center",
        viewport,
    }

    return gui.Panel{
        classes = {"heroSheetSwitcher"},
        halign = "left",
        width = 0,
        height = STRIP_H,
        flow = "horizontal",
        valign = "center",
        heroSheetFit = function(element)
            if inner ~= nil and inner.valid then
                Fit()
            end
        end,
        eye,
        leftArrow,
        viewHolder,
        rightArrow,
    }
end

----------------------------------------------------------------------
--Edit, tabs, Builder, sheet actions.

--A labelled button with an optional icon before the text, sized to its
--text. (gui.Button stretches an icon over the whole button when it also has
--text.) "selected" on it marks the open tab. A segment is one tab of the
--joined tab group: no edge of its own (the group draws it), corners set by
--the group.
--- @param args {text: string, icon: nil|string, tooltip: nil|string, click: fun(element: Panel), hover: nil|fun(element: Panel), classes: nil|string[], lmargin: nil|number, data: nil|table, segment: nil|boolean}
--- @return Panel
local function TextButton(args)
    --extra classes ("selected") go on the label and icon too.
    local function Classes(base)
        local result = {base}
        for _, class in ipairs(args.classes or {}) do
            result[#result+1] = class
        end
        return result
    end
    local children = {}
    if args.icon ~= nil then
        children[#children+1] = gui.Panel{
            classes = Classes("heroSheetButtonIcon"),
            bgimage = args.icon,
            width = 16,
            height = 16,
            valign = "center",
            rmargin = 6,
            interactable = false,
        }
    end
    --the open tab's text is bold, which is wider: an invisible bold copy
    --sets the width, so selecting a tab never changes the bar's layout.
    local fontSize = cond(args.segment, 13.5, 14)
    children[#children+1] = gui.Panel{
        width = "auto",
        height = "auto",
        valign = "center",
        interactable = false,
        gui.Label{
            text = args.text,
            width = "auto",
            height = "auto",
            fontSize = fontSize,
            bold = true,
            color = "#00000000",
            textWrap = false,
            interactable = false,
        },
        gui.Label{
            classes = Classes("heroSheetButtonLabel"),
            text = args.text,
            floating = true,
            width = "auto",
            height = "auto",
            fontSize = fontSize,
            halign = "center",
            valign = "center",
            textWrap = false,
            interactable = false,
        },
    }
    local classes = {cond(args.segment, "heroSheetSegment", "heroSheetButton"), "hoverable"}
    for _, class in ipairs(args.classes or {}) do
        classes[#classes+1] = class
    end
    return gui.Panel{
        classes = classes,
        bgimage = "panels/square.png",
        border = cond(args.segment, 0, 1),
        cornerRadius = cond(args.segment, 0, 6),
        width = "auto",
        height = cond(args.segment, 34, 36),
        hpad = cond(args.segment, 13, 14),
        borderBox = true,
        flow = "horizontal",
        halign = "left",
        valign = "center",
        hmargin = cond(args.segment, 0, 1),
        lmargin = args.lmargin,
        data = args.data or {},
        linger = function(element)
            if args.tooltip ~= nil then
                gui.Tooltip(args.tooltip)(element)
            end
        end,
        click = args.click,
        hover = args.hover,
        children = children,
    }
end

--- @class HeroSheetTopBarArgs
--- @field tabs fun(): {id: string, text: string}[] the tabs the strip offers (the window's own, then other mods')
--- @field selectTab fun(tabid: string)
--- @field setEditing fun(editing: boolean)

--- Build the top bar. It listens for heroSheetTab (tabid), heroSheetEdit
--- (editing) and heroSheetBarWidth (the width of the column it sits in, in
--- sheet units).
--- @param args HeroSheetTopBarArgs
--- @return Panel
function HeroSheetTopBar.Create(args)
    --Edit: Character tab only, never on a view-only Hero; "Editing" and
    --Done while it is on.
    local doneButton
    --Done takes Edit's width, so the button pressed to start
    --Edit mode is the same size and place as the one that ends it. Edit is
    --measured while it shows, in bar units (buttons are 36 tall).
    --- @param edit Panel
    local function MatchDone(edit)
        if edit.valid and doneButton ~= nil and edit.renderedWidth > 0 and edit.renderedHeight > 0 then
            doneButton.selfStyle.width = edit.renderedWidth / (edit.renderedHeight / 36)
        end
    end
    local editButton = TextButton{
        text = "Edit",
        icon = "phosphor/pencil-simple.png",
        click = function(element)
            MatchDone(element)
            args.setEditing(true)
        end,
    }
    local editingLabel = gui.Label{
        classes = {"heroSheetInfo"},
        text = "Editing",
        width = "auto",
        height = "auto",
        fontSize = 15,
        bold = true,
        valign = "center",
        hmargin = 6,
    }
    doneButton = TextButton{
        classes = {"selected"},
        text = "Done",
        click = function(element)
            args.setEditing(false)
        end,
    }
    --Edit keeps a slot as wide as "Editing" and Done on every tab: its
    --controls sit at the slot's right, and the slot is empty off the
    --Character tab, so a tab switch or Edit mode never moves the tabs. A
    --view-only Hero never edits, so it has no slot.
    local editControls = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "right",
        valign = "center",
        editButton,
        editingLabel,
        doneButton,
    }
    local editGroup = gui.Panel{
        width = EDIT_SLOT,
        height = 36,
        halign = "left",
        valign = "center",
        rmargin = 8,
        editControls,
    }
    local function ShowEdit()
        local state = HeroSheet.State()
        local onCharacter = state ~= nil and state.tab == "CharacterSheet"
        local viewOnly = state == nil or state.viewOnly == true
        local editing = state ~= nil and state.editing == true
        editGroup:SetClass("collapsed", viewOnly)
        editControls:SetClass("collapsed", not onCharacter)
        editButton:SetClass("collapsed", editing)
        editingLabel:SetClass("collapsed", not editing)
        doneButton:SetClass("collapsed", not editing)
    end

    --The tabs as one joined group: one rounded edge
    --around them, a hairline between each, the open one filled.
    local tabButtons = {}
    local tabDividers = {}
    local tabChildren = {}
    for _, tab in ipairs(args.tabs()) do
        local tabid = tab.id
        if tabid ~= "Builder" then
            if #tabButtons > 0 then
                local divider = gui.Panel{
                    classes = {"heroSheetSegmentLine"},
                    bgimage = "panels/square.png",
                    width = 1,
                    height = 34,
                    valign = "center",
                    interactable = false,
                }
                tabDividers[#tabButtons + 1] = divider
                tabChildren[#tabChildren+1] = divider
            end
            local button = TextButton{
                text = tab.text or tabid,
                segment = true,
                data = {tabid = tabid},
                click = function(element)
                    args.selectTab(tabid)
                end,
                --a tab hidden a while catches up as the pointer comes over.
                hover = function(element)
                    HeroSheet.WarmTab(tabid)
                end,
            }
            tabButtons[#tabButtons+1] = button
            tabChildren[#tabChildren+1] = button
        end
    end
    local tabStrip = gui.Panel{
        classes = {"heroSheetSegments"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 8,
        width = "auto",
        height = 36,
        pad = 1,
        borderBox = true,
        flow = "horizontal",
        halign = "left",
        valign = "center",
        children = tabChildren,
    }
    local function ShowTabs()
        local state = HeroSheet.State()
        local shown = {}
        for i, button in ipairs(tabButtons) do
            button:SetClassTree("selected", state ~= nil and state.tab == button.data.tabid)
            --view only offers the Character tab alone.
            local hidden = state ~= nil and state.viewOnly and button.data.tabid ~= "CharacterSheet"
            button:SetClass("collapsed", hidden)
            if not hidden then
                shown[#shown+1] = i
            end
        end
        --the ends of the group are rounded (x1 = top left, y1 = top right,
        --x2 = bottom right, y2 = bottom left); a hairline only between shown tabs.
        for position, i in ipairs(shown) do
            local first, last = position == 1, position == #shown
            tabButtons[i].selfStyle.cornerRadius = {
                x1 = cond(first, 7, 0), y1 = cond(last, 7, 0),
                x2 = cond(last, 7, 0), y2 = cond(first, 7, 0),
            }
        end
        for i, divider in pairs(tabDividers) do
            divider:SetClass("collapsed", tabButtons[i]:HasClass("collapsed") or #shown < 2)
        end
    end

    --The Builder opens in place of the sheet; its own button, apart
    --from the tabs, with the build icon.
    local builderButton = TextButton{
        text = "Builder",
        icon = "phosphor/hammer-fill.png",
        lmargin = 8,
        tooltip = "Opens the Builder in place of the sheet",
        click = function(element)
            args.selectTab("Builder")
        end,
    }

    --Sheet actions other mods register (CharSheet.RegisterSheetAction):
    --Export is one.
    local actionButtons = {}
    for _, action in ipairs(CharSheet.SheetActions or {}) do
        local info = action
        --shown only for a Hero its visible() accepts; checked again on a
        --Hero switch, as the bar is kept for the next Hero.
        local function Sync(element)
            local visible = true
            if info.visible ~= nil then
                local token = HeroSheet.Token()
                visible = false
                if token ~= nil then
                    pcall(function() visible = info.visible(token.properties) == true end)
                end
            end
            element:SetClass("collapsed", not visible)
        end
        --a bordered square like the other buttons.
        actionButtons[#actionButtons+1] = gui.Panel{
            classes = {"heroSheetButton", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 6,
            width = 36,
            height = 36,
            valign = "center",
            hmargin = 2,
            gui.Panel{
                classes = {"heroSheetButtonIcon"},
                bgimage = info.icon,
                width = 20,
                height = 20,
                halign = "center",
                valign = "center",
                interactable = false,
            },
            linger = function(element)
                if info.tooltip ~= nil then
                    gui.Tooltip(info.tooltip)(element)
                end
            end,
            create = function(element)
                Sync(element)
            end,
            heroSheetHero = function(element)
                Sync(element)
            end,
            click = function(element)
                local token = HeroSheet.Token()
                if token ~= nil then
                    info.click(token, element)
                end
            end,
        }
    end
    local cornerGroup = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "right",
        valign = "center",
        lmargin = 8,
        children = actionButtons,
    }

    local switcher = Switcher()

    --The rows the controls are placed in; the arrangement moves them
    --between rows (never rebuilds them) as the column narrows.
    local row1 = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        valign = "top",
    }
    local row2 = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        tmargin = 6,
    }
    local row3 = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        tmargin = 6,
    }

    local arrangement = nil
    --- @param width number the column's width in sheet units
    local function Arrange(width)
        local wanted = cond(width < ONE_ROW_AT, "rows", "one")
        if wanted == arrangement then
            return
        end
        arrangement = wanted
        for _, panel in ipairs({switcher, editGroup, tabStrip, builderButton, cornerGroup}) do
            if panel.parent ~= nil then
                panel:Unparent()
            end
        end
        --Edit's slot: before the tabs on one row, where its empty part
        --borders the switcher's blank end; after the Builder on the second
        --row, where an empty slot at the row's start would indent the tabs.
        --Its controls sit at the slot's right end either way, so "Editing"
        --appears to the left of a button that does not move.
        if wanted == "one" then
            row1:AddChild(switcher)
            row1:AddChild(editGroup)
            row1:AddChild(tabStrip)
            row1:AddChild(builderButton)
            row1:AddChild(cornerGroup)
            editGroup.selfStyle.lmargin = 0
            editGroup.selfStyle.rmargin = 8
        else
            row1:AddChild(switcher)
            row1:AddChild(cornerGroup)
            row2:AddChild(tabStrip)
            row2:AddChild(builderButton)
            row2:AddChild(editGroup)
            editGroup.selfStyle.lmargin = 8
            editGroup.selfStyle.rmargin = 0
        end
        row2:SetClass("collapsed", wanted == "one")
        row3:SetClass("collapsed", true)
    end

    --Split into rows, the Builder sits on the second row while it fits there
    --and on a third row of its own when it does not.
    --- @param rowUnits number the row's width in sheet units
    --- @param perUnit number screen pixels per sheet unit
    local function PlaceBuilder(rowUnits, perUnit)
        if arrangement ~= "rows" then
            return
        end
        local need = 0
        for _, panel in ipairs({editGroup, tabStrip, builderButton}) do
            if panel.valid and not panel:HasClass("collapsed") then
                need = need + panel.renderedWidth / perUnit
            end
        end
        --Edit's and the Builder's margins.
        need = need + 16
        local ownRow = need > rowUnits
        if ownRow == (builderButton.parent == row3) then
            return
        end
        builderButton:Unparent()
        if ownRow then
            row3:AddChild(builderButton)
        else
            --back between the tabs and Edit's slot.
            editGroup:Unparent()
            row2:AddChild(builderButton)
            row2:AddChild(editGroup)
        end
        row3:SetClass("collapsed", not ownRow)
    end

    --The switcher takes what the other controls in its row leave. They size
    --to their text, so they are measured once they have laid out, and
    --converted from screen pixels to the bar's units.
    local sizeGen = 0
    --the column width last given, for re-measuring when Edit or the tabs
    --change size (Edit grows into "Editing" and Done).
    local lastWidth = ONE_ROW_AT
    --the switcher's width last set: a refit runs only when it changes, as a
    --refit starts the strip at full size and settles over a few frames.
    local switcherWidth = nil
    --- @param width nil|number the column's width in sheet units (default: the last given)
    local function SizeSwitcher(width)
        width = width or lastWidth
        lastWidth = width
        sizeGen = sizeGen + 1
        local gen = sizeGen
        HeroSheetWindow.AfterLayout(function()
            if gen ~= sizeGen or not row1.valid or row1.renderedWidth <= 0 then
                return
            end
            --the row is the column less the bar's padding and border.
            local rowUnits = width - 14
            local perUnit = row1.renderedWidth / rowUnits
            local used = 0
            for _, child in ipairs(row1.children) do
                if child ~= switcher and child.valid and not child:HasClass("collapsed") then
                    used = used + child.renderedWidth / perUnit
                end
            end
            --the margins between the controls (Edit, Builder and the corner
            --group each keep 8 units off their neighbour).
            used = used + 24
            local newWidth = math.max(THUMB * 2, math.floor(rowUnits - used))
            if newWidth ~= switcherWidth then
                switcherWidth = newWidth
                switcher.selfStyle.width = newWidth
                switcher:FireEvent("heroSheetFit")
            end
            PlaceBuilder(rowUnits, perUnit)
        end)
    end

    local function ShowBuilder()
        local state = HeroSheet.State()
        builderButton:SetClass("collapsed", state ~= nil and state.viewOnly)
        builderButton:SetClassTree("selected", state ~= nil and state.tab == "Builder")
    end

    local bar = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetTopBar"},
        bgimage = "panels/square.png",
        border = 0,
        cornerRadius = 10,
        width = "100%",
        height = "auto",
        flow = "vertical",
        pad = 6,
        borderBox = true,
        create = function(element)
            --the window lays new content out before its create runs: keep the
            --rows that layout chose (forcing one row here breaks the bar at
            --Narrow).
            if arrangement == nil then
                Arrange(ONE_ROW_AT)
            end
            ShowEdit()
            ShowTabs()
            ShowBuilder()
            --Done's width from Edit's, also when Edit mode starts another way.
            HeroSheetWindow.AfterLayout(function()
                MatchDone(editButton)
            end)
        end,
        heroSheetTab = function(element, tabid)
            ShowEdit()
            ShowTabs()
            ShowBuilder()
            SizeSwitcher()
        end,
        heroSheetEdit = function(element, editing)
            ShowEdit()
            SizeSwitcher()
        end,
        heroSheetBarWidth = function(element, width)
            Arrange(width)
            SizeSwitcher(width)
        end,
        row1,
        row2,
        row3,
    }
    return bar
end

----------------------------------------------------------------------
--The needed bar: while the sheet covers more than
--half the table, a gold strip under the top bar says when the game is
--waiting on a token you control (the Director: the monsters). Back to the
--table minimizes the sheet into its card; x hides the bar for that need
--only, and a new need shows it again.

--How often the bar re-asks (triggers expire by time without any write).
local NEED_POLL_SECONDS = 0.5

--Test switch, as EotW's debugNeededLine: set to "trigger", "save", "roll" or
--"turn" and the open Hero shows that need; nil for the real checks.
--- @type nil|string
HeroSheetTopBar.debugNeed = nil

--What the bar says for each kind of need (the creature's name fills %s).
local NEED_LINES = {
    trigger = "%s has a trigger to resolve",
    save = "%s has a save to make",
    roll = "%s has a roll to make",
    turn = "%s can claim the turn",
}

--The tokens whose needs the bar reports: for a player, the tokens on the
--map they control, the open Hero first; for the Director, the monsters.
--- @return CharacterToken[]
local function NeedTokens()
    local open = HeroSheet.Token()
    local result = {}
    local director = dmhub.isDM
    for _, tok in ipairs(dmhub.allTokens) do
        if tok.valid and tok.properties ~= nil then
            local include
            if director then
                include = not tok.playerControlled
            else
                include = tok.canControlAsUser
            end
            if include then
                if open ~= nil and tok.charid == open.charid then
                    table.insert(result, 1, tok)
                else
                    result[#result+1] = tok
                end
            end
        end
    end
    --the test switch shows the open Hero's need whoever is looking.
    if HeroSheetTopBar.debugNeed ~= nil and open ~= nil and (result[1] == nil or result[1].charid ~= open.charid) then
        table.insert(result, 1, open)
    end
    return result
end

--- @class HeroSheetNeededBarArgs
--- @field covers fun(): boolean true while the sheet covers more than half the table
--- @field canMinimize fun(): boolean
--- @field minimize fun()
--- @field shownChanged nil|fun() the bar appeared or went (the space under it changed)

--- The needed bar. It polls only while its window is showing.
--- @param args HeroSheetNeededBarArgs
--- @return Panel
function HeroSheetTopBar.NeededBar(args)
    --needs the user closed, by "<charid>:<kind>"; forgotten once the need goes.
    local dismissed = {}
    local shownKey = nil
    local bar
    local text
    local backButton

    --- @return nil|string key
    --- @return nil|string line
    local function FirstNeed()
        local live = {}
        local firstKey, firstLine = nil, nil
        local director = dmhub.isDM
        local open = HeroSheet.Token()
        for _, tok in ipairs(NeedTokens()) do
            local kind = HeroNeeds.Need(tok)
            if HeroSheetTopBar.debugNeed ~= nil and open ~= nil and tok.charid == open.charid then
                kind = HeroSheetTopBar.debugNeed
            end
            --claiming the turn is the Heroes' side's (the Director picks
            --the monsters' turns on the initiative bar).
            if kind == "turn" and director and HeroSheetTopBar.debugNeed == nil then
                kind = nil
            end
            if kind ~= nil then
                local key = tok.charid .. ":" .. kind
                live[key] = true
                if firstKey == nil and not dismissed[key] then
                    firstKey = key
                    firstLine = string.format(NEED_LINES[kind], tok.name or "A creature")
                end
            end
        end
        for key, _ in pairs(dismissed) do
            if not live[key] then
                dismissed[key] = nil
            end
        end
        return firstKey, firstLine
    end

    local function Update()
        local key, line = nil, nil
        if args.covers() then
            key, line = FirstNeed()
        end
        shownKey = key
        local wasShown = not bar:HasClass("collapsed")
        bar:SetClass("collapsed", key == nil)
        if wasShown ~= (key ~= nil) and args.shownChanged ~= nil then
            args.shownChanged()
        end
        if line ~= nil then
            text.text = line
            backButton:SetClass("collapsed", not args.canMinimize())
        end
    end

    --it leaves the buttons their room by a cap, never by "100% available":
    --the engine restyles such a part every frame.
    text = gui.Label{
        classes = {"heroSheetNeedText"},
        width = "auto",
        maxWidth = "100%-260",
        halign = "left",
        height = "auto",
        fontSize = 15,
        bold = true,
        valign = "center",
        textWrap = false,
        textOverflow = "ellipsis",
    }

    backButton = gui.Label{
        classes = {"heroSheetNeedButton", "hoverable"},
        text = "Back to the table",
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "auto",
        height = 28,
        hpad = 12,
        borderBox = true,
        fontSize = 13,
        bold = true,
        halign = "right",
        valign = "center",
        textAlignment = "center",
        linger = function(element)
            gui.Tooltip("Minimize the sheet into its card; restoring it brings back your size and tab")(element)
        end,
        click = function(element)
            args.minimize()
        end,
    }

    --a square strip across the window.
    bar = gui.Panel{
        classes = {"heroSheetNeedBar", "collapsed"},
        bgimage = "panels/square.png",
        width = "100%",
        height = 34,
        flow = "horizontal",
        lpad = 14,
        rpad = 8,
        borderBox = true,
        gui.Panel{
            classes = {"heroSheetNeedDot"},
            bgimage = "panels/square.png",
            cornerRadius = 5,
            width = 9,
            height = 9,
            valign = "center",
            rmargin = 12,
            interactable = false,
        },
        text,
        backButton,
        gui.Panel{
            width = 28,
            height = 28,
            halign = "right",
            valign = "center",
            lmargin = 8,
            bgimage = "panels/square.png",
            bgcolor = "clear",
            linger = function(element)
                gui.Tooltip("Close: keep looking at the sheet")(element)
            end,
            click = function(element)
                if shownKey ~= nil then
                    dismissed[shownKey] = true
                end
                Update()
            end,
            gui.Panel{
                classes = {"heroSheetNeedClose"},
                bgimage = "window-chrome/chrome-close.png",
                width = 12,
                height = 12,
                halign = "center",
                valign = "center",
                interactable = false,
            },
        },
    }

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        bar,
        --polls while the window shows; a minimized or closed window is
        --collapsed, so it stops.
        gui.Panel{
            floating = true,
            interactable = false,
            width = 1,
            height = 1,
            thinkTime = NEED_POLL_SECONDS,
            think = function(element)
                Update()
            end,
            heroSheetWindowMode = function(element, data)
                Update()
            end,
        },
    }
end
