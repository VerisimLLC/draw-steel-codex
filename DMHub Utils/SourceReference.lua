local mod = dmhub.GetModLoading()

--- @class SourceReference
--- @string type
--- @string docid
--- @number page
SourceReference = RegisterGameType("SourceReference")

SourceReference.type = "pdf"
SourceReference.docid = "none"
SourceReference.page = 1

--- The link a "View Source" action opens. Returns nil when no book has been
--- picked, so callers can use `ref:url() ~= nil` as "is this reference set?".
function SourceReference:url()
    if self.docid == nil or self.docid == "none" then
        return nil
    end
    return string.format("%s:%s&page=%d", self.type, self.docid, math.floor(tonumber(self.page) or 1))
end

--- Folds a name or bookmark title down to bare lowercase words. The codex
--- writes ASCII punctuation while the book uses curly quotes and en dashes,
--- so the two only compare equal once both are stripped.
local function normalizeTitle(s)
    if type(s) ~= "string" then return "" end
    s = s:gsub("\226\128\153", "'"):gsub("\226\128\152", "'")
    s = s:gsub("\226\128\148", "-"):gsub("\226\128\147", "-")
    s = s:lower():gsub("[^a-z0-9]+", " ")
    return (s:gsub("^ +", ""):gsub(" +$", ""))
end

--- PDFDocument:Search is an exact byte match and the text layer uses
--- typographic punctuation, so "Hit 'Em Hard!" finds nothing while
--- "Hit <U+2019>Em Hard!" finds the ability. Try the curly forms too.
local function searchVariants(name)
    local out, seen = {}, {}
    local function add(s)
        if s ~= nil and s ~= "" and not seen[s] then
            seen[s] = true
            out[#out + 1] = s
        end
    end
    add(name)
    add((name:gsub("'", "\226\128\153")))
    add((name:gsub("%-", "\226\128\147")))
    add((name:gsub("'", "\226\128\153"):gsub("%-", "\226\128\147")))
    return out
end

--- Converts a 0-based PDF page index into the printed page number stored on
--- SourceReference.page. The viewer resolves page= through pageLabels, so an
--- index would land 15 pages out on a book with front matter. Returns nil for
--- pages with no numeric label (roman-numbered front matter).
local function printedPage(document, page)
    local labels = nil
    pcall(function() labels = document.doc.summary.pageLabels end)
    if labels == nil then
        return page + 1
    end
    return tonumber(labels[page + 1])
end

--- Best guess at the page an entry called `name` is printed on, or nil.
--- Bookmarks win because the PDF outline is authored and points at the real
--- heading; a plain text search is only a fallback, and skips front matter so
--- the table of contents cannot beat the entry itself.
local function findPage(document, name)
    if type(name) ~= "string" or name == "" then return nil end
    local key = normalizeTitle(name)
    if key == "" then return nil end

    local hits = {}
    for _, variant in ipairs(searchVariants(name)) do
        local ok, results = pcall(function() return document.doc:Search(variant) end)
        if ok and type(results) == "table" then
            for _, entry in ipairs(results) do hits[entry.page] = true end
        end
        if next(hits) ~= nil then break end
    end

    local marks = {}
    for _, bookmark in pairs(document.bookmarks or {}) do
        if normalizeTitle(bookmark.title) == key then marks[#marks + 1] = bookmark.page end
    end
    table.sort(marks)
    if #marks > 0 then
        -- several bookmarks can share a title; prefer one the text agrees with
        for _, page in ipairs(marks) do
            if hits[page] or hits[page - 1] or hits[page + 1] then
                return printedPage(document, page)
            end
        end
        return printedPage(document, marks[1])
    end

    local pages = {}
    for page in pairs(hits) do pages[#pages + 1] = page end
    table.sort(pages)
    for _, page in ipairs(pages) do
        local printed = printedPage(document, page)
        if printed ~= nil then return printed end
    end
    return nil
end

function SourceReference:Editor(options)
    local m_object = options.object
    options.object = nil

    local sourcesOptions = {
    }

    local docs = assets.pdfDocumentsTable
    for k,doc in pairs(docs) do
        if not doc.hidden then
            sourcesOptions[#sourcesOptions+1] = {
                id = k,
                text = doc.description,
            }
        end
    end

    table.sort(sourcesOptions, function(a,b) return a.text < b.text end)
    table.insert(sourcesOptions, 1, {
        id = "none",
        text = "(None)",
    })



    local resultPanel
    local children = {
        gui.Panel {
            classes = { "formPanel" },
            gui.Label {
                classes = { "formLabel" },
                text = "Source:",
            },
            gui.Dropdown {
                classes = "formDropdown",
                options = sourcesOptions,
                idChosen = self.docid,
                change = function(element)
                    self.docid = element.idChosen
                    -- picking a book prefills the page; leave it alone if we
                    -- cannot find the entry rather than guessing
                    if self.docid ~= "none" then
                        local document = assets.pdfDocumentsTable[self.docid]
                        if document ~= nil and m_object ~= nil then
                            local name = nil
                            pcall(function() name = m_object.name end)
                            local page = findPage(document, name)
                            if page ~= nil then
                                self.page = page
                            end
                        end
                    end
                    resultPanel:FireEventTree("refreshSource")
                    resultPanel:FireEvent("change")
                end,
            }
        },

        gui.Panel {
            classes = { "formPanel", cond(self.docid == "none", "collapsed") },
            refreshSource = function(element)
                element:SetClass("collapsed", self.docid == "none")
            end,
            gui.Label {
                classes = { "formLabel" },
                text = "Page:",
            },
            gui.Input {
                classes = "formInput",
                text = self.page,
                characterLimit = 4,
                refreshSource = function(element)
                    element.text = self.page
                end,
                change = function(element)
                    local num = tonumber(element.text)
                    if num ~= nil then
                        self.page = num
                    else
                        element.text = self.page
                    end
                    resultPanel:FireEvent("change")
                end,
            },
            gui.Button {
                fontSize = 14,
                width = "auto",
                height = "auto",
                hpad = 10,
                vpad = 4,
                lmargin = 8,
                valign = "center",
                text = "Open",
                click = function(element)
                    local url = self:url()
                    if url ~= nil then
                        dmhub.OpenDocument(url)
                    end
                end,
            },
        }
    }

    local params = {
        width = "auto",
        height = "auto",
        flow = "vertical",
        children = children,
    }

    for k,v in pairs(options or {}) do
        params[k] = v
    end

    resultPanel = gui.Panel(params)
    return resultPanel
end