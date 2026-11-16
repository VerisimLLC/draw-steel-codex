local mod = dmhub.GetModLoading()

--The About Encounter of the Week dialog, shown anywhere in Blackbottom: the
--town (the titlescreen's Codex menu) and every EotW game (the in-game Codex
--menu, EncounterOfTheWeekHud). It lives in this core mod because the town
--runs in the lobby game, where the EncounterOfTheWeek mod is not loaded.
--
--It shows the mode's credits, then, in a game, the encounter being played:
--who wrote it (its module's author) and, when its map came from a map pack,
--who made the map (the pack's creator organization).

--- @class EotwAbout
EotwAbout = {}

local T = UIText.T

--The banner is the Town Gate's art (GATE_ART in Codex Titlescreen/
--EncounterOfTheWeek.lua), which that file tags as Czepeku's, so the banner
--carries the watermark their licence asks for.
local ABOUT_ART = "db5bcf88-00fc-4e0b-89c9-5ddb98d1a772"
local ABOUT_WIDTH = 720
local ABOUT_ART_HEIGHT = 240
--The banner sits this far inside the frame so the frame's border (and its
--rounded corners) show around it; full-bleed art covered the border.
local ABOUT_ART_INSET = 6
local ABOUT_THUMB_WIDTH = 168
local ABOUT_THUMB_HEIGHT = 108

--The mode's credits, in order: the line (TextMeshPro rich text) given the
--name as it is shown, the name, and optionally a site the name links to.
--- @type {line: (fun(name: string): string), name: (fun(): string), url: nil|string}[]
local ABOUT_CREDITS = {
    { line = function(name) return T("eotw.about.credit.draw_steel", { name = name }) end, name = function() return "MCDM" end },
    { line = function(name) return T("eotw.about.credit.eotw", { name = name }) end, name = function() return T("eotw.about.credit.eotw_name") end },
    { line = function(name) return T("eotw.about.credit.montage", { name = name }) end, name = function() return "T. Ashley Jenkins" end },
    { line = function(name) return T("eotw.about.credit.cartography", { name = name }) end, name = function() return "Czepeku" end, url = "https://czepeku.com" },
}

--Map packs whose maps are credited to someone other than the pack's
--publishing organization: pack module fullid -> {name, url}.
--- @type table<string, {name: string, url: nil|string}>
local ABOUT_MAP_PACK_CREATORS = {
    ["mcdm-encountermaps"] = { name = "MAD Cartographer", url = "https://themad.network/the-mad-cartographer" },
}

--A name as rich text, bold if asked, and when it has a url a link: accent
--colored and underlined (some schemes' accent is close to the body text),
--which an AboutLinkLabel opens on press.
--- @param name string
--- @param url nil|string
--- @param bold nil|boolean
--- @return string
local function AboutName(name, url, bold)
    if bold then
        name = string.format("<b>%s</b>", name)
    end
    if url == nil or url == "" then
        return name
    end
    return ThemeEngine.ResolveTokens(string.format("<color=@accent><u><link=%s>%s</link></u></color>", url, name))
end

--A gui.Label whose <link=url> spans open their url when pressed.
--- @param options table
--- @return Panel
local function AboutLinkLabel(options)
    options.links = true
    options.press = function(element)
        if element.linkHovered ~= nil then
            dmhub.OpenURL(element.linkHovered)
        end
    end
    return gui.Label(options)
end

local ABOUT_STYLES = {
    {
        selectors = {"label", "eotwAboutTitle"},
        fontSize = 30,
        bold = true,
        color = "@fgStrong",
        width = "100%-48",
        height = "auto",
        halign = "center",
        textAlignment = "center",
    },
    {
        selectors = {"label", "eotwAboutCredit"},
        fontSize = 18,
        color = "@fg",
        width = "100%-24",
        height = "auto",
        halign = "center",
        textAlignment = "center",
        textWrap = true,
        vmargin = 5,
    },
    {
        selectors = {"label", "eotwAboutHeading"},
        fontSize = 22,
        bold = true,
        color = "@fgStrong",
        width = "100%",
        height = "auto",
        textWrap = true,
    },
    {
        selectors = {"label", "eotwAboutLine"},
        fontSize = 17,
        color = "@fg",
        width = "100%",
        height = "auto",
        textWrap = true,
        tmargin = 6,
    },
    {
        selectors = {"eotwAboutRule"},
        width = "100%-64",
        height = 1,
        halign = "center",
        bgimage = "panels/square.png",
        bgcolor = "@border",
        vmargin = 16,
    },
}

--- @alias AboutCredit {name: string, url: nil|string}

--Creator organization id -> {name, url}, or false when the lookup failed.
--- @type table<string, AboutCredit|false>
local g_aboutOrgNames = {}

--Calls back with an organization's display name and website, or nil when
--it has no name or the lookup fails. Answers at once from the cache.
--- @param orgid nil|string
--- @param callback fun(credit: nil|AboutCredit)
local function AboutOrgName(orgid, callback)
    if orgid == nil or orgid == "" then
        callback(nil)
        return
    end
    local cached = g_aboutOrgNames[orgid]
    if cached ~= nil then
        callback(cached or nil)
        return
    end
    module.GetOrganizationInfo{
        orgid = orgid,
        success = function(info)
            local credit = nil
            local name = type(info) == "table" and info.displayName or nil
            if type(name) == "string" and name ~= "" then
                local url = info.url
                credit = { name = name, url = cond(type(url) == "string" and url ~= "", url, nil) }
            end
            g_aboutOrgNames[orgid] = credit or false
            if not mod.unloaded then
                callback(credit)
            end
        end,
        failure = function()
            g_aboutOrgNames[orgid] = false
            if not mod.unloaded then
                callback(nil)
            end
        end,
    }
end

--Calls back with the name of whoever published an encounter module: its
--creator organization's name, else the organization its author id names
--(author ids are often organization ids: "mcdm"), else the author id. nil
--when the module is not known here.
--- @param moduleid nil|string
--- @param callback fun(credit: nil|AboutCredit)
local function AboutEncounterAuthor(moduleid, callback)
    local info = moduleid ~= nil and module.GetModule(moduleid) or nil
    if info == nil then
        callback(nil)
        return
    end
    local org, authorid = nil, nil
    pcall(function() org = info.org end)
    pcall(function() authorid = info.authorid end)
    if authorid == "" then
        authorid = nil
    end
    if org == nil or org == "" then
        org = authorid
    end
    AboutOrgName(org, function(credit)
        if credit == nil and authorid ~= nil then
            credit = { name = authorid }
        end
        callback(credit)
    end)
end

--The map pack a map was added from (its module fullid), or nil.
--- @param mapid string
--- @return nil|string
local function AboutMapPack(mapid)
    local pack = nil
    pcall(function()
        local source = game.GetMap(mapid).packSource
        if source ~= nil and type(source.pack) == "string" and source.pack ~= "" then
            pack = source.pack
        end
    end)
    return pack
end

--The creator organization that publishes a map pack, or nil. Also used by
--the in-game map watermark (EncounterOfTheWeekHud).
--- @param pack string
--- @return nil|string
function EotwAbout.MapPackOrg(pack)
    local org = nil
    for _,p in ipairs(mappacks.packs or {}) do
        if p.id == pack then
            org = p.org
        end
    end
    if org == nil or org == "" then
        pcall(function() org = module.GetModule(pack).org end)
    end
    if org == "" then
        return nil
    end
    return org
end

--Calls back with the map pack a map came from, or nil. A map added before
--provenance was recorded is only recognised once the pack index has synced,
--so an unsynced index is synced first. Also used by the in-game map
--watermark (EncounterOfTheWeekHud).
--- @param mapid string
--- @param callback fun(pack: nil|string)
function EotwAbout.MapPackOf(mapid, callback)
    local pack = AboutMapPack(mapid)
    if pack ~= nil or mappacks.synced then
        callback(pack)
        return
    end
    mappacks.Sync{
        success = function()
            if not mod.unloaded then
                callback(AboutMapPack(mapid))
            end
        end,
        error = function()
            if not mod.unloaded then
                callback(nil)
            end
        end,
    }
end

--Calls back with the creator of a map that came from a map pack (the pack's
--entry in ABOUT_MAP_PACK_CREATORS, else its creator organization), or nil
--for any other map.
--- @param mapid string
--- @param callback fun(credit: nil|AboutCredit)
local function AboutMapCreator(mapid, callback)
    EotwAbout.MapPackOf(mapid, function(pack)
        if pack == nil then
            callback(nil)
        elseif ABOUT_MAP_PACK_CREATORS[pack] ~= nil then
            callback(ABOUT_MAP_PACK_CREATORS[pack])
        else
            AboutOrgName(EotwAbout.MapPackOrg(pack), callback)
        end
    end)
end

--The "About <encounter>" part of the dialog: heading, author and map
--creator (filled in as their lookups come back), beside the map's thumbnail
--when it has one.
--- @param info {title: string, mapid: string, moduleid: nil|string}
--- @return Panel
local function AboutEncounterSection(info)
    --hidden until its lookup comes back with a name.
    local function PendingLine()
        return AboutLinkLabel{
            classes = {"eotwAboutLine", "collapsed"},
            text = "",
            fill = function(element, text)
                element.text = text
                element:SetClass("collapsed", false)
            end,
        }
    end

    local authorLabel = PendingLine()
    local mapLabel = PendingLine()

    local function Fill(label, line)
        return function(credit)
            if credit ~= nil and label.valid then
                label:FireEvent("fill", line(AboutName(credit.name, credit.url, true)))
            end
        end
    end
    AboutEncounterAuthor(info.moduleid, Fill(authorLabel, function(name) return T("eotw.about.written_by", { name = name }) end))
    AboutMapCreator(info.mapid, Fill(mapLabel, function(name) return T("eotw.about.map_by", { name = name }) end))

    local thumb = nil
    pcall(function() thumb = game.GetMap(info.mapid).thumbnailImage end)
    local thumbPanel = nil
    if type(thumb) == "string" and thumb ~= "" then
        thumbPanel = gui.Panel{
            width = ABOUT_THUMB_WIDTH,
            height = ABOUT_THUMB_HEIGHT,
            valign = "top",
            rmargin = 20,
            flow = "none",
            CreatorCredit.Backdrop{
                width = ABOUT_THUMB_WIDTH,
                height = ABOUT_THUMB_HEIGHT,
                image = thumb,
                badge = false,
            },
        }
    end

    return gui.Panel{
        width = "100%-64",
        height = "auto",
        halign = "center",
        flow = "horizontal",
        thumbPanel,
        gui.Panel{
            width = cond(thumbPanel ~= nil, string.format("100%%-%d", ABOUT_THUMB_WIDTH + 20), "100%"),
            height = "auto",
            valign = "center",
            flow = "vertical",
            gui.Label{
                classes = {"eotwAboutHeading"},
                text = T("eotw.about.encounter_heading", { title = info.title }),
            },
            authorLabel,
            mapLabel,
        },
    }
end

--The Codex menu row's label (in town and in a game).
--- @return string
function EotwAbout.MenuText()
    return T("eotw.about.menu_item")
end

--Builds the dialog. The caller mounts it and takes it down in close (Close
--and Escape both call it).
--  encounter: the encounter being played ({title, mapid, moduleid}), or nil
--             to show the credits alone (in town).
--- @param args {encounter: nil|{title: string, mapid: string, moduleid: nil|string}, close: fun()}
--- @return Panel
function EotwAbout.Create(args)
    local credits = {}
    for _,credit in ipairs(ABOUT_CREDITS) do
        credits[#credits+1] = AboutLinkLabel{
            classes = {"eotwAboutCredit"},
            text = credit.line(AboutName(credit.name(), credit.url)),
        }
    end

    local encounterChildren = {}
    if args.encounter ~= nil then
        encounterChildren[#encounterChildren+1] = gui.Panel{ classes = {"eotwAboutRule"} }
        encounterChildren[#encounterChildren+1] = AboutEncounterSection(args.encounter)
    end

    return gui.Panel{
        classes = {"framedPanel"},
        styles = ThemeEngine.MergeStyles(ABOUT_STYLES),
        width = ABOUT_WIDTH,
        height = "auto",
        halign = "center",
        valign = "center",
        flow = "vertical",
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        captureEscape = true,
        escape = function(element)
            args.close()
        end,

        --the banner: the art, cover-fitted, with Czepeku's watermark.
        gui.Panel{
            width = ABOUT_WIDTH - 2 * ABOUT_ART_INSET,
            height = ABOUT_ART_HEIGHT,
            halign = "center",
            tmargin = ABOUT_ART_INSET,
            flow = "none",
            CreatorCredit.Backdrop{
                width = ABOUT_WIDTH - 2 * ABOUT_ART_INSET,
                height = ABOUT_ART_HEIGHT,
                image = ABOUT_ART,
                creator = "czepeku",
                badge = { hmargin = 16, vmargin = 12, light = true },
            },
        },

        gui.Label{
            classes = {"eotwAboutTitle"},
            text = T("eotw.about.title"),
            tmargin = 18,
            bmargin = 12,
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            children = credits,
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            children = encounterChildren,
        },

        gui.Button{
            classes = {"sizeL"},
            text = T("eotw.about.close"),
            halign = "center",
            tmargin = 22,
            bmargin = 18,
            click = function()
                args.close()
            end,
        },
    }
end

--The dialog over the town, on a dimmed backdrop that blocks the town under it.
--- @type nil|Panel
local m_townDialog = nil

--Opens the dialog over the town screen (or leaves it up if it is). Does
--nothing while the town is not open.
function EotwAbout.ShowInTown()
    if m_townDialog ~= nil and m_townDialog.valid then
        return
    end
    local town = EncounterOfTheWeek.TownScreen()
    if town == nil then
        return
    end

    local function Close()
        if m_townDialog ~= nil and m_townDialog.valid then
            m_townDialog:DestroySelf()
        end
        m_townDialog = nil
    end

    m_townDialog = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        bgcolor = "#000000b0",
        EotwAbout.Create{ close = Close },
    }
    town:AddChild(m_townDialog)
end
