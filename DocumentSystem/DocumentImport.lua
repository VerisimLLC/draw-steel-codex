local mod = dmhub.GetModLoading()

--Imports documents dragged in from the operating system into the journal:
--  .pdf             a PDF journal entry
--  .md / .markdown  a journal document, converted from standard (CommonMark /
--                   GitHub) Markdown to the journal's own markup
--  .txt             a journal document, as plain text -- unless it looks like
--                   Markdown, then as Markdown
--  .zip             a journal folder mirroring the archive: its documents,
--                   PDFs and pictures, with links between files and images
--                   embedded in documents resolved
--The table and the journal panel hand their drops here (Tabletop.lua,
--Journal.lua); see FILE_DROPS_REFERENCE.md for the whole picture.

--- @class DocumentImport
DocumentImport = {}

--Documents longer than this are split into parts ("Name (2)", ...) that link
--to each other: the journal editor holds CustomDocument.MaxLength characters.
--Bytes are counted, which is never fewer than characters; the margin leaves
--room for the "Continued in" link.
local PART_LIMIT = CustomDocument.MaxLength - 512

--A text file longer than this many parts is refused rather than turned into
--a pile of documents.
local MAX_PARTS = 40

--Links to imported entries name them by id (CustomDocument.ResolveLink).
local JOURNAL_PREFIX = "journal:"

----------------------------------------------------------------------
--Small helpers.

local function Trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function HasExtension(path, list)
    local ext = FileDrops.Extension(path)
    for _, e in ipairs(list) do
        if ext == e then
            return true
        end
    end
    return false
end

local TEXT_EXTENSIONS = {".md", ".markdown", ".txt"}
local MARKDOWN_EXTENSIONS = {".md", ".markdown"}

--- True for a file DocumentImport turns into a journal document.
--- @param path string
--- @return boolean
function DocumentImport.IsTextPath(path)
    return HasExtension(path, TEXT_EXTENSIONS)
end

--The folder new entries go in when the caller names none: the Director's
--Private Documents, or a player's own My Private Documents.
--- @return string
function DocumentImport.DefaultFolder()
    if dmhub.isDM then
        return "private"
    end
    return dmhub.loginUserid
end

--Strips what export tools add to file names: Notion's 32-hex-digit page id.
local function CleanTitle(name)
    name = name:gsub("%s+%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$", "")
    name = Trim(name)
    if name == "" then
        return "Untitled"
    end
    return name
end

--A string safe as a link label: link labels render raw (no markup inside),
--and brackets, braces and angle brackets would break the link or read as
--other markup.
local function SafeLabel(s)
    s = s:gsub("[%[%]{}<>]", ""):gsub("%s+", " ")
    s = Trim(s)
    --[x] / [ ] read as a checkbox and [:Name] as a page embed.
    s = s:gsub("^:+", "")
    if s:match("^[ xX]?$") then
        s = s .. "\u{200b}"
    end
    return s
end

--A link target safe inside (...): the journal's parser ends the target at the
--first ")" and its Lua scanners would read brackets and braces as markup.
local function SafeTarget(s)
    return (s:gsub("[%s%(%)%[%]{}<>\"]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

--A link to a document by its name, for documents not in this import (the
--journal resolves a bare target by document name, so the link works once
--that document is imported too).
local function NameTarget(path)
    return (CleanTitle(FileDrops.BaseName(path)):gsub("[%(%)%[%]{}<>\"]", ""))
end

local function UrlDecode(s)
    return (s:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

--True for a target with a scheme (https:, mailto:, ...). A Windows drive
--letter (C:) is a path.
local function IsExternalUrl(s)
    return s:match("^%a[%w%+%.%-]+:") ~= nil
end

local ENTITIES = {
    amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'", nbsp = "\u{a0}",
    mdash = "\u{2014}", ndash = "\u{2013}", hellip = "\u{2026}", copy = "\u{a9}",
    reg = "\u{ae}", trade = "\u{2122}", lsquo = "\u{2018}", rsquo = "\u{2019}",
    ldquo = "\u{201c}", rdquo = "\u{201d}", times = "\u{d7}", deg = "\u{b0}",
}

--Decodes one "&name;" / "&#123;" / "&#x1F;" entity, or nil when it isn't one.
local function DecodeEntity(entity)
    local name = entity:sub(2, -2)
    if name:sub(1, 1) == "#" then
        local n
        if name:sub(2, 2):lower() == "x" then
            n = tonumber(name:sub(3), 16)
        else
            n = tonumber(name:sub(2))
        end
        if n ~= nil and n > 0 and n < 0x110000 then
            return utf8.char(n)
        end
        return nil
    end
    return ENTITIES[name]
end

--Escapes literal inline text for the journal's markup (see
--MarkdownDocument.EscapeText for the line-start half, DefuseLineStart).
local function EscapeInline(s, inCell)
    s = s:gsub("\\", "\\\\")
    s = s:gsub("[%*%[%]{}`<]", "\\%0")
    s = s:gsub("__+", function(run) return (run:gsub("_", "\\_")) end)
    s = s:gsub("~~+", function(run) return (run:gsub("~", "\\~")) end)
    s = s:gsub(":>", "\\:>")
    if inCell then
        s = s:gsub("|", "\\|")
    end
    return s
end

--Defuses a line of converted text that would start a block construct in the
--journal (heading, bullet, quote, table, rule, ???, :::, + Title, 1.).
local function DefuseLineStart(line)
    if line:match("^[#>|+%-]") or line:match("^%?%?%?") or line:match("^:::") then
        return "\\" .. line
    end
    if line:match("^%d+[%.%)] ") then
        return (line:gsub("^(%d+)([%.%)])", "%1\\%2", 1))
    end
    return line
end

----------------------------------------------------------------------
--Markdown detection for .txt files.

--- True when a plain-text file is really Markdown: several Markdown
--- constructs, or a couple of unmistakable ones (headings, links, fences,
--- tables).
--- @param text string
--- @return boolean
function DocumentImport.LooksLikeMarkdown(text)
    local strong, weak = 0, 0
    local kinds = {}
    local function Hit(kind, isStrong)
        kinds[kind] = true
        if isStrong then
            strong = strong + 1
        else
            weak = weak + 1
        end
    end
    local prev = ""
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        if line:match("^#+ %S") and #line:match("^#+") <= 6 then
            Hit("heading", true)
        elseif line:match("^```") or line:match("^~~~") then
            Hit("fence", true)
        elseif line:match("^%s*[%-%*%+] %S") then
            Hit("bullet", false)
        elseif line:match("^%s*%d+[%.%)] %S") then
            Hit("ordered", false)
        elseif line:match("^> ") then
            Hit("quote", false)
        elseif line:match("^%s*|?%s*:?%-%-%-+:?%s*|") and prev:find("|", 1, true) then
            Hit("table", true)
        end
        if line:match("%[[^%]]+%]%([^%)]+%)") then
            Hit("link", true)
        end
        if line:match("%*%*[^%*%s][^%*]-%*%*") or line:match("__[^_%s][^_]-__") then
            Hit("bold", false)
        end
        if line:match("`[^`]+`") then
            Hit("code", false)
        end
        prev = line
    end
    local nkinds = 0
    for _ in pairs(kinds) do
        nkinds = nkinds + 1
    end
    return strong >= 2 or (nkinds >= 2 and strong + weak >= 4)
end

----------------------------------------------------------------------
--Inline conversion: CommonMark inline syntax -> journal markup.

local function IsSpaceChar(c)
    return c == "" or c:match("%s") ~= nil
end

local function IsPunctChar(c)
    return c ~= "" and c:match("%p") ~= nil
end

--Position of the "]" closing the "[" at open, skipping escapes, nested
--brackets and code spans; nil when there is none.
local function FindCloseBracket(src, open)
    local depth = 0
    local i = open
    while i <= #src do
        local c = src:sub(i, i)
        if c == "\\" then
            i = i + 2
        elseif c == "`" then
            local run = src:match("^`+", i)
            local close = src:find(run, i + #run, true)
            i = (close ~= nil and close + #run) or (i + #run)
        elseif c == "[" then
            depth = depth + 1
            i = i + 1
        elseif c == "]" then
            depth = depth - 1
            if depth == 0 then
                return i
            end
            i = i + 1
        else
            i = i + 1
        end
    end
    return nil
end

--Parses "(dest "title")" starting at the "(" at pos. Returns dest and the
--position after ")", or nil.
local function ParseInlineDestination(src, pos)
    local i = pos + 1
    i = src:find("[^ \t\n]", i) or (#src + 1)
    local dest
    if src:sub(i, i) == "<" then
        local close = src:find(">", i + 1, true)
        if close == nil then
            return nil
        end
        dest = src:sub(i + 1, close - 1)
        i = close + 1
    else
        local depth = 0
        local start = i
        while i <= #src do
            local c = src:sub(i, i)
            if c == "\\" then
                i = i + 2
            elseif c == "(" then
                depth = depth + 1
                i = i + 1
            elseif c == ")" then
                if depth == 0 then
                    break
                end
                depth = depth - 1
                i = i + 1
            elseif c:match("%s") then
                break
            else
                i = i + 1
            end
        end
        dest = src:sub(start, i - 1)
    end
    i = src:find("[^ \t\n]", i) or (#src + 1)
    --an optional title: "..." or '...' or (...)
    local q = src:sub(i, i)
    if q == "\"" or q == "'" or q == "(" then
        local closeChar = (q == "(") and ")" or q
        local close = src:find(closeChar, i + 1, true)
        if close == nil then
            return nil
        end
        i = close + 1
        i = src:find("[^ \t\n]", i) or (#src + 1)
    end
    if src:sub(i, i) ~= ")" then
        --not CommonMark, but common in hand-written notes: a file name with
        --spaces, (My Notes.md). Taken when it names a file we import.
        local loose = src:match("^%(([^%(%)\n]+)%)", pos)
        if loose ~= nil and HasExtension(Trim(loose), {".md", ".markdown", ".txt", ".pdf", ".png", ".jpg", ".jpeg", ".webp", ".mp4", ".webm"}) then
            return Trim(loose), pos + #loose + 2
        end
        return nil
    end
    dest = dest:gsub("\\(%p)", "%1")
    return dest, i + 1
end

local function NormalizeRefLabel(label)
    return Trim(label:lower():gsub("%s+", " "))
end

--Plain text of some inline markup, for link labels and image alt text.
local function PlainText(src)
    local s = src
    s = s:gsub("!%[([^%]]*)%]%b()", "%1")
    s = s:gsub("%[([^%]]*)%]%b()", "%1")
    s = s:gsub("<[^>]*>", "")
    s = s:gsub("&#?%w+;", function(e) return DecodeEntity(e) or e end)
    s = s:gsub("\\(%p)", "%1")
    s = s:gsub("[%*_~`]", "")
    return Trim(s)
end

local HTML_MARKERS = {
    b = "**", strong = "**", i = "*", em = "*", u = "__", ins = "__",
    s = "~~", del = "~~", strike = "~~",
}

local function HtmlAttribute(attrs, name)
    return attrs:match(name .. "%s*=%s*\"([^\"]*)\"") or attrs:match(name .. "%s*=%s*'([^']*)'")
        or attrs:match(name .. "%s*=%s*([^%s>\"']+)")
end

local ConvertInline

--Builds a link to dest with the label from labelSrc; plain text when dest
--does not resolve.
local function LinkMarkup(labelSrc, dest, ctx, opts)
    local label = SafeLabel(PlainText(labelSrc))
    local target = nil
    if dest ~= nil and dest ~= "" then
        target = ctx.Link(dest)
    end
    if label == "" or label == "\u{200b}" then
        if target == nil then
            return ""
        end
        label = SafeLabel(FileDrops.BaseName(UrlDecode(dest)))
    end
    if opts.inCell then
        label = label:gsub("|", "/")
    end
    if target == nil then
        return EscapeInline(label, opts.inCell)
    end
    return string.format("[%s](%s)", label, target)
end

--Converts CommonMark inline text (a paragraph, a heading, a cell...; "\n"
--is a hard line break) to journal markup. Returns a list of pieces: strings
--of markup, and {image = key} where an image goes (rich tags only render on
--a line of their own, so the caller places them).
--opts.inCell: inside a table cell (pipes escaped, no line breaks).
--- @return (string|{image: string})[]
ConvertInline = function(src, ctx, opts)
    opts = opts or {}
    local nodes = {}
    local buf = {}
    local function FlushText()
        if #buf > 0 then
            nodes[#nodes + 1] = {kind = "text", text = table.concat(buf)}
            buf = {}
        end
    end
    local function Markup(text)
        FlushText()
        nodes[#nodes + 1] = {kind = "markup", text = text}
    end
    local function Image(dest, alt)
        local key = ctx.Image(dest, alt)
        if key ~= nil then
            FlushText()
            nodes[#nodes + 1] = {kind = "image", key = key}
        elseif IsExternalUrl(dest) then
            Markup(LinkMarkup(alt ~= "" and alt or "Image", dest, ctx, opts))
        elseif alt ~= "" then
            buf[#buf + 1] = alt
        end
    end

    local n = #src
    local i = 1
    while i <= n do
        local c = src:sub(i, i)
        local prev = i > 1 and src:sub(i - 1, i - 1) or ""
        if c == "\\" then
            local nx = src:sub(i + 1, i + 1)
            if nx == "\n" then
                Markup("\n")
                i = i + 2
            elseif IsPunctChar(nx) then
                buf[#buf + 1] = nx
                i = i + 2
            else
                buf[#buf + 1] = "\\"
                i = i + 1
            end
        elseif c == "\n" then
            Markup(opts.inCell and " " or "\n")
            i = i + 1
        elseif c == "`" then
            local run = src:match("^`+", i)
            local close = nil
            local from = i + #run
            while true do
                local s, e = src:find(run, from, true)
                if s == nil then
                    break
                end
                --the closing run must be exactly as long as the opening one.
                if src:sub(e + 1, e + 1) ~= "`" and src:sub(s - 1, s - 1) ~= "`" then
                    close = s
                    break
                end
                from = e + 1
                while src:sub(from, from) == "`" do
                    from = from + 1
                end
            end
            if close ~= nil then
                local code = src:sub(i + #run, close - 1):gsub("\n", " ")
                if code:match("^ .* $") and code:match("%S") then
                    code = code:sub(2, -2)
                end
                Markup("`" .. EscapeInline(code, opts.inCell) .. "`")
                i = close + #run
            else
                buf[#buf + 1] = run
                i = i + #run
            end
        elseif c == "!" and src:sub(i + 1, i + 2) == "[[" then
            --Obsidian embed: ![[picture.png]] / ![[picture.png|300]]
            local close = src:find("]]", i + 3, true)
            if close ~= nil then
                local inner = src:sub(i + 3, close - 1)
                local page = Trim(inner:match("^([^|#]*)") or inner)
                local key = page ~= "" and ctx.WikiImage(page) or nil
                local link = (key == nil and page ~= "") and ctx.Wiki(page) or nil
                if key ~= nil then
                    FlushText()
                    nodes[#nodes + 1] = {kind = "image", key = key}
                elseif link ~= nil then
                    --an embedded note: a link to it.
                    Markup(string.format("[%s](%s)", SafeLabel(FileDrops.BaseName(page)), link))
                else
                    buf[#buf + 1] = FileDrops.BaseName(page)
                end
                i = close + 2
            else
                buf[#buf + 1] = c
                i = i + 1
            end
        elseif c == "[" and src:sub(i + 1, i + 1) == "[" then
            --Obsidian wiki link: [[Page]] / [[Page|shown text]] / [[Page#Heading]]
            local close = src:find("]]", i + 2, true)
            if close ~= nil then
                local inner = src:sub(i + 2, close - 1)
                local target, alias = inner:match("^([^|]*)|(.*)$")
                if target == nil then
                    target = inner
                end
                local page = Trim(target:match("^([^#]*)") or target)
                local label = alias or (page ~= "" and FileDrops.BaseName(page)) or target
                local link = nil
                if page ~= "" then
                    link = ctx.Wiki(page)
                end
                if link ~= nil then
                    Markup(string.format("[%s](%s)", SafeLabel(label), link))
                else
                    buf[#buf + 1] = label
                end
                i = close + 2
            else
                buf[#buf + 1] = c
                i = i + 1
            end
        elseif c == "[" or (c == "!" and src:sub(i + 1, i + 1) == "[") then
            local isImage = c == "!"
            local open = isImage and i + 1 or i
            local close = FindCloseBracket(src, open)
            local handled = false
            if close ~= nil then
                local labelSrc = src:sub(open + 1, close - 1)
                local dest, after = nil, nil
                if src:sub(close + 1, close + 1) == "(" then
                    dest, after = ParseInlineDestination(src, close + 1)
                end
                if dest == nil then
                    --reference links: [text][ref], [text][], [text]
                    local refLabel = nil
                    local refEnd = close + 1
                    if src:sub(close + 1, close + 1) == "[" then
                        local rclose = src:find("]", close + 2, true)
                        if rclose ~= nil then
                            refLabel = src:sub(close + 2, rclose - 1)
                            refEnd = rclose + 1
                        end
                    end
                    if refLabel == nil or refLabel == "" then
                        refLabel = labelSrc
                    end
                    local ref = ctx.refs[NormalizeRefLabel(refLabel)]
                    if ref ~= nil and not labelSrc:match("^%^") then
                        dest, after = ref, refEnd
                    end
                end
                if dest ~= nil then
                    if isImage then
                        Image(dest, PlainText(labelSrc))
                    else
                        --a linked picture (a badge) keeps its alt text as the label.
                        Markup(LinkMarkup(labelSrc, dest, ctx, opts))
                    end
                    i = after or (close + 1)
                    handled = true
                end
            end
            if not handled then
                buf[#buf + 1] = c
                i = i + 1
            end
        elseif c == "<" then
            local comment = src:match("^<!%-%-.-%-%->", i)
            local autolink = src:match("^<(%a[%w%+%.%-]+:[^%s<>]*)>", i)
            local email = src:match("^<([%w%._%%%+%-]+@[%w%.%-]+%.%a+)>", i)
            local closing, tagName, attrs = src:match("^<(/?)(%a[%w]*)([^<>]*)>", i)
            if comment ~= nil then
                FlushText()
                i = i + #comment
            elseif autolink ~= nil then
                Markup(LinkMarkup(autolink, autolink, ctx, opts))
                i = i + #autolink + 2
            elseif email ~= nil then
                Markup(LinkMarkup(email, "mailto:" .. email, ctx, opts))
                i = i + #email + 2
            elseif tagName ~= nil then
                local whole = src:match("^<[^<>]*>", i)
                local name = tagName:lower()
                if name == "br" then
                    Markup(opts.inCell and " " or "\n")
                elseif name == "img" and closing == "" then
                    local imgSrc = HtmlAttribute(attrs, "src")
                    if imgSrc ~= nil then
                        Image(imgSrc, HtmlAttribute(attrs, "alt") or "")
                    end
                elseif name == "a" and closing == "" then
                    local href = HtmlAttribute(attrs, "href")
                    local s, e = src:lower():find("</a%s*>", i + #whole)
                    if href ~= nil and s ~= nil then
                        Markup(LinkMarkup(src:sub(i + #whole, s - 1), href, ctx, opts))
                        whole = src:sub(i, e)
                    end
                elseif HTML_MARKERS[name] ~= nil then
                    Markup(HTML_MARKERS[name])
                elseif name == "sup" or name == "sub" then
                    Markup("<" .. closing .. name .. ">")
                end
                --any other tag (div, span, p, ...) is dropped; its text stays.
                i = i + #whole
            else
                buf[#buf + 1] = c
                i = i + 1
            end
        elseif c == "*" or c == "_" or c == "~" then
            local run = src:match("^" .. (c == "*" and "%*" or c) .. "+", i)
            local nextc = src:sub(i + #run, i + #run)
            if c == "~" and #run < 2 then
                buf[#buf + 1] = run
            else
                local left = not IsSpaceChar(nextc) and (not IsPunctChar(nextc) or IsSpaceChar(prev) or IsPunctChar(prev))
                local right = not IsSpaceChar(prev) and (not IsPunctChar(prev) or IsSpaceChar(nextc) or IsPunctChar(nextc))
                local canOpen, canClose = left, right
                if c == "_" then
                    canOpen = left and (not right or IsPunctChar(prev))
                    canClose = right and (not left or IsPunctChar(nextc))
                end
                FlushText()
                nodes[#nodes + 1] = {kind = "delim", char = c, count = #run,
                    canOpen = canOpen, canClose = canClose, before = "", after = ""}
            end
            i = i + #run
        elseif c == "&" then
            local entity = src:match("^&#?%w+;", i)
            local decoded = entity ~= nil and DecodeEntity(entity) or nil
            if decoded ~= nil then
                buf[#buf + 1] = decoded
                i = i + #entity
            else
                buf[#buf + 1] = c
                i = i + 1
            end
        elseif (c == "h" or c == "H") and (prev == "" or IsSpaceChar(prev) or prev == "(") and src:match("^[hH][tT][tT][pP][sS]?://", i) then
            --a bare web address (GitHub autolink).
            local url = src:match("^%S+", i)
            url = url:gsub("[<>].*$", "")
            url = url:gsub("[%.,;:!%?'\"]+$", "")
            if url:sub(-1) == ")" and not url:find("(", 1, true) then
                url = url:sub(1, -2)
            end
            Markup(string.format("[%s](%s)", SafeLabel(url), SafeTarget(url)))
            i = i + #url
        else
            local run = src:match("^[^\\\n`!%[<%*_~&hH]+", i) or c
            buf[#buf + 1] = run
            i = i + #run
        end
    end
    FlushText()

    --emphasis: pair each closing delimiter run with the nearest earlier
    --opening run of the same character (a simplified CommonMark pass).
    --Unpaired delimiters are literal text.
    for ci = 1, #nodes do
        local closer = nodes[ci]
        if closer.kind == "delim" and closer.canClose then
            while closer.count > 0 do
                local opener = nil
                for oi = ci - 1, 1, -1 do
                    local o = nodes[oi]
                    if o.kind == "delim" and o.char == closer.char and o.canOpen and o.count > 0 then
                        opener = o
                        break
                    end
                end
                if opener == nil then
                    break
                end
                local use, mark
                if closer.char == "~" then
                    if opener.count < 2 or closer.count < 2 then
                        break
                    end
                    use, mark = 2, "~~"
                elseif opener.count >= 2 and closer.count >= 2 then
                    use, mark = 2, "**"
                else
                    use, mark = 1, "*"
                end
                opener.count = opener.count - use
                closer.count = closer.count - use
                opener.after = mark .. opener.after
                closer.before = closer.before .. mark
                --delimiters between the pair can no longer pair across it.
                local between = false
                for k = 1, ci - 1 do
                    if nodes[k] == opener then
                        between = true
                    elseif between and nodes[k].kind == "delim" then
                        nodes[k].canOpen = false
                    end
                end
            end
        end
    end

    local pieces = {}
    local out = {}
    for _, node in ipairs(nodes) do
        if node.kind == "text" then
            out[#out + 1] = EscapeInline(node.text, opts.inCell)
        elseif node.kind == "markup" then
            out[#out + 1] = node.text
        elseif node.kind == "delim" then
            local literal = string.rep("\\" .. node.char, node.count)
            out[#out + 1] = node.before .. literal .. node.after
        elseif node.kind == "image" then
            pieces[#pieces + 1] = table.concat(out)
            out = {}
            pieces[#pieces + 1] = {image = node.key}
        end
    end
    pieces[#pieces + 1] = table.concat(out)
    return pieces
end

----------------------------------------------------------------------
--Block conversion: CommonMark blocks -> journal lines.

local function ExpandTabs(line)
    if not line:find("\t", 1, true) then
        return line
    end
    local out = {}
    local col = 0
    for ch in line:gmatch(".") do
        if ch == "\t" then
            local spaces = 4 - (col % 4)
            out[#out + 1] = string.rep(" ", spaces)
            col = col + spaces
        else
            out[#out + 1] = ch
            col = col + 1
        end
    end
    return table.concat(out)
end

local function ListMarker(line)
    local indent, marker, spaces, rest = line:match("^( *)([%-%*%+])( +)(.*)$")
    if indent == nil then
        indent, marker, rest = line:match("^( *)([%-%*%+])()$")
        if indent ~= nil then
            spaces, rest = " ", ""
        end
    end
    if indent ~= nil then
        return {indent = #indent, content = #indent + 1 + math.min(#spaces, 4), text = rest, ordered = false}
    end
    local num, delim
    indent, num, delim, spaces, rest = line:match("^( *)(%d+)([%.%)])( +)(.*)$")
    if indent ~= nil and #num <= 9 then
        return {indent = #indent, content = #indent + #num + 1 + math.min(#spaces, 4), text = rest, ordered = true, number = num}
    end
    return nil
end

local function IsThematicBreak(line)
    local s = line:gsub("%s", "")
    return #s >= 3 and (s:match("^%-+$") or s:match("^%*+$") or s:match("^_+$")) and line:match("^ ? ? ?[%-%*_]") ~= nil
end

local function IsFence(line)
    local indent, fence, info = line:match("^( ? ? ?)(```+)(.*)$")
    if fence == nil then
        indent, fence, info = line:match("^( ? ? ?)(~~~+)(.*)$")
    end
    if fence ~= nil and fence:sub(1, 1) == "`" and info:find("`", 1, true) then
        return nil
    end
    return fence
end

local function IsTableDelimiter(line)
    local cells = Trim(line)
    if not cells:find("-", 1, true) then
        return false
    end
    cells = cells:gsub("^|", ""):gsub("|$", "")
    for cell in (cells .. "|"):gmatch("([^|]*)|") do
        if not Trim(cell):match("^:?%-+:?$") then
            return false
        end
    end
    return true
end

local function SplitTableRow(line)
    local s = Trim(line)
    s = s:gsub("^|", "")
    if s:sub(-1) == "|" and s:sub(-2, -2) ~= "\\" then
        s = s:sub(1, -2)
    end
    local cells = {}
    local current = {}
    local i = 1
    local inCode = false
    while i <= #s do
        local c = s:sub(i, i)
        if c == "\\" and s:sub(i + 1, i + 1) == "|" then
            current[#current + 1] = "|"
            i = i + 2
        else
            if c == "`" then
                inCode = not inCode
            end
            if c == "|" and not inCode then
                cells[#cells + 1] = Trim(table.concat(current))
                current = {}
            else
                current[#current + 1] = c
            end
            i = i + 1
        end
    end
    cells[#cells + 1] = Trim(table.concat(current))
    return cells
end

local function StartsBlock(line)
    return line:match("^ ? ? ?#+ ") ~= nil or line:match("^ ? ? ?#+$") ~= nil or IsFence(line) ~= nil
        or line:match("^ ? ? ?>") ~= nil or IsThematicBreak(line) or ListMarker(line) ~= nil
end

local ConvertBlocks

--Converts Markdown source lines to journal lines (appended to out).
ConvertBlocks = function(lines, ctx, out, opts)
    opts = opts or {}
    local deferredImages = nil
    local function Blank()
        if #out > 0 and out[#out] ~= "" then
            out[#out + 1] = ""
        end
    end
    local function ImageLine(key)
        if opts.deferImages then
            deferredImages = deferredImages or {}
            deferredImages[#deferredImages + 1] = "[[" .. key .. "]]"
        else
            out[#out + 1] = "[[" .. key .. "]]"
        end
    end
    --Emits inline pieces as lines: first gets prefix, later lines contPrefix;
    --images go on lines of their own (or after the block when held).
    local function EmitPieces(pieces, prefix, contPrefix, holdImages)
        local held = {}
        local first = true
        local function Line(text)
            text = Trim(text)
            if text == "" then
                return
            end
            local p = first and prefix or contPrefix
            first = false
            if p == "" then
                text = DefuseLineStart(text)
            end
            out[#out + 1] = p .. text
        end
        for _, piece in ipairs(pieces) do
            if type(piece) == "table" then
                if holdImages then
                    held[#held + 1] = piece.image
                else
                    ImageLine(piece.image)
                    first = false
                end
            else
                for segment in (piece .. "\n"):gmatch("(.-)\n") do
                    Line(segment)
                end
            end
        end
        if first and prefix ~= "" and not holdImages then
            --an empty item or heading still gets its marker.
            out[#out + 1] = Trim(prefix)
        end
        for _, key in ipairs(held) do
            ImageLine(key)
        end
    end

    local para = nil
    local function FlushParagraph()
        if para == nil then
            return
        end
        local text = {}
        for k, line in ipairs(para) do
            local hard = line:match("  +$") ~= nil or (line:match("\\$") ~= nil and line:match("\\\\$") == nil)
            line = Trim(line)
            if hard and k < #para then
                line = line:gsub("\\$", "")
                text[#text + 1] = line .. "\n"
            elseif k < #para then
                text[#text + 1] = line .. " "
            else
                text[#text + 1] = line
            end
        end
        para = nil
        Blank()
        EmitPieces(ConvertInline(table.concat(text), ctx), "", "", false)
    end

    local listStack = {}
    local i = 1
    local n = #lines
    while i <= n do
        local line = lines[i]
        local trimmed = Trim(line)

        if trimmed == "" then
            FlushParagraph()
            i = i + 1
        elseif para == nil and line:match("^    ") and #listStack == 0 then
            --indented code block
            Blank()
            while i <= n and (lines[i]:match("^    ") or (Trim(lines[i]) == "" and lines[i + 1] ~= nil and lines[i + 1]:match("^    "))) do
                local code = lines[i]:sub(5)
                if Trim(code) == "" then
                    out[#out + 1] = ""
                else
                    out[#out + 1] = "`" .. EscapeInline(code) .. "`"
                end
                i = i + 1
            end
        elseif IsFence(line) ~= nil then
            FlushParagraph()
            listStack = {}
            local fence = assert(IsFence(line))
            local indent = #line:match("^( *)")
            Blank()
            i = i + 1
            while i <= n do
                local closeFence = IsFence(lines[i])
                if closeFence ~= nil and closeFence:sub(1, 1) == fence:sub(1, 1) and #closeFence >= #fence and Trim(lines[i]) == closeFence then
                    i = i + 1
                    break
                end
                local code = lines[i]
                if indent > 0 then
                    code = code:gsub("^" .. string.rep(" ?", indent), "")
                end
                if Trim(code) == "" then
                    out[#out + 1] = ""
                else
                    out[#out + 1] = "`" .. EscapeInline(code) .. "`"
                end
                i = i + 1
            end
        elseif trimmed:match("^<!%-%-") then
            --an HTML comment, possibly over several lines.
            FlushParagraph()
            while i <= n and not lines[i]:find("-->", 1, true) do
                i = i + 1
            end
            i = i + 1
        elseif trimmed:match("^\\page") or trimmed:match("^\\column") or trimmed:match("^{{") or trimmed == "}}" then
            --Homebrewery page/column breaks and {{block}} fences: no meaning here.
            FlushParagraph()
            i = i + 1
        elseif para ~= nil and #listStack == 0 and (trimmed:match("^=+$") or trimmed:match("^%-+$")) and line:match("^ ? ? ?[=%-]") then
            --setext heading: the paragraph above is the heading text.
            local level = trimmed:sub(1, 1) == "=" and 1 or 2
            local text = table.concat(para, " ")
            para = nil
            Blank()
            EmitPieces(ConvertInline(Trim(text), ctx), string.rep("#", level) .. " ", "", true)
            i = i + 1
        elseif line:match("^ ? ? ?#+ ") or line:match("^ ? ? ?#+$") then
            FlushParagraph()
            listStack = {}
            local hashes, text = line:match("^ ? ? ?(#+)%s*(.-)%s*$")
            if #hashes <= 6 then
                text = text:gsub("%s+#+$", ""):gsub("^#+$", "")
                Blank()
                EmitPieces(ConvertInline(text, ctx), string.rep("#", math.min(#hashes, 5)) .. " ", "", true)
            else
                para = {line}
            end
            i = i + 1
        elseif IsThematicBreak(line) then
            FlushParagraph()
            listStack = {}
            Blank()
            out[#out + 1] = "---"
            i = i + 1
        elseif line:match("^ ? ? ?>") then
            FlushParagraph()
            listStack = {}
            local inner = {}
            while i <= n and lines[i]:match("^ ? ? ?>") do
                local content = lines[i]:gsub("^ ? ? ?> ?", "")
                --nested quotes flatten into one.
                while content:match("^ ? ? ?>") do
                    content = content:gsub("^ ? ? ?> ?", "")
                end
                inner[#inner + 1] = content
                i = i + 1
            end
            --GitHub / Obsidian callouts: > [!NOTE] Title
            if inner[1] ~= nil then
                local kind, title = inner[1]:match("^%s*%[!(%w+)%][%+%-]?%s*(.*)$")
                if kind ~= nil then
                    local label = kind:sub(1, 1):upper() .. kind:sub(2):lower()
                    inner[1] = "**" .. label .. (title ~= "" and (":** " .. title) or "**")
                    --the title is its own line, not the start of the body.
                    table.insert(inner, 2, "")
                end
            end
            local quoted = {}
            local held = ConvertBlocks(inner, ctx, quoted, {deferImages = true})
            Blank()
            for _, q in ipairs(quoted) do
                if q == "" then
                    out[#out + 1] = ">"
                else
                    out[#out + 1] = "> " .. q
                end
            end
            for _, imageLine in ipairs(held or {}) do
                out[#out + 1] = imageLine
            end
        elseif line:find("|", 1, true) and lines[i + 1] ~= nil and IsTableDelimiter(lines[i + 1]) and #listStack == 0 then
            FlushParagraph()
            local header = SplitTableRow(line)
            local aligns = SplitTableRow(lines[i + 1])
            local rows = {header}
            i = i + 2
            while i <= n and Trim(lines[i]) ~= "" and lines[i]:find("|", 1, true) and not StartsBlock(lines[i]) do
                rows[#rows + 1] = SplitTableRow(lines[i])
                i = i + 1
            end
            Blank()
            local heldImages = {}
            local cols = #header
            for r, row in ipairs(rows) do
                local cells = {}
                for col = 1, cols do
                    local pieces = ConvertInline(row[col] or "", ctx, {inCell = true})
                    local text = {}
                    for _, piece in ipairs(pieces) do
                        if type(piece) == "table" then
                            heldImages[#heldImages + 1] = piece.image
                        else
                            text[#text + 1] = piece
                        end
                    end
                    local cell = Trim(table.concat(text))
                    if cell == "" then
                        cell = " "
                    end
                    cells[#cells + 1] = cell
                end
                out[#out + 1] = "|" .. table.concat(cells, "|") .. "|"
                if r == 1 then
                    local sep = {}
                    for col = 1, cols do
                        local a = Trim(aligns[col] or "")
                        local l, rr = a:sub(1, 1) == ":", a:sub(-1) == ":"
                        sep[#sep + 1] = (l and ":" or "") .. "---" .. (rr and ":" or "")
                    end
                    out[#out + 1] = "|" .. table.concat(sep, "|") .. "|"
                end
            end
            for _, key in ipairs(heldImages) do
                ImageLine(key)
            end
        elseif ListMarker(line) ~= nil and (para == nil or (ListMarker(line).text ~= "" and (not ListMarker(line).ordered or ListMarker(line).number == "1"))) then
            FlushParagraph()
            local item = assert(ListMarker(line))
            --nesting: the deepest open item whose content this line is
            --indented under.
            local depth = 0
            for d = #listStack, 1, -1 do
                if item.indent >= listStack[d].content then
                    depth = d
                    break
                end
            end
            for d = #listStack, depth + 1, -1 do
                listStack[d] = nil
            end
            listStack[depth + 1] = item
            if depth == 0 and (out[#out] ~= nil and out[#out] ~= "" and not out[#out]:match("^[%-%d%[ ]")) then
                Blank()
            end
            --the item's own continuation lines.
            local text = {item.text}
            i = i + 1
            while i <= n do
                local nxt = lines[i]
                if Trim(nxt) == "" then
                    --a blank line ends the item unless indented content follows.
                    local after = lines[i + 1]
                    if after ~= nil and Trim(after) ~= "" and #after:match("^( *)") >= item.content and ListMarker(after) == nil then
                        text[#text + 1] = "\n"
                        i = i + 1
                    else
                        break
                    end
                elseif ListMarker(nxt) ~= nil or (StartsBlock(nxt) and #nxt:match("^( *)") < item.content) then
                    break
                elseif IsFence(nxt) ~= nil or nxt:match("^ *>") then
                    break
                else
                    text[#text + 1] = Trim(nxt)
                    i = i + 1
                end
            end
            local body = table.concat(text, " "):gsub(" ?\n ?", "\n")
            local prefix
            local task, rest = body:match("^%[([ xX])%]%s+(.*)$")
            local indent = string.rep(" ", math.min(depth, 6))
            if task ~= nil then
                body = rest
                prefix = string.rep("  ", depth) .. "[" .. task .. "] "
            elseif depth == 0 then
                prefix = item.ordered and ((tonumber(item.number) or 1) .. ". ") or "- "
            elseif item.ordered then
                prefix = indent .. "* " .. (tonumber(item.number) or 1) .. "\\. "
            else
                prefix = indent .. "* "
            end
            EmitPieces(ConvertInline(body, ctx), prefix, string.rep("  ", depth + 1), false)
        else
            if para == nil then
                listStack = {}
                para = {}
            end
            para[#para + 1] = line
            i = i + 1
        end
    end
    FlushParagraph()
    return deferredImages
end

--Pulls link reference definitions ([id]: url) out of the lines (outside
--code fences), returning the remaining lines and the definitions.
local function ExtractReferences(lines)
    local refs = {}
    local kept = {}
    local inFence = nil
    for _, line in ipairs(lines) do
        local fence = IsFence(line)
        if inFence ~= nil then
            if fence ~= nil and fence:sub(1, 1) == inFence then
                inFence = nil
            end
            kept[#kept + 1] = line
        elseif fence ~= nil then
            inFence = fence:sub(1, 1)
            kept[#kept + 1] = line
        else
            local label, dest = line:match("^ ? ? ?%[([^%]]+)%]:%s*<?([^%s>]+)>?")
            if label ~= nil and not label:match("^%^") then
                local key = NormalizeRefLabel(label)
                if refs[key] == nil then
                    refs[key] = dest
                end
            else
                kept[#kept + 1] = line
            end
        end
    end
    return kept, refs
end

--- Converts Markdown to journal markup. ctx supplies resolution:
---   ctx.doc        the MarkdownDocument images are annotated on
---   ctx.Link(dest)  -> link target (e.g. "journal:<id>") or nil
---   ctx.Image(dest, alt) -> rich tag key or nil
---   ctx.Wiki(page) / ctx.WikiImage(page) -> the same for [[Page]] links
--- Returns the converted text and the title from YAML front matter, if any.
--- @param text string
--- @param ctx table
--- @return string text, string|nil title
function DocumentImport.ConvertMarkdown(text, ctx)
    text = text:gsub("^\u{feff}", ""):gsub("\r\n?", "\n")
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = ExpandTabs(line)
    end

    --YAML front matter (Obsidian, Jekyll, Hugo): dropped, but its title kept.
    local title = nil
    if lines[1] ~= nil and Trim(lines[1]) == "---" then
        for k = 2, math.min(#lines, 200) do
            local t = Trim(lines[k])
            if t == "---" or t == "..." then
                for j = 2, k - 1 do
                    local v = lines[j]:match("^title:%s*(.-)%s*$")
                    if v ~= nil and v ~= "" then
                        title = v:gsub("^[\"'](.*)[\"']$", "%1")
                    end
                end
                local rest = {}
                for j = k + 1, #lines do
                    rest[#rest + 1] = lines[j]
                end
                lines = rest
                break
            end
        end
    end

    local refs
    lines, refs = ExtractReferences(lines)
    ctx.refs = refs

    local out = {}
    ConvertBlocks(lines, ctx, out)
    while out[#out] == "" do
        out[#out] = nil
    end
    while out[1] == "" do
        table.remove(out, 1)
    end
    return table.concat(out, "\n"), title
end

--- Converts plain text to journal markup: everything shows as written.
--- @param text string
--- @return string
function DocumentImport.ConvertPlainText(text)
    text = text:gsub("^\u{feff}", ""):gsub("\r\n?", "\n")
    return MarkdownDocument.EscapeText(text)
end

----------------------------------------------------------------------
--Creating journal entries.

--Splits text at blank lines (else line breaks, else spaces) into parts of at
--most limit bytes.
local function SplitParts(text, limit)
    local parts = {}
    while #text > limit do
        local window = text:sub(1, limit)
        local cut = nil
        for _, pattern in ipairs({"()\n\n", "()\n", "() "}) do
            local last = nil
            for pos in window:gmatch(pattern) do
                last = pos
            end
            if last ~= nil and last > limit / 4 then
                cut = last
                break
            end
        end
        cut = cut or limit
        --never inside a UTF-8 sequence.
        while cut > 1 do
            local b = text:byte(cut + 1) or 0
            if b < 0x80 or b >= 0xC0 then
                break
            end
            cut = cut - 1
        end
        parts[#parts + 1] = (text:sub(1, cut):gsub("%s+$", ""))
        text = (text:sub(cut + 1):gsub("^\n+", ""))
    end
    parts[#parts + 1] = text
    return parts
end

--Uploads a converted document as one journal document, or several linked
--parts when it is too long for one. annotations come from the conversion.
--Returns false when it was too long even for that.
local function UploadDocument(info)
    local parts = SplitParts(info.text, PART_LIMIT)
    if #parts > MAX_PARTS then
        return false
    end
    local ids = {info.id}
    for k = 2, #parts do
        ids[k] = dmhub.GenerateGuid()
    end
    for k, partText in ipairs(parts) do
        local name = info.title
        if k > 1 then
            name = string.format("%s (%d)", info.title, k)
        end
        if k < #parts then
            partText = string.format("%s\n\n[Continued in %s](%s%s)", partText,
                SafeLabel(string.format("%s (%d)", info.title, k + 1)), JOURNAL_PREFIX, ids[k + 1])
        end
        local annotations = {}
        for key, annotation in pairs(info.annotations or {}) do
            if string.find(partText, "[[" .. key .. "]]", 1, true) ~= nil then
                annotations[key] = annotation
            end
        end
        local doc = MarkdownDocument.new{
            id = ids[k],
            description = name,
            parentFolder = info.parentFolder,
            annotations = annotations,
            ord = info.ord or 0,
        }
        if not dmhub.isDM then
            doc.ownerid = dmhub.loginUserid
        end
        doc:SetTextContent(partText)
        doc:Upload()
    end
    return true
end

--Calls fn(entryid) once the entry has reached the journal (an upload's
--record arrives a moment after its callback), giving up after timeout
--seconds (then gaveUp, if given, is called instead).
local function WhenInJournal(entryid, timeout, fn, gaveUp)
    if fn == nil then
        return
    end
    dmhub.Coroutine(function()
        local deadline = dmhub.Time() + timeout
        while CustomDocument.FindJournalEntry(entryid) == nil do
            if mod.unloaded then
                return
            end
            if dmhub.Time() > deadline then
                if gaveUp ~= nil then
                    gaveUp()
                end
                return
            end
            coroutine.yield(0.1)
        end
        if not mod.unloaded then
            fn(entryid)
        end
    end)
end

local function ShowError(title, message)
    gui.ModalMessage{
        title = title,
        message = message,
    }
end

--Uploads a picture or video file with a chosen id. As a journal entry when
--parentFolder is given, else as a plain asset (an image embedded in a
--document needs no entry of its own).
--done(errorMessage|nil) is called exactly once. Returns the asset id, or nil
--when the upload could not start (done has then been called).
local function UploadMedia(path, id, parentFolder, done)
    local called = false
    local function Done(message)
        if not called then
            called = true
            done(message)
        end
    end
    local ok, result = pcall(function()
        return assets:UploadImageAsset{
            guid = id,
            path = path,
            description = CleanTitle(FileDrops.BaseName(path)),
            imageType = parentFolder ~= nil and "document" or nil,
            parentFolder = parentFolder,
            error = function(message)
                Done(message)
            end,
            upload = function()
                Done(nil)
            end,
        }
    end)
    if not ok or result == nil then
        Done(ok and "could not be read" or tostring(result))
        return nil
    end
    return result
end

--A rich tag for an image or video, added to the document's annotations.
local function MediaAnnotation(doc, assetid, path, alt)
    local tag
    if FileDrops.IsVideo(path) then
        tag = RichVideo.new{image = assetid}
    else
        tag = RichImage.new{image = assetid}
    end
    local name = alt
    if name == nil or Trim(name) == "" then
        name = CleanTitle(FileDrops.BaseName(path))
    end
    return doc:AddRichTagAnnotation(tag, name)
end

----------------------------------------------------------------------
--Single files.

--A progress row in the network status list while uploads run.
local function StartOperation(description)
    local operation = dmhub.CreateNetworkOperation()
    operation.description = description
    operation.status = "Uploading..."
    operation.progress = 0.0
    operation:Update()
    return operation
end

--- @class DocumentImportWatch
--- @field progress fun(fraction: number) how far the upload has got (0 to 1)
--- @field failed fun() the upload failed or never reached the journal

--watch (optional): the caller shows the upload itself (the table's placeholder),
--so there is no app-locking progress dialog.
--- @param watch nil|DocumentImportWatch
local function ImportPDF(path, parentFolder, ready, watch)
    local operation = nil
    if watch == nil then
        operation = StartOperation("Uploading Document")
    end
    local function SetProgress(f)
        if operation ~= nil then
            operation.progress = f
            operation:Update()
        end
        if watch ~= nil then
            watch.progress(f)
        end
    end
    local name = FileDrops.BaseName(path)
    assets.UploadPDFDocumentAsset{
        path = path,
        parentFolder = parentFolder,
        description = CleanTitle(name),
        progress = function(f)
            SetProgress(math.min(0.99, f))
        end,
        upload = function(guid)
            SetProgress(1)
            WhenInJournal(guid, 60, ready, watch and watch.failed)
        end,
        error = function(message)
            SetProgress(1)
            if watch ~= nil then
                watch.failed()
            end
            ShowError("Could not import " .. name, message)
        end,
    }
end

local function ImportTextFile(path, parentFolder, ready)
    local name = FileDrops.BaseName(path)
    local readError = nil
    local text = dmhub.ReadTextFile(path, function(message)
        readError = message
    end)
    if text == nil then
        ShowError("Could not import " .. name, readError or "The file could not be read.")
        return
    end

    local id = dmhub.GenerateGuid()
    local doc = MarkdownDocument.new{id = id, content = "", annotations = {}}
    local converted, title
    if HasExtension(path, MARKDOWN_EXTENSIONS) or DocumentImport.LooksLikeMarkdown(text) then
        --pictures next to the file on disk are embedded; links to other
        --documents become links by name (they work once those are imported).
        local dir = path:match("^(.*)[/\\][^/\\]*$") or "."
        local uploaded = {}
        local ctx = {
            doc = doc,
            Link = function(dest)
                if IsExternalUrl(dest) then
                    return SafeTarget(dest)
                end
                local file = UrlDecode(dest:gsub("[#%?].*$", ""))
                if file ~= "" and (DocumentImport.IsTextPath(file) or FileDrops.Extension(file) == "") then
                    return NameTarget(file)
                end
                return nil
            end,
            Image = function(dest, alt)
                if IsExternalUrl(dest) or dest:match("^data:") then
                    return nil
                end
                local file = UrlDecode(dest:gsub("[#%?].*$", ""))
                local full = file
                if not file:match("^%a:[/\\]") and not file:match("^[/\\]") then
                    full = dir .. "/" .. file
                end
                if not HasExtension(full, FileDrops.MEDIA_EXTENSIONS) then
                    return nil
                end
                local assetid = uploaded[full]
                if assetid == nil then
                    --a picture that isn't there stays as its alt text.
                    assetid = UploadMedia(full, dmhub.GenerateGuid(), nil, function() end)
                    if assetid == nil then
                        return nil
                    end
                    uploaded[full] = assetid
                end
                return MediaAnnotation(doc, assetid, full, alt)
            end,
            Wiki = function(page)
                return NameTarget(page)
            end,
        }
        ctx.WikiImage = function(page)
            if HasExtension(page, FileDrops.MEDIA_EXTENSIONS) then
                return ctx.Image(page, nil)
            end
            return nil
        end
        converted, title = DocumentImport.ConvertMarkdown(text, ctx)
    else
        converted = DocumentImport.ConvertPlainText(text)
    end

    local ok = UploadDocument{
        id = id,
        title = CleanTitle(title or name),
        parentFolder = parentFolder,
        text = converted,
        annotations = doc.annotations,
    }
    if not ok then
        ShowError("Could not import " .. name, "The file is too long to import.")
        return
    end
    WhenInJournal(id, 30, ready)
end

----------------------------------------------------------------------
--Zip archives.

local function NormalizePath(path)
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            parts[#parts] = nil
        elseif part ~= "." then
            parts[#parts + 1] = part
        end
    end
    return table.concat(parts, "/")
end

local function DirOf(name)
    return name:match("^(.*)/[^/]*$") or ""
end

--Imports the unpacked files of an archive (files: {path, name}[]) into a
--folder named after it.
local function ImportFileSet(files, archiveName, parentFolder, ready)
    --drop hidden files and the clutter Windows and macOS add.
    local entries = {}
    for _, f in ipairs(files) do
        local name = f.name:gsub("\\", "/")
        local hidden = false
        for part in name:gmatch("[^/]+") do
            if part:sub(1, 1) == "." then
                hidden = true
            end
        end
        local base = (name:match("([^/]+)$") or ""):lower()
        if not hidden and base ~= "thumbs.db" and base ~= "desktop.ini" then
            entries[#entries + 1] = {path = f.path, name = name}
        end
    end

    --an archive of one folder: that folder is the archive.
    local commonRoot = entries[1] ~= nil and entries[1].name:match("^([^/]+)/") or nil
    if commonRoot ~= nil then
        for _, e in ipairs(entries) do
            if e.name:sub(1, #commonRoot + 1) ~= commonRoot .. "/" then
                commonRoot = nil
                break
            end
        end
    end
    if commonRoot ~= nil then
        for _, e in ipairs(entries) do
            e.name = e.name:sub(#commonRoot + 2)
        end
    end

    --what each file becomes, and its id ahead of time so links resolve
    --before anything is uploaded.
    local byPath = {}
    local byBase = {}
    local docs, pdfs, media = {}, {}, {}
    local skipped = 0
    for _, e in ipairs(entries) do
        if DocumentImport.IsTextPath(e.name) then
            e.kind = "doc"
            docs[#docs + 1] = e
        elseif FileDrops.Extension(e.name) == ".pdf" then
            e.kind = "pdf"
            pdfs[#pdfs + 1] = e
        elseif HasExtension(e.name, FileDrops.MEDIA_EXTENSIONS) then
            e.kind = "media"
            media[#media + 1] = e
        else
            skipped = skipped + 1
        end
        if e.kind ~= nil then
            e.id = dmhub.GenerateGuid()
            byPath[e.name:lower()] = e
            local base = (e.name:match("([^/]+)$") or e.name):lower()
            local list = byBase[base] or {}
            list[#list + 1] = e
            byBase[base] = list
            local stem = FileDrops.BaseName(base):lower()
            if stem ~= base then
                list = byBase[stem] or {}
                list[#list + 1] = e
                byBase[stem] = list
            end
        end
    end
    if #docs + #pdfs + #media == 0 then
        ShowError("Nothing to import", string.format("%s holds no documents, PDFs or pictures.", archiveName))
        return
    end

    --a file a link or embed names: relative to the linking file first, then
    --from the archive's root, then by name anywhere (Obsidian style).
    local function Find(baseDir, dest)
        local file = UrlDecode(dest:gsub("[#%?].*$", "")):gsub("\\", "/")
        if file == "" then
            return nil
        end
        local candidates = {}
        if file:sub(1, 1) == "/" then
            candidates[#candidates + 1] = NormalizePath(file)
        else
            candidates[#candidates + 1] = NormalizePath(baseDir ~= "" and (baseDir .. "/" .. file) or file)
            candidates[#candidates + 1] = NormalizePath(file)
        end
        for _, c in ipairs(candidates) do
            local e = byPath[c:lower()] or byPath[(c .. ".md"):lower()]
            if e ~= nil then
                return e
            end
        end
        local base = (file:match("([^/]+)$") or file):lower()
        local list = byBase[base]
        if list ~= nil and #list >= 1 then
            return list[1]
        end
        return nil
    end

    --convert every document; this decides which pictures are only embedded.
    local converted = {}
    for _, e in ipairs(docs) do
        local readError = nil
        local text = dmhub.ReadTextFile(e.path, function(message)
            readError = message
        end)
        if text == nil then
            e.failed = readError or "could not be read"
        else
            local doc = MarkdownDocument.new{id = e.id, content = "", annotations = {}}
            local baseDir = DirOf(e.name)
            local function LinkTo(target)
                if target == nil then
                    return nil
                end
                if target.kind == "media" then
                    target.linked = true
                end
                return JOURNAL_PREFIX .. target.id
            end
            local function Embed(target, alt)
                if target == nil or target.kind ~= "media" then
                    return nil
                end
                target.embedded = true
                return MediaAnnotation(doc, target.id, target.name, alt)
            end
            local ctx = {
                doc = doc,
                Link = function(dest)
                    if IsExternalUrl(dest) then
                        return SafeTarget(dest)
                    end
                    if dest:sub(1, 1) == "#" then
                        return nil
                    end
                    local target = Find(baseDir, dest)
                    if target == nil then
                        local file = UrlDecode(dest:gsub("[#%?].*$", ""))
                        if DocumentImport.IsTextPath(file) or FileDrops.Extension(file) == "" then
                            return NameTarget(file)
                        end
                        return nil
                    end
                    return LinkTo(target)
                end,
                Image = function(dest, alt)
                    if IsExternalUrl(dest) or dest:match("^data:") then
                        return nil
                    end
                    return Embed(Find(baseDir, dest), alt)
                end,
                Wiki = function(page)
                    local target = Find(baseDir, page)
                    if target == nil then
                        return NameTarget(page)
                    end
                    return LinkTo(target)
                end,
                WikiImage = function(page)
                    local target = Find(baseDir, page)
                    if target ~= nil and target.kind == "media" then
                        return Embed(target, nil)
                    end
                    return nil
                end,
            }
            local result, title
            if HasExtension(e.name, MARKDOWN_EXTENSIONS) or DocumentImport.LooksLikeMarkdown(text) then
                result, title = DocumentImport.ConvertMarkdown(text, ctx)
            else
                result = DocumentImport.ConvertPlainText(text)
            end
            converted[e] = {
                text = result,
                title = CleanTitle(title or FileDrops.BaseName(e.name)),
                annotations = doc.annotations,
            }
        end
    end

    --pictures that are only embedded stay out of the journal tree; any other
    --picture (linked to, or not mentioned at all) is a journal entry.
    local entryCount = #pdfs
    for _, e in ipairs(docs) do
        if converted[e] ~= nil then
            entryCount = entryCount + 1
        end
    end
    for _, e in ipairs(media) do
        e.isEntry = e.linked or not e.embedded
        if e.isEntry then
            entryCount = entryCount + 1
        end
    end

    --the main entry, which goes on the table: a readme/index at the top
    --level, else the shallowest document, else a PDF, else a picture.
    local function Depth(e)
        local _, slashes = e.name:gsub("/", "")
        return slashes
    end
    local main = nil
    local MAIN_NAMES = {readme = 1, index = 2, home = 3, start = 4, main = 5, _index = 6}
    local function Better(a, b)
        if b == nil then
            return true
        end
        if Depth(a) ~= Depth(b) then
            return Depth(a) < Depth(b)
        end
        local ra = MAIN_NAMES[FileDrops.BaseName(a.name):lower()] or 100
        local rb = MAIN_NAMES[FileDrops.BaseName(b.name):lower()] or 100
        if ra ~= rb then
            return ra < rb
        end
        return a.name:lower() < b.name:lower()
    end
    for _, e in ipairs(docs) do
        if converted[e] ~= nil and Better(e, main) then
            main = e
        end
    end
    if main == nil then
        for _, e in ipairs(pdfs) do
            if Better(e, main) then
                main = e
            end
        end
    end
    if main == nil then
        for _, e in ipairs(media) do
            if e.isEntry and Better(e, main) then
                main = e
            end
        end
    end

    --folders: one named after the archive when it makes more than one
    --entry, and one per folder inside it that holds entries.
    local ownerid = nil
    if not dmhub.isDM then
        ownerid = dmhub.loginUserid
    end
    local folderIds = {}
    if entryCount > 1 then
        folderIds[""] = assets:UploadNewDocumentFolder{
            id = dmhub.GenerateGuid(),
            description = CleanTitle(commonRoot or archiveName),
            parentFolder = parentFolder,
            ownerid = ownerid,
        }
    else
        folderIds[""] = parentFolder
    end
    local function FolderFor(dir)
        if folderIds[dir] ~= nil then
            return folderIds[dir]
        end
        local parentId = FolderFor(DirOf(dir))
        local id = assets:UploadNewDocumentFolder{
            id = dmhub.GenerateGuid(),
            description = CleanTitle(dir:match("([^/]+)$") or dir),
            parentFolder = parentId,
            ownerid = ownerid,
        }
        folderIds[dir] = id
        return id
    end

    --uploads, with one progress row for the lot.
    local operation = StartOperation("Importing " .. archiveName)
    local pending = 0
    local total = 0
    local failures = {}
    local function Started()
        pending = pending + 1
        total = total + 1
    end
    local finished = false
    local function Finished(name, message)
        pending = pending - 1
        if message ~= nil then
            failures[#failures + 1] = string.format("%s: %s", name, message)
        end
        if total > 0 then
            operation.progress = math.min(0.99, (total - pending) / total)
            operation:Update()
        end
        if pending == 0 and finished then
            operation.progress = 1
            operation:Update()
            if #failures > 0 then
                --skipped files (a .docx, a .psd...) are worth a line when
                --something went wrong anyway, but not a dialog of their own.
                if skipped > 0 then
                    failures[#failures + 1] = string.format("%d other file%s (not a document, PDF or picture) skipped",
                        skipped, skipped == 1 and "" or "s")
                end
                local shown = {}
                for k = 1, math.min(#failures, 6) do
                    shown[k] = failures[k]
                end
                if #failures > 6 then
                    shown[#shown + 1] = string.format("...and %d more.", #failures - 6)
                end
                ShowError("Some files could not be imported", table.concat(shown, "\n"))
            end
        end
    end

    local mainReady = function(entryid)
        if ready ~= nil then
            ready(entryid)
        end
    end

    for _, e in ipairs(media) do
        Started()
        local folder = nil
        if e.isEntry then
            folder = FolderFor(DirOf(e.name))
        end
        local name = e.name
        UploadMedia(e.path, e.id, folder, function(message)
            Finished(name, message)
            if message == nil and e == main then
                WhenInJournal(e.id, 30, mainReady)
            end
        end)
    end

    for _, e in ipairs(pdfs) do
        Started()
        local name = e.name
        --a file that cannot be read calls error at once and returns nil.
        assets.UploadPDFDocumentAsset{
            guid = e.id,
            path = e.path,
            parentFolder = FolderFor(DirOf(e.name)),
            description = CleanTitle(FileDrops.BaseName(e.name)),
            upload = function()
                Finished(name, nil)
                if e == main then
                    WhenInJournal(e.id, 60, mainReady)
                end
            end,
            error = function(message)
                Finished(name, message)
            end,
        }
    end

    for _, e in ipairs(docs) do
        local info = converted[e]
        if info == nil then
            failures[#failures + 1] = string.format("%s: %s", e.name, e.failed or "could not be read")
        else
            local ok = UploadDocument{
                id = e.id,
                title = info.title,
                parentFolder = FolderFor(DirOf(e.name)),
                text = info.text,
                annotations = info.annotations,
                --the main document heads its folder.
                ord = (e == main) and -1 or 0,
            }
            if not ok then
                failures[#failures + 1] = string.format("%s: too long to import", e.name)
            elseif e == main then
                WhenInJournal(e.id, 30, mainReady)
            end
        end
    end

    finished = true
    Started()
    Finished(archiveName, nil)
end

local function ImportZip(path, parentFolder, ready)
    local name = FileDrops.BaseName(path)
    dmhub.ExtractZip(path, function(files, message)
        if mod.unloaded then
            return
        end
        if files == nil then
            ShowError("Could not import " .. name, message or "The archive could not be read.")
            return
        end
        ImportFileSet(files, name, parentFolder, ready)
    end)
end

----------------------------------------------------------------------

--- Imports dropped files into the journal: PDFs, Markdown and text files,
--- and .zip archives of them (other files are ignored).
--- options.parentFolder: the journal folder they go in (default: the
--- user's private documents). options.ready(entryid, index): called when
--- the index-th file's main entry is in the journal (the document itself; a
--- zip's readme/index/first document), so the caller can put it on the table.
--- options.uploading(index, name): called as the index-th file starts a
--- slow upload (a PDF); returning a DocumentImportWatch shows its progress
--- there instead of in the app-locking upload dialog.
--- @param paths string[]
--- @param options nil|{parentFolder: nil|string, ready: nil|fun(entryid: string, index: integer), uploading: nil|fun(index: integer, name: string): nil|DocumentImportWatch}
function DocumentImport.ImportFiles(paths, options)
    options = options or {}
    local parentFolder = options.parentFolder or DocumentImport.DefaultFolder()
    local index = 0
    for _, path in ipairs(paths) do
        local ext = FileDrops.Extension(path)
        local fn = nil
        if ext == ".pdf" then
            fn = ImportPDF
        elseif ext == ".zip" then
            fn = ImportZip
        elseif DocumentImport.IsTextPath(path) then
            fn = ImportTextFile
        end
        if fn ~= nil then
            index = index + 1
            local myIndex = index
            local ready = nil
            if options.ready ~= nil then
                ready = function(entryid)
                    options.ready(entryid, myIndex)
                end
            end
            local watch = nil
            if fn == ImportPDF and options.uploading ~= nil then
                watch = options.uploading(myIndex, CleanTitle(FileDrops.BaseName(path)))
            end
            fn(path, parentFolder, ready, watch)
        end
    end
end
