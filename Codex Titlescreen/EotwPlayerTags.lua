local mod = dmhub.GetModLoading()

--Player Tags: badges Encounter of the Week players earn and choose to show
--beside their name. Design: PLAYER_TAGS_BRIEF.md.
--
--The town server decides who has earned what. list-heroes (EotwRoster.Refresh)
--hands this module the caller's tags through EotwPlayerTags.Apply; other
--players' chosen tags ride beside their names in what the server sends:
--presence (/presence/<userid>.tag), chat lines (msg.tag), party records
--(players[<userid>].tag, hostTag) and list replies (a `tags` map).
--
--Two looks for one badge: Badge() is the bordered panel, for rows that give the
--name its own label; Inline() is the same tag as rich text, for places where
--the name sits inside a line of text (chat, bylines, "Controlled by").

local T = UIText.T

EotwPlayerTags = {}

--Badge styles. The panel badge is a "plaque": a dark gradient (dark -> black)
--with a 1px border and a stripe down its left edge in the bright color, and
--light text. The rarest tags (gold, ember) get a wider stripe, so rank never
--rests on color alone. The text form (Inline) is a bright highlight with ink text.
EotwPlayerTags.STYLES = {
    bronze = { bright = "#c08a4e", dark = "#36230f", light = "#f6e2c8", ink = "#24160a", stripe = 4 },
    copper = { bright = "#d48a5c", dark = "#3a1f10", light = "#ffe8d8", ink = "#2a1208", stripe = 4 },
    teal = { bright = "#4fb3a9", dark = "#0e2e2b", light = "#d8f5f1", ink = "#08201e", stripe = 4 },
    slate = { bright = "#8a96a6", dark = "#1f252d", light = "#e8edf2", ink = "#14181d", stripe = 4 },
    violet = { bright = "#a786e0", dark = "#24173c", light = "#efe6ff", ink = "#1a1030", stripe = 4 },
    silver = { bright = "#c8d0da", dark = "#2a2e34", light = "#f2f5f8", ink = "#1a1d22", stripe = 4 },
    gold = { bright = "#e8c25a", dark = "#3a2c0c", light = "#fff3cc", ink = "#2a1e08", stripe = 6 },
    ember = { bright = "#e8743e", dark = "#3a160c", light = "#ffd9c4", ink = "#2a0c06", stripe = 6 },
    --one-of-a-kind titles (the top builder of a town project): a deep royal purple.
    special = { bright = "#b065ff", dark = "#2a1048", light = "#f1e2ff", ink = "#1e0a36", stripe = 6 },
}

--A locked tag in the picker: muted greys keep the name readable but quiet.
local LOCKED_STYLE = { bright = "#5e574b", dark = "#24211c", light = "#9a9284", ink = "#24211c", stripe = 4 }

--Bumped whenever this account's tags change, so open panels can refresh.
EotwPlayerTags.revision = 0

--The tag list the server awards (list-heroes tags.defs), or nil before the
--first listing; until then the codex copy (EotwPlayerTagDefs) stands in.
---@type EotwPlayerTagDef[]|nil
local m_defs = nil
--This account's earned tags, oldest first.
---@type EotwEarnedTag[]
local m_earned = {}
--The tag this account shows, or nil.
---@type string|nil
local m_chosen = nil
--Tag ids newly earned and not yet announced by the banner on this machine.
---@type string[]
local m_toAnnounce = {}

--Tags this machine has already announced, so the banner shows each tag once.
setting{
    id = "eotw:announcedtags",
    default = "",
    storage = "preference",
}

local function AnnouncedSet()
    local set = {}
    local raw = dmhub.GetSettingValue("eotw:announcedtags")
    if type(raw) == "string" and raw ~= "" then
        local parsed = dmhub.FromJson(raw)
        if parsed ~= nil and type(parsed.result) == "table" then
            for _, id in ipairs(parsed.result) do
                set[id] = true
            end
        end
    end
    return set
end

local function RememberAnnounced(ids)
    local set = AnnouncedSet()
    local list = {}
    for id in pairs(set) do
        list[#list+1] = id
    end
    for _, id in ipairs(ids) do
        if not set[id] then
            list[#list+1] = id
        end
    end
    dmhub.SetSettingValue("eotw:announcedtags", dmhub.ToJson(list))
end

--- data -------------------------------------------------------------------

--One tag as EotwPlayerTagDefs.lua describes it (the server sends the same shape).
---@class EotwPlayerTagDef
---@field id string
---@field name string
---@field description string|nil
---@field style string a key of EotwPlayerTags.STYLES
---@field hidden boolean|nil

--One tag this account has earned.
---@class EotwEarnedTag
---@field id string
---@field at any when it was earned, as the server sent it
---@field seen boolean

--Every tag, as the server describes it (or the codex copy before it has).
---@return EotwPlayerTagDef[]
function EotwPlayerTags.Defs()
    if m_defs ~= nil then
        return m_defs
    end
    local local_defs = rawget(_G, "EotwPlayerTagDefs")
    return local_defs ~= nil and local_defs.tags or {}
end

---@param tagid string|nil
---@return EotwPlayerTagDef|nil
function EotwPlayerTags.Def(tagid)
    if type(tagid) ~= "string" or tagid == "" then
        return nil
    end
    for _, def in ipairs(EotwPlayerTags.Defs()) do
        if def.id == tagid then
            return def
        end
    end
    return nil
end

---@param def EotwPlayerTagDef
local function StyleOf(def)
    return EotwPlayerTags.STYLES[def.style] or EotwPlayerTags.STYLES.slate
end

---@param tagid string|nil
---@return boolean
function EotwPlayerTags.HasEarned(tagid)
    for _, earnedTag in ipairs(m_earned) do
        if earnedTag.id == tagid then
            return true
        end
    end
    return false
end

---@return string|nil tagid the tag this account shows
function EotwPlayerTags.Chosen()
    return m_chosen
end

---@return integer count earned tags not yet looked at in the picker
function EotwPlayerTags.UnseenCount()
    local count = 0
    for _, earnedTag in ipairs(m_earned) do
        if not earnedTag.seen and EotwPlayerTags.Def(earnedTag.id) ~= nil then
            count = count + 1
        end
    end
    return count
end

--Take in list-heroes' `tags` for this account: {defs, earned, chosen}.
---@param tags any the server's reply; anything but a table is ignored
function EotwPlayerTags.Apply(tags)
    if type(tags) ~= "table" then
        return
    end
    if type(tags.defs) == "table" then
        m_defs = tags.defs
    end
    local earned = {}
    local announced = nil
    for _, earnedTag in ipairs(tags.earned or {}) do
        if type(earnedTag) == "table" and type(earnedTag.id) == "string" then
            earned[#earned+1] = { id = earnedTag.id, at = earnedTag.at, seen = earnedTag.seen == true }
            if earnedTag.seen ~= true then
                announced = announced or AnnouncedSet()
                if not announced[earnedTag.id] and not table.contains(m_toAnnounce, earnedTag.id) then
                    m_toAnnounce[#m_toAnnounce+1] = earnedTag.id
                end
            end
        end
    end
    m_earned = earned
    m_chosen = type(tags.chosen) == "string" and tags.chosen or nil
    EotwPlayerTags.revision = EotwPlayerTags.revision + 1
end

--The tag another player shows, from the town's presence (nil if they show
--none or are not in town). Your own comes from what the server last said.
---@param userid string|nil
---@return string|nil tagid
function EotwPlayerTags.TagOf(userid)
    if userid == nil then
        return nil
    end
    if userid == dmhub.loginUserid then
        return m_chosen
    end
    local conn = EotwRoster.Connection()
    if conn == nil then
        return nil
    end
    local entry = conn:GetPath("/presence/" .. userid)
    if type(entry) == "table" and type(entry.tag) == "string" then
        return entry.tag
    end
    return nil
end

--Send one request to the town server; onDone(ok) is optional.
---@param action string
---@param args table
---@param onDone nil|fun(ok: boolean)
local function Request(action, args, onDone)
    local conn = EotwRoster.Connection()
    if conn == nil or not conn.connected then
        if onDone ~= nil then
            onDone(false)
        end
        return
    end
    conn:Request{
        action = action,
        args = args,
        success = function()
            if not mod.unloaded and onDone ~= nil then
                onDone(true)
            end
        end,
        error = function()
            if not mod.unloaded and onDone ~= nil then
                onDone(false)
            end
        end,
    }
end

--Show this earned tag beside your name (nil shows none).
---@param tagid string|nil
---@param onDone nil|fun(ok: boolean)
function EotwPlayerTags.Select(tagid, onDone)
    Request("select-tag", { tagid = tagid }, function(ok)
        if ok then
            m_chosen = tagid
            for _, earnedTag in ipairs(m_earned) do
                if earnedTag.id == tagid then
                    earnedTag.seen = true
                end
            end
            EotwPlayerTags.revision = EotwPlayerTags.revision + 1
        end
        if onDone ~= nil then
            onDone(ok)
        end
    end)
end

--The player has looked at their tags: clear every unseen mark.
function EotwPlayerTags.MarkAllSeen()
    if EotwPlayerTags.UnseenCount() == 0 then
        return
    end
    Request("mark-tags-seen", {}, function(ok)
        if ok then
            for _, earnedTag in ipairs(m_earned) do
                earnedTag.seen = true
            end
            EotwPlayerTags.revision = EotwPlayerTags.revision + 1
        end
    end)
end

--- looks --------------------------------------------------------------------

--The tag as rich text, for a name inside a line of text: a highlighted badge
--(<mark>) after a space, or "" for no (or an unknown) tag. The spaces inside
--the highlight pad it; <nobr> keeps it from breaking across lines.
---@param tagid string|nil
---@param sizePercent nil|integer the text size relative to the line (default 75)
---@return string
function EotwPlayerTags.Inline(tagid, sizePercent)
    local def = EotwPlayerTags.Def(tagid)
    if def == nil then
        return ""
    end
    local style = StyleOf(def)
    local name = string.gsub(def.name, "[<>]", "")
    return string.format(" <nobr><mark=%sff><color=%s><b><size=%d%%>  %s  </size></b></color></mark></nobr>",
        style.bright, style.ink, sizePercent or 75, name)
end

--The tag as a plaque badge panel, or nil for no (or an unknown) tag. The
--badge never grows past maxWidth: a long name ends in "...", with the full
--name and how it was earned in its tooltip.
---@param tagid string|nil
---@param opts nil|{fontSize: nil|number, maxWidth: nil|number, dim: nil|boolean, valign: nil|string}
---@return Panel|nil
function EotwPlayerTags.Badge(tagid, opts)
    local def = EotwPlayerTags.Def(tagid)
    if def == nil then
        return nil
    end
    opts = opts or {}
    local style = cond(opts.dim, LOCKED_STYLE, StyleOf(def))
    local fontSize = opts.fontSize or 12
    local maxWidth = opts.maxWidth or 180
    return gui.Panel{
        width = "auto",
        height = "auto",
        maxWidth = maxWidth,
        flow = "horizontal",
        valign = opts.valign or "center",
        bgimage = "panels/square.png",
        --white so the gradient's colors show as they are.
        bgcolor = "#ffffff",
        gradient = gui.Gradient{
            point_a = { x = 0.5, y = 1 },
            point_b = { x = 0.5, y = 0 },
            stops = {
                { position = 0, color = core.Color(style.dark) },
                { position = 1, color = core.Color("#0c0a08") },
            },
        },
        borderWidth = 1,
        borderColor = style.bright,
        cornerRadius = 3,
        linger = function(element)
            gui.Tooltip(string.format("<b>%s</b>\n%s", def.name, def.description or ""))(element)
        end,
        gui.Panel{
            width = style.stripe,
            height = fontSize + 8,
            valign = "center",
            bgimage = "panels/square.png",
            bgcolor = style.bright,
            interactable = false,
        },
        gui.Label{
            text = def.name,
            fontSize = fontSize,
            bold = true,
            color = style.light,
            width = "auto",
            height = "auto",
            maxWidth = maxWidth - style.stripe - 2,
            hpad = math.floor(fontSize * 0.55),
            vpad = 2,
            borderBox = true,
            valign = "center",
            textWrap = false,
            textOverflow = "ellipsis",
            interactable = false,
        },
    }
end

---@class EotwTagNameListPerson
---@field name string
---@field tag string|nil
---@field note string|nil shown after the badge, e.g. "(away)"

---@class EotwTagNameListOpts
---@field fontSize number
---@field color string
---@field opacity nil|number
---@field rowHeight number
---@field badgeMaxWidth number

--A list of names, each followed by its badge: "Here now (2): Ann [Legend], Bo".
--Returns the pieces to put in a horizontal panel with wrap = true; each name
--stays together with its badge when the line wraps.
---@param heading string text before the names
---@param people EotwTagNameListPerson[]
---@param opts EotwTagNameListOpts
---@return Panel[]
function EotwPlayerTags.NameList(heading, people, opts)
    local function Text(text)
        return gui.Label{
            text = text,
            fontSize = opts.fontSize,
            color = opts.color,
            opacity = opts.opacity or 1,
            width = "auto",
            height = "auto",
            valign = "center",
            textWrap = false,
        }
    end
    local headingLabel = Text(heading)
    --labels drop a trailing space, so the gap after the heading is a margin.
    headingLabel.selfStyle.rmargin = 5
    local items = { headingLabel }
    for i, person in ipairs(people) do
        local parts = { Text(person.name) }
        local badge = EotwPlayerTags.Badge(person.tag, { fontSize = 11, maxWidth = opts.badgeMaxWidth })
        if badge ~= nil then
            badge.selfStyle.lmargin = 5
            parts[#parts+1] = badge
        end
        if person.note ~= nil then
            parts[#parts+1] = Text(" " .. person.note)
        end
        if i < #people then
            parts[#parts+1] = Text(",")
        end
        items[#items+1] = gui.Panel{
            width = "auto",
            height = opts.rowHeight,
            flow = "horizontal",
            rmargin = 5,
            children = parts,
        }
    end
    return items
end

--- the picker ----------------------------------------------------------------

local TEXT = "#efe4cc"
local DIM = "#c9bfa9"
local GOLD = "#d9b56a"

---@param text string
---@param click fun()
---@param width nil|number defaults to 160
---@return Panel
local function FrameButton(text, click, width)
    return gui.Button{
        text = text,
        fontSize = 18,
        width = width or 160,
        height = 40,
        hmargin = 6,
        click = click,
    }
end

--The Hero's Guild's tag picker: every tag, earned ones selectable, the rest
--dimmed and marked as not earned yet (only you see those). Tags earned since
--you last opened it get a gold dot this one time.
---@param host Panel the screen the picker opens over
function EotwPlayerTags.ShowPicker(host)
    local dlg
    local unseen = {}
    for _, earnedTag in ipairs(m_earned) do
        if not earnedTag.seen then
            unseen[earnedTag.id] = true
        end
    end
    local statusLabel = nil
    local listPanel = nil

    local Rebuild
    local function Pick(tagid)
        if statusLabel ~= nil and statusLabel.valid then
            statusLabel.text = ""
        end
        EotwPlayerTags.Select(tagid, function(ok)
            if not ok and statusLabel ~= nil and statusLabel.valid then
                statusLabel.text = T("tags.select_failed")
            end
            Rebuild()
        end)
    end

    local function Row(args)
        return gui.Panel{
            classes = { "eotwTagRow", cond(args.locked, "locked", nil), cond(args.showing, "showing", nil) },
            width = "100%",
            height = 52,
            flow = "horizontal",
            hpad = 12,
            vmargin = 3,
            borderBox = true,
            bgimage = "panels/square.png",
            cornerRadius = 6,
            press = function()
                if not args.locked then
                    Pick(args.tagid)
                end
            end,
            --the gold dot: earned since you last opened this picker.
            gui.Panel{
                width = 10,
                height = 10,
                valign = "center",
                rmargin = 8,
                bgimage = "panels/square.png",
                cornerRadius = 5,
                bgcolor = cond(args.new, GOLD, "#00000000"),
                interactable = false,
            },
            args.badge or gui.Label{
                text = args.label,
                fontSize = 16,
                italics = true,
                color = DIM,
                width = 180,
                height = "auto",
                valign = "center",
                interactable = false,
            },
            gui.Label{
                text = args.description or "",
                fontSize = 15,
                color = DIM,
                width = "100%-320",
                height = "auto",
                lmargin = 14,
                valign = "center",
                interactable = false,
            },
            gui.Label{
                text = cond(args.showing, T("tags.picker.showing"), cond(args.locked, T("tags.picker.locked"), "")),
                fontSize = 14,
                bold = args.showing,
                color = cond(args.showing, GOLD, DIM),
                width = 90,
                height = "auto",
                halign = "right",
                valign = "center",
                textAlignment = "right",
                interactable = false,
            },
        }
    end

    Rebuild = function()
        if listPanel == nil or not listPanel.valid then
            return
        end
        local rows = {
            Row{ label = T("tags.picker.none"), showing = m_chosen == nil, tagid = nil },
        }
        local anyEarned = false
        --earned tags first, in the authored order; then the locked ones.
        for pass = 1, 2 do
            for _, def in ipairs(EotwPlayerTags.Defs()) do
                local earned = EotwPlayerTags.HasEarned(def.id)
                --a hidden tag stays out of the list until you have earned it.
                if (pass == 1) == earned and (earned or def.hidden ~= true) then
                    anyEarned = anyEarned or earned
                    rows[#rows+1] = Row{
                        tagid = def.id,
                        badge = gui.Panel{
                            width = 180,
                            height = "auto",
                            valign = "center",
                            interactable = false,
                            EotwPlayerTags.Badge(def.id, { fontSize = 14, maxWidth = 180, dim = not earned }),
                        },
                        description = def.description,
                        locked = not earned,
                        showing = m_chosen == def.id,
                        new = unseen[def.id] == true,
                    }
                end
            end
        end
        if not anyEarned then
            table.insert(rows, 1, gui.Label{
                text = T("tags.picker.empty"),
                fontSize = 16,
                italics = true,
                color = DIM,
                width = "100%",
                height = "auto",
                textAlignment = "center",
                vmargin = 8,
            })
        end
        listPanel.children = rows
    end

    dlg = gui.Panel{
        floating = true,
        width = 780,
        height = 640,
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#14110dff",
        borderWidth = 2,
        borderColor = "#8c7a55",
        cornerRadius = 10,
        flow = "vertical",
        styles = {
            Styles.Default,
            { selectors = { "eotwTagRow" }, bgcolor = "#221b13" },
            { selectors = { "eotwTagRow", "hover", "~locked" }, bgcolor = "#2c2318" },
            { selectors = { "eotwTagRow", "showing" }, borderWidth = 1, borderColor = GOLD },
        },
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            element:DestroySelf()
        end,
        gui.Label{
            text = T("tags.picker.title"),
            fontSize = 32,
            bold = true,
            color = TEXT,
            width = "auto",
            height = "auto",
            halign = "center",
            tmargin = 16,
        },
        gui.Label{
            text = T("tags.picker.subtitle"),
            fontSize = 17,
            italics = true,
            color = DIM,
            width = "90%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            vmargin = 4,
        },
        gui.Panel{
            width = "94%",
            height = "100%-170",
            halign = "center",
            vscroll = true,
            rpad = 10,
            borderBox = true,
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                create = function(element)
                    listPanel = element
                    Rebuild()
                end,
            },
        },
        gui.Label{
            text = "",
            fontSize = 15,
            color = "#ff8888",
            width = "100%",
            height = 22,
            textAlignment = "center",
            create = function(element)
                statusLabel = element
            end,
        },
        gui.Panel{
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "bottom",
            bmargin = 14,
            FrameButton(T("tags.picker.close_button"), function() dlg:DestroySelf() end),
        },
    }
    host:AddChild(dlg)
    EotwPlayerTags.MarkAllSeen()
end

--The Hero's Guild button that opens the picker, with a gold dot while any
--earned tag has not been looked at yet.
---@param host Panel the screen the picker opens over
---@return Panel
function EotwPlayerTags.GuildButton(host)
    local dot
    return gui.Button{
        text = T("tags.guild_button"),
        fontSize = 18,
        width = "auto",
        minWidth = 140,
        hpad = 16,
        height = 42,
        hmargin = 4,
        lmargin = 28,
        data = { seen = -1 },
        thinkTime = 0.5,
        think = function(element)
            if element.data.seen ~= EotwPlayerTags.revision then
                element.data.seen = EotwPlayerTags.revision
                if dot ~= nil and dot.valid then
                    dot:SetClass("collapsed", EotwPlayerTags.UnseenCount() == 0)
                end
            end
        end,
        linger = function(element)
            gui.Tooltip(T("tags.guild_tooltip"))(element)
        end,
        click = function()
            EotwPlayerTags.ShowPicker(host)
        end,
        gui.Panel{
            classes = { "collapsed" },
            floating = true,
            width = 10,
            height = 10,
            halign = "right",
            valign = "top",
            hmargin = 4,
            vmargin = 4,
            bgimage = "panels/square.png",
            cornerRadius = 5,
            bgcolor = GOLD,
            interactable = false,
            create = function(element)
                dot = element
            end,
        },
    }
end

--- the earn banner -----------------------------------------------------------

local m_banner = nil

--Show a card for tags earned since the last call (the town screen calls this
--from its think). With one new tag, its main button puts that tag beside
--your name; with several, it opens the picker. It never blocks the town.
---@param host Panel|nil the town screen (nil or gone: nothing happens)
function EotwPlayerTags.AnnounceEarned(host)
    if #m_toAnnounce == 0 or host == nil or not host.valid then
        return
    end
    if m_banner ~= nil and m_banner.valid then
        return
    end
    local ids = {}
    for _, id in ipairs(m_toAnnounce) do
        if EotwPlayerTags.Def(id) ~= nil and EotwPlayerTags.HasEarned(id) then
            ids[#ids+1] = id
        end
    end
    m_toAnnounce = {}
    if #ids == 0 then
        return
    end
    RememberAnnounced(ids)

    --one centered badge per line; a long backfill list shows its first six.
    local badges = {}
    for i, id in ipairs(ids) do
        local badge = i <= 6 and EotwPlayerTags.Badge(id, { fontSize = 16, maxWidth = 300 }) or nil
        if badge ~= nil then
            badge.selfStyle.halign = "center"
            badge.selfStyle.vmargin = 2
            badges[#badges+1] = badge
        end
    end
    local single = #ids == 1
    local def = EotwPlayerTags.Def(ids[1])
    local statusLabel = nil
    local function Close()
        if m_banner ~= nil and m_banner.valid then
            m_banner:DestroySelf()
        end
        m_banner = nil
    end

    m_banner = gui.Panel{
        floating = true,
        width = 520,
        height = "auto",
        halign = "center",
        valign = "top",
        vmargin = 90,
        vpad = 14,
        hpad = 18,
        borderBox = true,
        flow = "vertical",
        bgimage = "panels/square.png",
        --opaque: near-opaque alphas still let the town map show through.
        bgcolor = "#14110dff",
        borderWidth = 2,
        borderColor = GOLD,
        cornerRadius = 10,
        styles = { Styles.Default },
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = Close,
        gui.Label{
            text = cond(single, T("tags.banner.title_one"), T("tags.banner.title_many", { count = #ids })),
            fontSize = 26,
            bold = true,
            color = GOLD,
            width = "auto",
            height = "auto",
            halign = "center",
        },
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            vmargin = 10,
            children = badges,
        },
        gui.Label{
            classes = { cond(single, nil, "collapsed") },
            text = def ~= nil and def.description or "",
            fontSize = 17,
            color = TEXT,
            width = "100%",
            height = "auto",
            textAlignment = "center",
        },
        gui.Label{
            text = "",
            fontSize = 15,
            color = "#ff8888",
            width = "100%",
            height = "auto",
            textAlignment = "center",
            create = function(element)
                statusLabel = element
            end,
        },
        gui.Panel{
            width = "auto",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            tmargin = 8,
            FrameButton(cond(single, T("tags.banner.show_button"), T("tags.banner.choose_button")), function()
                if single then
                    EotwPlayerTags.Select(ids[1], function(ok)
                        if ok then
                            Close()
                        elseif statusLabel ~= nil and statusLabel.valid then
                            statusLabel.text = T("tags.select_failed")
                        end
                    end)
                else
                    Close()
                    EotwPlayerTags.ShowPicker(host)
                end
            end, 250),
            FrameButton(T("tags.banner.later_button"), Close, 120),
        },
    }
    host:AddChild(m_banner)
end
