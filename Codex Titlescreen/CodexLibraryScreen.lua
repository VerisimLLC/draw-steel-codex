local mod = dmhub.GetModLoading()

--------------------------------------------------------------------------------
--The Library: a fullscreen shelf of the PDF books the user owns. Reached from
--the Codex menu (next to Shop and Inventory) on the titlescreen and in game.
--Clicking a cover opens the normal PDF viewer, which can be popped out.
--
--Books come from published modules, so the Library works in any game and on
--the titlescreen. A book is found in the loaded game's PDFs when present;
--otherwise module.DownloadModulePDFDocuments fetches the module's PDF records
--(disk-cached) without installing it. Premium adventures only show once the
--user owns the module (store purchase or Patreon).
--------------------------------------------------------------------------------

--Each book names the module that ships it. A premium entry has no docid: it
--shows every visible PDF the module ships, once the user owns it.
local g_librarySections = {
    {
        title = "Draw Steel",
        books = {
            { moduleid = "mcdm-drawsteel", docid = "e6cab5b7-a1c9-4b12-ad06-ed573f6ba904" }, --Heroes
            { moduleid = "mcdm-drawsteel", docid = "cc66844a-04d0-49a0-8687-65ef83b15363" }, --Monsters
            { moduleid = "mcdm-drawsteel", docid = "8e6b780e-754c-4c35-902f-c52e5745cfea" }, --Encounters
            { moduleid = "mcdm-drawsteel", docid = "6a761787-90ad-4cd8-b2cb-43064db57a20" }, --The Summoner
            { moduleid = "mcdm-drawsteel", docid = "d04b544a-5144-4c0f-bd3d-2e9fc27e3bc4" }, --The Beastheart
        },
    },
    {
        title = "Adventures",
        books = {
            { moduleid = "venla-deliantomb", docid = "4dad1bc1-d23a-4780-ac6a-536a0f9cd9b9" }, --Delian Tomb Adventure
            { moduleid = "venla-deliantomb", docid = "cbddffb4-0c92-4245-bdfb-ad7621163a57" }, --Delian Tomb Encounters
            { moduleid = "codex-redroad", premium = true },
            { moduleid = "codex-darkheart", premium = true },
        },
    },
}

--Every docid the catalog names explicitly. A premium module's listing skips
--these: modules ship copies of books they depend on (Dark Heart of the Wood
--carries Draw Steel Monsters), which would otherwise show twice.
local g_catalogDocIds = {}
for _,section in ipairs(g_librarySections) do
    for _,book in ipairs(section.books) do
        if book.docid ~= nil then
            g_catalogDocIds[book.docid] = true
        end
    end
end

--Book cover size, in the screen's 1920-wide logical units (US letter aspect).
local COVER_WIDTH = 256
local COVER_HEIGHT = math.floor(COVER_WIDTH * 11 / 8.5)

local ACCENT = "#d6b46a"

--Per-module PDF fetches for this session: moduleid -> {status, docs}.
--status is "loading", "ready" or "failed".
local g_moduleDocs = {}

--Returns the module's PDF records, or nil while (or if) they are unavailable.
--Starts the fetch on first ask; onready runs once when it lands.
local function GetModuleDocs(moduleid, onready)
    local entry = g_moduleDocs[moduleid]
    if entry == nil then
        entry = { status = "loading", docs = nil, waiting = {} }
        g_moduleDocs[moduleid] = entry
        module.DownloadModulePDFDocuments{
            moduleid = moduleid,
            success = function(docs)
                entry.status = "ready"
                entry.docs = docs
                for _,fn in ipairs(entry.waiting) do
                    fn()
                end
                entry.waiting = {}
            end,
            failure = function(message)
                print("Library: could not load PDFs for", moduleid, message)
                --kept as failed (not retried) until the Library is reopened;
                --see ForgetFailedModules.
                entry.status = "failed"
                for _,fn in ipairs(entry.waiting) do
                    fn()
                end
                entry.waiting = {}
            end,
        }
    end

    if entry.status == "ready" then
        return entry.docs
    end

    if onready ~= nil and entry.status == "loading" then
        entry.waiting[#entry.waiting + 1] = onready
    end
    return nil
end

local function IsModuleLoading(moduleid)
    local entry = g_moduleDocs[moduleid]
    return entry ~= nil and entry.status == "loading"
end

--Each Library open gets a fresh try at modules whose fetch failed.
local function ForgetFailedModules()
    for moduleid,entry in pairs(g_moduleDocs) do
        if entry.status == "failed" then
            g_moduleDocs[moduleid] = nil
        end
    end
end

local function OwnedModuleSet()
    local result = {}
    for _,list in ipairs({ module.GetOurPurchasedModules(), module.GetOurPatreonModules() }) do
        for _,moduleid in ipairs(list or {}) do
            result[moduleid] = true
        end
    end
    return result
end

--Resolves a section to its list of PDFDocumentAssetLua records. Books still
--being fetched are left out; onchange runs when a fetch lands so the caller
--can resolve again. Returns the docs plus whether anything is still loading.
local function ResolveSection(section, owned, onchange)
    local result = {}
    local seen = {}
    local loading = false
    local localDocs = assets.pdfDocumentsTable

    local function add(doc, id)
        if doc ~= nil and not doc.hidden and not seen[id] then
            seen[id] = true
            result[#result + 1] = doc
        end
    end

    for _,book in ipairs(section.books) do
        if book.premium then
            if owned[book.moduleid] then
                local docs = GetModuleDocs(book.moduleid, onchange)
                if docs == nil then
                    loading = loading or IsModuleLoading(book.moduleid)
                else
                    local list = {}
                    for id,doc in pairs(docs) do
                        if not doc.hidden and not g_catalogDocIds[id] then
                            list[#list + 1] = { id = id, doc = doc }
                        end
                    end
                    table.sort(list, function(a, b)
                        if a.doc.ord ~= b.doc.ord then
                            return a.doc.ord < b.doc.ord
                        end
                        return (a.doc.description or "") < (b.doc.description or "")
                    end)
                    for _,item in ipairs(list) do
                        add(item.doc, item.id)
                    end
                end
            end
        elseif localDocs[book.docid] ~= nil then
            add(localDocs[book.docid], book.docid)
        else
            local docs = GetModuleDocs(book.moduleid, onchange)
            if docs == nil then
                loading = loading or IsModuleLoading(book.moduleid)
            else
                add(docs[book.docid], book.docid)
            end
        end
    end

    return result, loading
end

--Where an opened book's viewer goes: the normal gamehud modal in game (it
--sorts above the Library), the titlescreen root otherwise, since the gamehud
--modal layer renders underneath the titlescreen.
local function OpenBook(doc)
    audio.FireSoundEvent("Mouse.Click")
    local options = nil
    if not (dmhub.inGame and not dmhub.isLobbyGame) then
        local root = rawget(_G, "CodexTitlescreenRoot")
        if root ~= nil and root.valid then
            options = { host = root }
        end
    end
    OpenPDFDocument(doc, nil, options)
end

local function CreateBookCard(doc)
    --doc.doc starts the PDF's download; read it once per card.
    local document = doc.doc

    return gui.Panel {
        classes = { "libraryBook" },
        flow = "vertical",
        width = COVER_WIDTH,
        height = "auto",
        hmargin = 28,
        vmargin = 20,

        gui.Panel {
            classes = { "libraryCoverFrame" },
            bgimage = true,
            width = COVER_WIDTH,
            height = COVER_HEIGHT,

            click = function(element)
                OpenBook(doc)
            end,
            hover = function(element)
                audio.FireSoundEvent("Mouse.Hover")
            end,

            --shows through until the cover renders on top of it.
            gui.LoadingIndicator {
                halign = "center",
                valign = "center",
                interactable = false,
            },

            gui.Panel {
                classes = { "libraryCover" },
                floating = true,
                bgimage = document:GetPageCoverId(0),
                width = "100%",
                height = "100%",
                interactable = false,
            },
        },

        gui.Label {
            classes = { "libraryBookTitle" },
            text = doc.description,
            width = COVER_WIDTH,
            height = "auto",
            tmargin = 14,
            interactable = false,
        },

        gui.Label {
            classes = { "libraryBookPages" },
            text = "",
            width = COVER_WIDTH,
            height = "auto",
            tmargin = 2,
            interactable = false,

            create = function(element)
                element:FireEvent("pollPages")
            end,
            pollPages = function(element)
                local summary = document.summary
                if summary ~= nil and summary.npages ~= nil then
                    element.text = string.format("%d pages", summary.npages)
                else
                    element:ScheduleEvent("pollPages", 0.5)
                end
            end,
        },
    }
end

local function CreateSection(section, owned)
    local sectionPanel
    local shelf = gui.Panel {
        flow = "horizontal",
        wrap = true,
        width = "100%",
        height = "auto",
        halign = "left",
    }

    local loadingLabel = gui.Label {
        classes = { "libraryNote", "collapsed" },
        text = "Loading your books...",
    }

    sectionPanel = gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        bmargin = 36,

        refreshShelf = function(element)
            local docs, loading = ResolveSection(section, owned, function()
                if sectionPanel ~= nil and sectionPanel.valid then
                    sectionPanel:FireEvent("refreshShelf")
                end
            end)

            --only rebuild when the set of books changed, so covers that are
            --already showing do not flash.
            local ids = {}
            for _,doc in ipairs(docs) do
                ids[#ids + 1] = doc.id
            end
            local key = table.concat(ids, ",")
            if key ~= element.data.key then
                element.data.key = key
                local cards = {}
                for _,doc in ipairs(docs) do
                    cards[#cards + 1] = CreateBookCard(doc)
                end
                shelf.children = cards
            end

            loadingLabel:SetClass("collapsed", not loading)
            element:SetClass("collapsed", #docs == 0 and not loading)
        end,

        data = { key = nil },

        gui.Label {
            classes = { "librarySectionTitle" },
            text = section.title,
        },

        gui.Panel {
            classes = { "librarySectionRule" },
            bgimage = true,
            width = "100%-56",
            height = 1,
            hmargin = 28,
            bmargin = 8,
        },

        loadingLabel,
        shelf,
    }

    sectionPanel:FireEvent("refreshShelf")
    return sectionPanel
end

local g_libraryStyles = {
    {
        selectors = { "label" },
        fontFace = "Inter",
        color = "#e8e2d6",
    },
    {
        selectors = { "libraryTitle" },
        fontFace = "Berling",
        fontSize = 64,
        color = "#f4ecdc",
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "librarySubtitle" },
        fontSize = 18,
        color = "#b9ae99",
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "librarySectionTitle" },
        fontFace = "Berling",
        fontSize = 32,
        color = ACCENT,
        width = "auto",
        height = "auto",
        hmargin = 28,
        bmargin = 6,
    },
    {
        selectors = { "librarySectionRule" },
        bgcolor = ACCENT,
        opacity = 0.35,
    },
    {
        selectors = { "libraryNote" },
        fontSize = 16,
        italics = true,
        color = "#b9ae99",
        width = "auto",
        height = "auto",
        hmargin = 28,
        vmargin = 8,
    },
    {
        selectors = { "libraryCoverFrame" },
        bgcolor = "#1b1814",
        borderWidth = 1,
        borderColor = "#00000000",
        cornerRadius = 3,
    },
    {
        selectors = { "libraryCoverFrame", "hover" },
        scale = 1.035,
        borderWidth = 2,
        borderColor = ACCENT,
        transitionTime = 0.12,
    },
    {
        selectors = { "libraryCoverFrame", "press" },
        brightness = 0.85,
    },
    {
        selectors = { "libraryCover" },
        bgcolor = "white",
        cornerRadius = 3,
    },
    {
        selectors = { "libraryBookTitle" },
        fontFace = "Berling",
        fontSize = 20,
        color = "#f4ecdc",
        textAlignment = "center",
        textWrap = true,
    },
    {
        selectors = { "libraryBookPages" },
        fontSize = 14,
        color = "#9c9281",
        textAlignment = "center",
    },
}

--Builds the Library screen. args.host is the panel it is added to; it must
--carry .data.dialog (for sizing), like the Shop screen's host.
function CreateLibraryScreen(args)
    local dialog = args.host.data.dialog

    --same scaling as the Shop screen: a 1920-wide logical canvas, or 1080
    --tall on screens wider than 16:9.
    local uiscale = dialog.width / 1920
    local panelHeight = 1920 * (dialog.height / dialog.width)
    local panelWidth = 1920
    if panelHeight < 1080 then
        uiscale = dialog.height / 1080
        panelHeight = 1080
        panelWidth = dialog.width / uiscale
    end

    ForgetFailedModules()
    local owned = OwnedModuleSet()

    local sections = {}
    for _,section in ipairs(g_librarySections) do
        sections[#sections + 1] = CreateSection(section, owned)
    end

    local screen
    screen = gui.Panel {
        floating = true,
        width = panelWidth,
        height = panelHeight,
        uiscale = uiscale,
        halign = "center",
        valign = "center",
        bgimage = cond(dmhub.whiteLabel == "mcdm", "panels/storebg2.png", "panels/square.png"),
        bgcolor = cond(dmhub.whiteLabel == "mcdm", "white", "#15120e"),
        styles = {
            ThemeEngine.GetStyles(),
            g_libraryStyles,
        },

        closeLibrary = function(element)
            element:DestroySelf()
        end,

        --darkens the background art so the covers read clearly.
        gui.Panel {
            floating = true,
            bgimage = true,
            bgcolor = "#0b0907d9",
            width = "100%",
            height = "100%",
            interactable = false,
        },

        gui.Panel {
            flow = "vertical",
            width = 1600,
            height = "100%",
            halign = "center",
            valign = "top",

            gui.Label {
                classes = { "libraryTitle" },
                text = "Library",
                halign = "center",
                tmargin = 48,
            },

            gui.Label {
                classes = { "librarySubtitle" },
                text = "Your Draw Steel books. Click a cover to start reading.",
                halign = "center",
                tmargin = 4,
                bmargin = 28,
            },

            gui.Panel {
                flow = "vertical",
                width = "100%",
                height = "100% available",
                vscroll = true,
                children = sections,
            },
        },

        gui.Button {
            classes = { "closeButton", "sizeL" },
            floating = true,
            halign = "left",
            valign = "top",
            hmargin = 16,
            vmargin = 16,
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_DIALOG,
            click = function(element)
                screen:FireEvent("closeLibrary")
            end,
        },
    }

    screen:PulseClass("fadein")
    return screen
end

--Opens the Library over whatever is showing: the game hud's fullscreen shop
--layer in a real game, the titlescreen otherwise (same hosts as the Shop).
function OpenLibraryScreen()
    local host = nil
    if dmhub.inGame and not dmhub.isLobbyGame and GameHud.instance and GameHud.instance.shopPanel then
        host = GameHud.instance.shopPanel
    else
        local root = rawget(_G, "CodexTitlescreenRoot")
        if root ~= nil and root.valid then
            host = root
        end
    end

    if host == nil then
        return
    end

    host:AddChild(CreateLibraryScreen{ host = host })
end
