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

--Badge styles: fill, border and text colors, and border width. The wider
--border marks the rarest tags, so rank never rests on color alone.
EotwPlayerTags.STYLES = {
    bronze = { fill = "#4a301a", border = "#c08a4e", text = "#f6e2c8", width = 1 },
    copper = { fill = "#4a2818", border = "#d48a5c", text = "#ffe8d8", width = 1 },
    teal = { fill = "#123634", border = "#4fb3a9", text = "#dcf7f3", width = 1 },
    slate = { fill = "#262c34", border = "#8a96a6", text = "#e8edf2", width = 1 },
    violet = { fill = "#2c1e44", border = "#a786e0", text = "#efe6ff", width = 1 },
    silver = { fill = "#34383e", border = "#c8d0da", text = "#f2f5f8", width = 1 },
    gold = { fill = "#463610", border = "#e8c25a", text = "#fff3cc", width = 2 },
    ember = { fill = "#461a12", border = "#e8743e", text = "#ffe4d6", width = 2 },
}

--Bumped whenever this account's tags change, so open panels can refresh.
EotwPlayerTags.revision = 0

--The tag list the server awards (list-heroes tags.defs), or nil before the
--first listing; until then the codex copy (EotwPlayerTagDefs) stands in.
local m_defs = nil
--This account's earned tags, oldest first: { {id, at, seen}, ... }.
local m_earned = {}
--The tag this account shows, or nil.
local m_chosen = nil
--Tag ids newly earned and not yet announced by the banner on this machine.
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

--Every tag, as the server describes it (or the codex copy before it has).
---@return table[] defs each {id, name, description, style}
function EotwPlayerTags.Defs()
    if m_defs ~= nil then
        return m_defs
    end
    local local_defs = rawget(_G, "EotwPlayerTagDefs")
    return local_defs ~= nil and local_defs.tags or {}
end

---@param tagid string|nil
---@return table|nil def {id, name, description, style}
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

local function StyleOf(def)
    return EotwPlayerTags.STYLES[def.style] or EotwPlayerTags.STYLES.slate
end

---@return boolean
function EotwPlayerTags.HasEarned(tagid)
    for _, e in ipairs(m_earned) do
        if e.id == tagid then
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
    local n = 0
    for _, e in ipairs(m_earned) do
        if not e.seen and EotwPlayerTags.Def(e.id) ~= nil then
            n = n + 1
        end
    end
    return n
end

--Take in list-heroes' `tags` for this account: {defs, earned, chosen}.
function EotwPlayerTags.Apply(tags)
    if type(tags) ~= "table" then
        return
    end
    if type(tags.defs) == "table" then
        m_defs = tags.defs
    end
    local earned = {}
    local announced = nil
    for _, e in ipairs(tags.earned or {}) do
        if type(e) == "table" and type(e.id) == "string" then
            earned[#earned+1] = { id = e.id, at = e.at, seen = e.seen == true }
            if e.seen ~= true then
                announced = announced or AnnouncedSet()
                if not announced[e.id] then
                    local queued = false
                    for _, id in ipairs(m_toAnnounce) do
                        queued = queued or id == e.id
                    end
                    if not queued then
                        m_toAnnounce[#m_toAnnounce+1] = e.id
                    end
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

--Show this earned tag beside your name (nil shows none). onDone(ok) optional.
function EotwPlayerTags.Select(tagid, onDone)
    Request("select-tag", { tagid = tagid }, function(ok)
        if ok then
            m_chosen = tagid
            for _, e in ipairs(m_earned) do
                if e.id == tagid then
                    e.seen = true
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
            for _, e in ipairs(m_earned) do
                e.seen = true
            end
            EotwPlayerTags.revision = EotwPlayerTags.revision + 1
        end
    end)
end

--- looks --------------------------------------------------------------------

--The tag as rich text, for a name inside a line of text: " [Name]" in the
--tag's color at a smaller size, or "" for no (or an unknown) tag.
---@param tagid string|nil
---@param sizePercent nil|integer the text size relative to the line (default 80)
---@return string
function EotwPlayerTags.Inline(tagid, sizePercent)
    local def = EotwPlayerTags.Def(tagid)
    if def == nil then
        return ""
    end
    local name = string.gsub(def.name, "[<>]", "")
    return string.format(" <color=%s><size=%d%%>[%s]</size></color>", StyleOf(def).border, sizePercent or 80, name)
end

--The tag as a bordered badge panel, or nil for no (or an unknown) tag. The
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
    local style = StyleOf(def)
    --a locked tag in the picker: muted greys keep the name readable but quiet.
    if opts.dim then
        style = { fill = "#1c1915", border = "#5e574b", text = "#9a9284", width = 1 }
    end
    local fontSize = opts.fontSize or 12
    return gui.Panel{
        width = "auto",
        height = "auto",
        maxWidth = opts.maxWidth or 180,
        valign = opts.valign or "center",
        hpad = math.floor(fontSize * 0.5),
        vpad = 1,
        borderBox = true,
        bgimage = "panels/square.png",
        bgcolor = style.fill,
        borderWidth = style.width,
        borderColor = style.border,
        cornerRadius = 4,
        linger = function(element)
            gui.Tooltip(string.format("<b>%s</b>\n%s", def.name, def.description or ""))(element)
        end,
        gui.Label{
            text = def.name,
            fontSize = fontSize,
            bold = true,
            color = style.text,
            width = "auto",
            height = "auto",
            maxWidth = (opts.maxWidth or 180) - fontSize,
            textWrap = false,
            textOverflow = "ellipsis",
            interactable = false,
        },
    }
end

--- the picker ----------------------------------------------------------------

local TEXT = "#efe4cc"
local DIM = "#c9bfa9"
local GOLD = "#d9b56a"

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
--dimmed and marked Locked (only you see those). Opening it marks your new
--tags seen; their dots show this once.
function EotwPlayerTags.ShowPicker(host)
    local dlg
    local unseen = {}
    for _, e in ipairs(m_earned) do
        if not e.seen then
            unseen[e.id] = true
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
                if (pass == 1) == earned then
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

--The Hero's Guild's "Tags" button, with a gold dot while tags are unseen.
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
--from its think, with itself as the host). One tag offers "Show This Tag";
--several offer the picker. It never blocks the town; Esc or Later closes it.
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
            end, 180),
            FrameButton(T("tags.banner.later_button"), Close, 120),
        },
    }
    host:AddChild(m_banner)
end
