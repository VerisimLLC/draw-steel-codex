--Encounter of the Week: lossless edits to script documents.
--
--The montage builder edits the script's own journal markdown; the markdown
--stays the source of truth (design: EncounterOfTheWeek.md, "The montage
--builder"). This module is the layer between them:
--
--  * Split / Join cut a document's text into lines and put it back together
--    byte for byte, keeping each line's own terminator ("\n", or "\v" for a
--    journal soft break), so lines are numbered exactly as the parser
--    numbers them (EncounterScript.SplitLines).
--  * Patches { docid, first, last, lines } replace a run of lines in one
--    document. Everything a patch does not cover is left untouched, so an
--    edit never reformats the author's text.
--  * The edit operations (SetTier, AddRider, InsertEntry...) take a parse
--    from EncounterScript.ParseExpanded and one of its elements, and return
--    the patches that make the change in whichever sub-document the element
--    came from. They use the line fields the parser records (entry.line,
--    roll.tierLines, entry.descriptionLines...).
--  * The writers (RollLines, RiderLine...) turn builder values into script
--    lines that the parser reads back to the same values.
--
--PURE Lua like EncounterScript: no engine globals, so it runs under the
--bundled lua.exe (tests/encounter_script_edit_test.lua). The builder UI
--uploads the new text (CustomDocument:SetTextContent + Upload).

EncounterScriptEdit = rawget(_G, "EncounterScriptEdit") or {}
local E = EncounterScriptEdit

--Messages and starter text: UIText, EncounterAuthoringText.lua (loads first).
local T = UIText.T

local function trim(s)
    return (string.gsub(s or "", "^%s*(.-)%s*$", "%1"))
end

--- lines -----------------------------------------------------------------------

--text -> { lines = {...}, ends = {...} }: ends[i] is the terminator after
--lines[i] ("\n", "\r\n", "\r", "\v", or "" for the last line). The line
--count always matches EncounterScript.SplitLines on the same text.
function E.Split(text)
    text = text or ""
    local lines, ends = {}, {}
    local pos, n = 1, #text
    local start = 1
    while pos <= n do
        local c = string.sub(text, pos, pos)
        if c == "\n" or c == "\v" then
            lines[#lines + 1] = string.sub(text, start, pos - 1)
            ends[#ends + 1] = c
            pos = pos + 1
            start = pos
        elseif c == "\r" then
            lines[#lines + 1] = string.sub(text, start, pos - 1)
            if string.sub(text, pos + 1, pos + 1) == "\n" then
                ends[#ends + 1] = "\r\n"
                pos = pos + 2
            else
                ends[#ends + 1] = "\r"
                pos = pos + 1
            end
            start = pos
        else
            pos = pos + 1
        end
    end
    lines[#lines + 1] = string.sub(text, start)
    ends[#ends + 1] = ""
    return { lines = lines, ends = ends }
end

function E.Join(split)
    local out = {}
    for i, line in ipairs(split.lines) do
        out[#out + 1] = line
        out[#out + 1] = split.ends[i] or "\n"
    end
    return table.concat(out)
end

--Replace lines first..last of text with newLines (a list of strings without
--terminators). last = first - 1 inserts before line `first`; an empty
--newLines deletes. New lines end in "\n"; the last of them takes over the
--terminator of the last line replaced, so the end of the document (and a
--soft break) is kept.
function E.Replace(text, first, last, newLines)
    local s = E.Split(text)
    local n = #s.lines
    assert(first >= 1 and first <= n + 1 and last >= first - 1 and last <= n,
        string.format("EncounterScriptEdit.Replace: lines %d-%d out of range (1-%d)", first, last, n))
    local lines, ends = {}, {}
    for i = 1, first - 1 do
        lines[#lines + 1] = s.lines[i]
        ends[#ends + 1] = s.ends[i]
    end
    for _, l in ipairs(newLines) do
        lines[#lines + 1] = l
        ends[#ends + 1] = "\n"
    end
    if last >= first and #newLines > 0 then
        ends[#ends] = s.ends[last]
    elseif first == n + 1 and #newLines > 0 then
        --appended after the final line: that line now needs a terminator,
        --and the document still ends the way it did.
        ends[first - 1] = "\n"
        ends[#ends] = s.ends[n]
    end
    for i = last + 1, n do
        lines[#lines + 1] = s.lines[i]
        ends[#ends + 1] = s.ends[i]
    end
    return E.Join({ lines = lines, ends = ends })
end

--- patches -----------------------------------------------------------------------

--A patch replaces lines first..last of one document (last = first - 1 is an
--insertion before `first`).
function E.Patch(docid, first, last, lines)
    return { docid = docid, first = first, last = last, lines = lines or {} }
end

--Apply patches to texts = { [docid] = text }. Returns a new table holding
--only the documents that changed. Patches on one document must not
--overlap; they are applied bottom-up so each one's line numbers stay valid.
function E.Apply(texts, patches)
    local byDoc = {}
    for _, p in ipairs(patches) do
        byDoc[p.docid] = byDoc[p.docid] or {}
        local list = byDoc[p.docid]
        list[#list + 1] = p
    end
    local changed = {}
    for docid, list in pairs(byDoc) do
        table.sort(list, function(a, b)
            if a.first ~= b.first then
                return a.first > b.first
            end
            --two insertions at one point: keep their given order.
            return a.last > b.last
        end)
        for i = 2, #list do
            local below, above = list[i - 1], list[i]
            assert(above.last < below.first or (above.last == above.first - 1 and above.first <= below.first),
                "EncounterScriptEdit.Apply: overlapping patches on " .. tostring(docid))
        end
        local text = texts[docid]
        assert(text ~= nil, "EncounterScriptEdit.Apply: no text for document " .. tostring(docid))
        for _, p in ipairs(list) do
            text = E.Replace(text, p.first, p.last, p.lines)
        end
        changed[docid] = text
    end
    return changed
end

--- where an element lives --------------------------------------------------------

--The document and line an expanded-script line came from. A parse that did
--not come through ParseExpanded is one document, `parse.rootId`.
function E.Source(parse, line)
    if parse.sources == nil then
        return parse.rootId, line
    end
    local src = parse.sources[line]
    if src == nil then
        return nil, nil
    end
    return src.docid, src.line
end

--The document range of expanded lines first..last, or nil when they do not
--sit together in one document (an include link in between).
function E.SourceRange(parse, first, last)
    local docid, a = E.Source(parse, first)
    local docid2, b = E.Source(parse, last)
    if docid == nil or docid ~= docid2 or b - a ~= last - first then
        return nil
    end
    return docid, a, b
end

--A patch replacing expanded lines first..last (last = first - 1: insert
--before `first`), or nil + why.
function E.PatchExpanded(parse, first, last, lines)
    if last == first - 1 then
        local docid, a = E.Source(parse, first)
        if docid == nil then
            return nil, T("author.script_edit.place_not_in_document")
        end
        return E.Patch(docid, a, a - 1, lines)
    end
    local docid, a, b = E.SourceRange(parse, first, last)
    if docid == nil then
        return nil, T("author.script_edit.spans_documents")
    end
    return E.Patch(docid, a, b, lines)
end

--Insert lines after expanded line `after`: in the document `after` came
--from, right below it (an insertion at the end of a sub-document stays in
--that sub-document, which inserting before the next expanded line would not).
function E.PatchAfter(parse, after, lines)
    local docid, a = E.Source(parse, after)
    if docid == nil then
        return nil, T("author.script_edit.place_not_in_document")
    end
    return E.Patch(docid, a + 1, a, lines)
end

--Heading level of a line: 1-4 for "#" .. "####" followed by a space, else nil.
function E.HeadingLevel(line)
    local hashes = string.match(trim(line), "^(#+)%s+%S")
    if hashes == nil or #hashes > 4 then
        return nil
    end
    return #hashes
end

--The lines an element headed at expanded line `line` (level 2 entry, 3
--option, 4 knack) covers in its own document: up to the next heading of
--that level or higher, or the end of the document, without trailing blank
--lines. Returns docid, first, last (document lines).
function E.ElementRange(parse, docTexts, line, level)
    local docid, first = E.Source(parse, line)
    if docid == nil or docTexts[docid] == nil then
        return nil
    end
    local lines = E.Split(docTexts[docid]).lines
    local last = #lines
    for i = first + 1, #lines do
        local l = E.HeadingLevel(lines[i])
        if l ~= nil and l <= level then
            last = i - 1
            break
        end
    end
    while last > first and trim(lines[last]) == "" do
        last = last - 1
    end
    return docid, first, last
end

--- writers -------------------------------------------------------------------------

--Text inside one script line: no line breaks, and no "|" (it ends a tier).
function E.LineText(text)
    local s = string.gsub(text or "", "[\r\n\v]+", " ")
    s = string.gsub(s, "|", "/")
    return trim(s)
end

--Prose -> lines: paragraphs separated by one blank line, each line trimmed.
function E.ProseLines(text)
    local out = {}
    local s = string.gsub(text or "", "\r\n?", "\n")
    s = string.gsub(s, "\v", "\n")
    local blank = true
    for line in string.gmatch(s .. "\n", "(.-)\n") do
        line = trim(line)
        if line == "" then
            blank = true
        else
            if blank and #out > 0 then
                out[#out + 1] = ""
            end
            out[#out + 1] = line
            blank = false
        end
    end
    return out
end

--Why prose would not stay prose once written into an entry, or nil.
function E.ProseProblem(text)
    for _, line in ipairs(E.ProseLines(text)) do
        if E.HeadingLevel(line) ~= nil then
            return T("author.script_edit.prose.heading")
        elseif string.match(line, "^|") then
            return T("author.script_edit.prose.rules_line")
        elseif string.match(line, "^%-%-%-+$") then
            return T("author.script_edit.prose.scene_line")
        elseif string.match(line, "^%[%[.+%]%]$") then
            return T("author.script_edit.prose.tag_line")
        elseif string.match(string.lower(line), "^consequences?:") or string.match(string.lower(line), "^options?:") then
            return T("author.script_edit.prose.keyword_line")
        end
    end
    return nil
end

local ENTRY_KIND_WORD = { opportunity = "Opportunity", threat = "Threat", obstacle = "Obstacle" }

--{ kind, name, required, locked, temporary } -> "## Threat: Name (Required, Temporary)"
function E.EntryHeadingLine(e)
    local tags = {}
    if e.required then tags[#tags + 1] = "Required" end
    if e.locked then tags[#tags + 1] = "Locked" end
    if e.temporary then tags[#tags + 1] = "Temporary" end
    local line = string.format("## %s: %s", ENTRY_KIND_WORD[e.kind] or "Opportunity", E.LineText(e.name))
    if #tags > 0 then
        line = line .. " (" .. table.concat(tags, ", ") .. ")"
    end
    return line
end

function E.OptionHeadingLine(name)
    return "### " .. E.LineText(name)
end

function E.KnackHeadingLine(requirement)
    return "#### If " .. E.LineText(requirement)
end

function E.RoundHeadingLine(number)
    return string.format("## Round %d", number)
end

--characteristics = { "Might", "Agility" }, skills = { "Climb" } -> "Might or Agility (Climb)"
function E.AttrText(characteristics, skills)
    local text = table.concat(characteristics or {}, " or ")
    if skills ~= nil and #skills > 0 then
        text = text .. " (" .. table.concat(skills, ", ") .. ")"
    end
    return text
end

--"|Name: Attr". The name loses any ":" (the header splits on ": ").
function E.RollHeaderLine(name, attrText)
    local n = string.gsub(E.LineText(name), ":", "")
    return string.format("|%s: %s", trim(n), E.LineText(attrText))
end

--A tier line, with its teaser ("|teaser => full text") when there is one.
function E.TierLine(teaser, text)
    text = string.gsub(E.LineText(text), "=>", "->")
    teaser = teaser ~= nil and string.gsub(E.LineText(teaser), "=>", "->") or nil
    if teaser ~= nil and teaser ~= "" then
        return string.format("|%s => %s", teaser, text)
    end
    return "|" .. text
end

local RIDER_WORDS = { allow = "Allow", edge = "Edge", doubleedge = "Double Edge", bane = "Bane", doublebane = "Double Bane" }
E.RIDER_EFFECTS = { "edge", "doubleedge", "bane", "doublebane", "allow" }

function E.RiderWord(effect)
    return RIDER_WORDS[effect] or "Edge"
end

--"|Edge (Round 1): you speak Zaliac"
function E.RiderLine(effect, round, requirement)
    local label = E.RiderWord(effect)
    if round ~= nil then
        label = string.format("%s (Round %d)", label, round)
    end
    return string.format("|%s: %s", label, E.LineText(requirement))
end

--roll = { name, attr (text) or characteristics + skills, tiers = { {teaser, text} x3-4 },
--         riders = { {effect, round, text} } } -> the block's lines.
function E.RollLines(roll)
    local attr = roll.attr or E.AttrText(roll.characteristics, roll.skills)
    local lines = { E.RollHeaderLine(roll.name, attr) }
    for _, tier in ipairs(roll.tiers or {}) do
        lines[#lines + 1] = E.TierLine(tier.teaser, tier.text)
    end
    for _, r in ipairs(roll.riders or {}) do
        lines[#lines + 1] = E.RiderLine(r.effect, r.round, r.text)
    end
    return lines
end

--Must stay in the form EncounterScript.TableHeaderDice parses, or the table silently stops being one.
---@param dice string
---@param mystery boolean|nil
---@return string
function E.TableHeaderValue(dice, mystery)
    local value = E.LineText(dice)
    if mystery then
        value = value .. " (Mystery)"
    end
    return value
end

--table = { name, dice = "1d6", mystery = nil|true, rows = { {lo, hi, text} } }
function E.TableLines(t)
    local name = string.gsub(E.LineText(t.name), ":", "")
    local lines = { string.format("|%s: %s", trim(name), E.TableHeaderValue(t.dice or "1d6", t.mystery)) }
    for _, row in ipairs(t.rows or {}) do
        local range = tostring(row.lo)
        if row.hi ~= nil and row.hi ~= row.lo then
            range = string.format("%d-%d", row.lo, row.hi)
        end
        lines[#lines + 1] = string.format("|%s: %s", range, E.LineText(row.text))
    end
    return lines
end

--{ min, max (nil = and up), removals = { opportunity = n, threat = n } }
--  -> "4-5 Players: -1 Opportunity, -1 Threat"
function E.ScalingLine(d)
    local range = tostring(d.min)
    if d.max == nil then
        range = range .. "+"
    elseif d.max ~= d.min then
        range = string.format("%d-%d", d.min, d.max)
    end
    local parts = {}
    for _, kind in ipairs({ "opportunity", "threat" }) do
        local n = (d.removals or {})[kind]
        if n ~= nil and n > 0 then
            parts[#parts + 1] = string.format("-%d %s", n, ENTRY_KIND_WORD[kind])
        end
    end
    return string.format("%s Players: %s", range, table.concat(parts, ", "))
end

--- block insertion --------------------------------------------------------------

--Lines to insert after document line `after` of `lines`, with blank lines
--added so the block is a paragraph of its own on both sides.
local function Padded(lines, after, block)
    local out = {}
    local above = lines[after]
    if above ~= nil and trim(above) ~= "" then
        out[#out + 1] = ""
    end
    for _, l in ipairs(block) do
        out[#out + 1] = l
    end
    local below = lines[after + 1]
    if below ~= nil and trim(below) ~= "" then
        out[#out + 1] = ""
    end
    return out
end

--A patch inserting `block` after expanded line `after`, padded with blank
--lines as needed. docTexts = { [docid] = text } (the documents' current text).
function E.InsertBlockAfter(parse, docTexts, after, block)
    local docid, a = E.Source(parse, after)
    if docid == nil or docTexts[docid] == nil then
        return nil, T("author.script_edit.place_not_in_document")
    end
    local lines = E.Split(docTexts[docid]).lines
    return E.Patch(docid, a + 1, a, Padded(lines, a, block))
end

--The same, at document line `after` of document `docid` (0 = the top).
function E.InsertBlockAfterDocLine(docTexts, docid, after, block)
    local lines = E.Split(docTexts[docid] or "").lines
    return E.Patch(docid, after + 1, after, Padded(lines, after, block))
end

--Replace the region from the first span's start to the last span's end
--(spans are {first, last} expanded lines) with `block`.
local function ReplaceSpans(parse, spans, block)
    local first, last = spans[1][1], spans[#spans][2]
    return E.PatchExpanded(parse, first, last, block)
end

--- edit operations -------------------------------------------------------------------
--
--Each returns a list of patches, or nil + a sentence saying why it cannot
--be done. `parse` is from EncounterScript.ParseExpanded; `docTexts` maps
--every document in it (root and included) to its current text.

local function One(patch, why)
    if patch == nil then
        return nil, why
    end
    return { patch }
end

function E.SetLine(parse, line, newLine)
    return One(E.PatchExpanded(parse, line, line, { newLine }))
end

function E.DeleteLine(parse, line)
    return One(E.PatchExpanded(parse, line, line, {}))
end

--Rename / retag an entry: fields = { kind, name, required, locked, temporary }
--(missing ones keep the entry's own).
function E.SetEntryHeading(parse, entry, fields)
    local e = { kind = fields.kind or entry.kind, name = fields.name or entry.name }
    for _, key in ipairs({ "required", "locked", "temporary" }) do
        if fields[key] ~= nil then
            e[key] = fields[key]
        else
            e[key] = entry[key]
        end
    end
    return E.SetLine(parse, entry.line, E.EntryHeadingLine(e))
end

--An entry's card text (the paragraphs above its scene and options).
function E.SetDescription(parse, docTexts, entry, text)
    local problem = E.ProseProblem(text)
    if problem ~= nil then
        return nil, problem
    end
    local block = E.ProseLines(text)
    if entry.descriptionLines ~= nil then
        return One(ReplaceSpans(parse, entry.descriptionLines, block))
    end
    if #block == 0 then
        return {}
    end
    return One(E.InsertBlockAfter(parse, docTexts, entry.line, block))
end

--Any prose field held as spans (option.textLines, beat.introLines...): the
--spans are replaced, or with none the text goes in after expanded line
--`afterLine`. Text "" removes the paragraphs.
function E.SetProse(parse, docTexts, spans, afterLine, text)
    local problem = E.ProseProblem(text)
    if problem ~= nil then
        return nil, problem
    end
    local block = E.ProseLines(text)
    if spans ~= nil and #spans > 0 then
        return One(ReplaceSpans(parse, spans, block))
    end
    if #block == 0 then
        return {}
    end
    return One(E.InsertBlockAfter(parse, docTexts, afterLine, block))
end

--Replace a whole element (entry, option, knack: heading at expanded line
--`line`, of that level) with the lines of `text`, as written.
function E.ReplaceElement(parse, docTexts, line, level, text)
    local docid, first, last = E.ElementRange(parse, docTexts, line, level)
    if docid == nil then
        return nil, T("author.script_edit.element_not_in_document")
    end
    local block = E.Split(string.gsub(text or "", "\r", "")).lines
    while #block > 0 and trim(block[#block]) == "" do
        block[#block] = nil
    end
    return { E.Patch(docid, first, last, block) }
end

--The line of the ROOT document an expanded line belongs to: the line itself
--when it is in the root, else the include link that pulled its document in.
--Returns the root's line number, or nil.
function E.RootLine(parse, line)
    for l = line, 1, -1 do
        local docid, at = E.Source(parse, l)
        if docid == parse.rootId then
            return at
        end
    end
    return nil
end

--A threat's "Consequence:" line; text "" removes it. A new one goes right
--below the card text (it must come before the first option: below one, the
--parser reads it as that option's text).
function E.SetConsequence(parse, docTexts, entry, text)
    text = E.LineText(text)
    if entry.consequence ~= nil and entry.consequence.lines ~= nil then
        local span = entry.consequence.lines
        if text == "" then
            return One(E.PatchExpanded(parse, span[1], span[2], {}))
        end
        return One(E.PatchExpanded(parse, span[1], span[2], { "Consequence: " .. text }))
    end
    if text == "" then
        return {}
    end
    local after = entry.line
    if entry.descriptionLines ~= nil then
        after = entry.descriptionLines[#entry.descriptionLines][2]
    end
    return One(E.InsertBlockAfter(parse, docTexts, after, { "Consequence: " .. text }))
end

--Rewrite a roll's header: name and attr text ("Presence (Lie, Flirt)").
function E.SetRollHeader(parse, roll, name, attrText)
    return E.SetLine(parse, roll.line, E.RollHeaderLine(name, attrText))
end

--Tier t (1-4) of a roll. For t = 4 on an automatic critical a line is
--written after tier 3; ClearCritical goes back to the automatic one.
function E.SetTier(parse, roll, t, teaser, text)
    local line = E.TierLine(teaser, text)
    local at = roll.tierLines[t]
    if at ~= nil then
        return E.SetLine(parse, at, line)
    end
    if t == 4 and roll.tierLines[3] ~= nil then
        return One(E.PatchAfter(parse, roll.tierLines[3], { line }))
    end
    return nil, T("author.script_edit.tier_no_line", { tier = t })
end

function E.ClearCritical(parse, roll)
    if roll.tierLines[4] == nil then
        return {}
    end
    return E.DeleteLine(parse, roll.tierLines[4])
end

--The last line of an option's (or knack's) rules: its roll block, else its
--free rules and riders. nil when it has neither.
local function RulesEnd(holder)
    if holder.roll ~= nil then
        return holder.roll.lastLine
    end
    local last = nil
    if holder.free ~= nil then
        for _, l in ipairs(holder.free.lines or { holder.free.line }) do
            last = math.max(last or l, l)
        end
    end
    for _, r in ipairs(holder.riders or {}) do
        last = math.max(last or r.line, r.line)
    end
    return last
end

--Add a rider to an option or knack: inside its roll block (after the
--tiers and riders), else after its free rules.
function E.AddRider(parse, docTexts, holder, effect, round, requirement)
    local line = E.RiderLine(effect, round, requirement)
    local after = RulesEnd(holder)
    if after ~= nil then
        return One(E.PatchAfter(parse, after, { line }))
    end
    return One(E.InsertBlockAfter(parse, docTexts, holder.line, { line }))
end

function E.SetRider(parse, rider, effect, round, requirement)
    return E.SetLine(parse, rider.line, E.RiderLine(effect, round, requirement))
end

function E.RemoveRider(parse, rider)
    return E.DeleteLine(parse, rider.line)
end

--Replace an option's (or knack's) whole rules block -- roll, riders or
--free lines -- with `block` (from RollLines, or "|clause" lines).
function E.SetRules(parse, docTexts, holder, block)
    if holder.roll ~= nil then
        --a roll's riders sit inside its block (roll.line..roll.lastLine).
        local riderOutside = false
        for _, r in ipairs(holder.riders or {}) do
            if r.line < holder.roll.line or r.line > holder.roll.lastLine then
                riderOutside = true
            end
        end
        if riderOutside then
            return nil, T("author.script_edit.riders_outside_roll")
        end
        return One(E.PatchExpanded(parse, holder.roll.line, holder.roll.lastLine, block))
    end
    local first, last = nil, RulesEnd(holder)
    if holder.free ~= nil then
        first = holder.free.lines[1]
    end
    for _, r in ipairs(holder.riders or {}) do
        first = math.min(first or r.line, r.line)
    end
    if first == nil then
        return One(E.InsertBlockAfter(parse, docTexts, holder.line, block))
    end
    --the rules have to be one run of lines to be replaced as one.
    for l = first, last do
        local docid = E.Source(parse, l)
        if docid == nil then
            return nil, T("author.script_edit.rules_split")
        end
    end
    return One(E.PatchExpanded(parse, first, last, block))
end

--Append a whole element block (entry, option, knack) after the element
--headed at expanded line `line` of that level, in the same document.
function E.InsertAfterElement(parse, docTexts, line, level, block)
    local docid, _, last = E.ElementRange(parse, docTexts, line, level)
    if docid == nil then
        return nil, T("author.script_edit.element_not_in_document")
    end
    local lines = E.Split(docTexts[docid]).lines
    return { E.Patch(docid, last + 1, last, Padded(lines, last, block)) }
end

--Delete the element headed at expanded line `line` (with the blank lines
--that followed it, so no gap is left behind).
function E.DeleteElement(parse, docTexts, line, level)
    local docid, first, last = E.ElementRange(parse, docTexts, line, level)
    if docid == nil then
        return nil, T("author.script_edit.element_not_in_document")
    end
    local lines = E.Split(docTexts[docid]).lines
    while last < #lines and trim(lines[last + 1]) == "" do
        last = last + 1
    end
    return { E.Patch(docid, first, last, {}) }
end

--The lines of an element as written (for move / duplicate).
function E.ElementLines(parse, docTexts, line, level)
    local docid, first, last = E.ElementRange(parse, docTexts, line, level)
    if docid == nil then
        return nil
    end
    local lines = E.Split(docTexts[docid]).lines
    local out = {}
    for i = first, last do
        out[#out + 1] = lines[i]
    end
    return out
end

--- new elements ------------------------------------------------------------------------

--A new option block: heading, optional prose, then its rules (roll lines
--or free "|" lines).
function E.OptionBlock(name, text, rules)
    local block = { E.OptionHeadingLine(name) }
    local prose = E.ProseLines(text)
    if #prose > 0 then
        block[#block + 1] = ""
        for _, l in ipairs(prose) do
            block[#block + 1] = l
        end
    end
    if rules ~= nil and #rules > 0 then
        block[#block + 1] = ""
        for _, l in ipairs(rules) do
            block[#block + 1] = l
        end
    end
    return block
end

--A new entry block (a sub-document's whole text, or lines for the master):
--e = { kind, name, required, locked, temporary, description, consequence,
--      options = { OptionBlock lines, ... } }
function E.EntryBlock(e)
    local block = { E.EntryHeadingLine(e) }
    local prose = E.ProseLines(e.description)
    if #prose > 0 then
        block[#block + 1] = ""
        for _, l in ipairs(prose) do
            block[#block + 1] = l
        end
    end
    if e.consequence ~= nil and E.LineText(e.consequence) ~= "" then
        block[#block + 1] = ""
        block[#block + 1] = "Consequence: " .. E.LineText(e.consequence)
    end
    for _, option in ipairs(e.options or {}) do
        block[#block + 1] = ""
        for _, l in ipairs(option) do
            block[#block + 1] = l
        end
    end
    return block
end

--The link line that includes a sub-document: "[Name]".
function E.IncludeLine(docName)
    return "[" .. E.LineText(docName) .. "]"
end

--- scene steps as forms ------------------------------------------------------------
--
--The builder shows each scene line as a small form (who speaks, who enters,
--a branch's condition...) instead of raw text. ReadSceneStep turns a line
--into the form's values with the parser's own rules; SceneStepLine writes
--the values back as a line the parser reads to the same step.

--The emotes a character can show, in a fixed order for dropdowns.
function E.SceneEmotes()
    local list = {}
    for name, _ in pairs(EncounterScript.SCENE_EMOTES) do
        list[#list + 1] = name
    end
    table.sort(list)
    return list
end

--One scene line -> a form:
--  { kind = "narrate", text }
--  { kind = "say", speaker ("PC", a character, or an off-stage name),
--    offstage = bool, emote = nil|word, lang = nil|name, text }
--  { kind = "enter", name, monster }   { kind = "exit", name }
--  { kind = "emote", name, emote }
--  { kind = "if"|"elseif", cond = condition text }  { kind = "else" }  { kind = "end" }
--`actors` is the entry's characters (entry.actors), as the parser reads it.
function E.ReadSceneStep(text, actors)
    local branch, condText = EncounterScript.SceneBranchLine(text)
    if branch ~= nil then
        local c = nil
        if condText ~= nil then
            c = trim((string.gsub(trim(condText), "%s+[tT][hH][eE][nN]$", "")))
        end
        return { kind = branch, cond = c }
    end
    local steps = EncounterScript.CompileScene({ { text = text, line = 1 } }, actors or {}, "outcome", function() end)
    local step = steps[1]
    if step == nil then
        return { kind = "narrate", text = trim(text) }
    end
    if step.kind == "say" then
        return { kind = "say", speaker = step.speaker, offstage = step.offstage == true, emote = step.emote, lang = step.lang, text = step.text }
    elseif step.kind == "enter" then
        return { kind = "enter", name = step.name, monster = step.monster }
    elseif step.kind == "exit" then
        return { kind = "exit", name = step.name }
    elseif step.kind == "emote" then
        return { kind = "emote", name = step.name, emote = step.emote }
    end
    return { kind = "narrate", text = step.text or trim(text) }
end

--A form (as ReadSceneStep returns) -> the scene line, without indentation.
function E.SceneStepLine(step)
    local kind = step.kind
    if kind == "say" then
        local speaker = (string.gsub(E.LineText(step.speaker), ":", ""))
        if speaker == "" then
            speaker = "PC"
        end
        if step.offstage then
            speaker = speaker .. " (offstage)"
        elseif step.emote ~= nil and step.emote ~= "" then
            speaker = string.format("%s (%s)", speaker, step.emote)
        end
        local said = E.LineText(step.text)
        if step.lang ~= nil and E.LineText(step.lang) ~= "" then
            said = string.format("(in %s) %s", E.LineText(step.lang), said)
        end
        return string.format("%s: %s", speaker, said)
    elseif kind == "enter" then
        local name = E.LineText(step.name)
        local monster = E.LineText(step.monster)
        if monster == "" or string.lower(monster) == string.lower(name) then
            return name .. " enters"
        end
        return string.format("%s (%s) enters", name, monster)
    elseif kind == "exit" then
        return E.LineText(step.name) .. " exits"
    elseif kind == "emote" then
        return string.format("%s is %s", E.LineText(step.name), E.LineText(step.emote))
    elseif kind == "if" or kind == "elseif" then
        return string.format("%s %s then", kind, E.LineText(step.cond))
    elseif kind == "else" or kind == "end" then
        return kind
    end
    return E.LineText(step.text)
end

--Where an "if" block ends: `lines` are a scene's lines (strings) and
--`first` the index of an "if"; returns the index of its matching "end",
--or nil when the block is never closed.
function E.SceneBlockEnd(lines, first)
    local depth = 0
    for i = first, #lines do
        local kind = EncounterScript.SceneBranchLine(lines[i])
        if kind == "if" then
            depth = depth + 1
        elseif kind == "end" then
            depth = depth - 1
            if depth == 0 then
                return i
            end
        end
    end
    return nil
end

--The last line of the branch that `first` (an "if", "elseif" or "else")
--opens: the line before the next "elseif" / "else" / "end" of the same
--block. nil when the block is never closed.
function E.SceneBranchEnd(lines, first)
    local depth = 0
    for i = first + 1, #lines do
        local kind = EncounterScript.SceneBranchLine(lines[i])
        if kind == "if" then
            depth = depth + 1
        elseif kind == "end" then
            if depth == 0 then
                return i - 1
            end
            depth = depth - 1
        elseif (kind == "elseif" or kind == "else") and depth == 0 then
            return i - 1
        end
    end
    return nil
end

--- branch conditions as forms ----------------------------------------------------
--
--A condition is a flat list of rows, joined by "and" / "or" ("and" binds
--tighter, as in the parser), each optionally negated:
--  { { negate = bool, kind, value }, { join = "and"|"or", negate, kind, value }, ... }
--kind: "speaks" (a language), "kindred" (ancestry, class...: "PC is a X"),
--"career" ("PC was a X"), "skilled", "perk", "has", "can" (a capability),
--"is" ("PC is small"), "chose" (an option), "tier" (value "1"-"3", "4" =
--critical), or "custom" (value = the atom as written).

--One atom's text -> { negate, kind, value }. Matched on the lowered text,
--with the value cut from the original so its capitals survive.
local function ReadAtom(text)
    local s = trim(text)
    local lc = string.lower(s)
    --`pattern` has one "(.+)" capture; the same span of the original text.
    local function Tail(pattern)
        local pos, capture = string.match(lc, (string.gsub(pattern, "%(%.%+%)", "()(.+)")))
        if pos == nil then
            return nil
        end
        return trim(string.sub(s, pos, pos + #capture - 1))
    end
    local n = string.match(lc, "^tier%s*(%d)$")
    if n ~= nil and tonumber(n) >= 1 and tonumber(n) <= 3 then
        return { kind = "tier", value = n }
    end
    local words = { one = "1", two = "2", three = "3" }
    local w = string.match(lc, "^tier%s+(%a+)$")
    if w ~= nil and words[w] ~= nil then
        return { kind = "tier", value = words[w] }
    end
    if lc == "crit" or lc == "critical" or lc == "critical success" or lc == "a critical success" then
        return { kind = "tier", value = "4" }
    end
    local v = Tail("^pc does not speak (.+)$") or Tail("^pc doesn't speak (.+)$")
    if v ~= nil then
        return { kind = "speaks", value = v, negate = true }
    end
    v = Tail("^pc speaks (.+)$") or Tail("^pc knows (.+)$")
    if v ~= nil then
        return { kind = "speaks", value = v }
    end
    v = Tail("^pc is skilled in (.+)$")
    if v ~= nil then
        return { kind = "skilled", value = v }
    end
    v = Tail("^pc has the (.+) perk$")
    if v ~= nil then
        return { kind = "perk", value = v }
    end
    v = Tail("^pc has (.+)$")
    if v ~= nil then
        return { kind = "has", value = v }
    end
    v = Tail("^pc can (.+)$")
    if v ~= nil then
        return { kind = "can", value = v }
    end
    v = Tail("^pc was an? (.+)$")
    if v ~= nil then
        return { kind = "career", value = v }
    end
    v = Tail("^pc is an? (.+)$")
    if v ~= nil then
        return { kind = "kindred", value = v }
    end
    v = Tail("^pc is (.+)$")
    if v ~= nil then
        return { kind = "is", value = v }
    end
    v = Tail("^pc chose (.+)$") or Tail("^pc chooses (.+)$")
    if v ~= nil then
        return { kind = "chose", value = v }
    end
    return { kind = "custom", value = s }
end

--Condition text -> rows, or nil when the form cannot hold it (parentheses,
--or a missing condition). The text may end in "then".
function E.ReadCondition(text)
    local src = trim(text or "")
    src = string.gsub(src, "%s+[tT][hH][eE][nN]$", "")
    if string.find(src, "[()]") ~= nil then
        return nil
    end
    local rows = {}
    local words = {}
    local join = nil
    local negate = false
    local function Flush()
        if #words == 0 then
            return false
        end
        local atom = ReadAtom(table.concat(words, " "))
        if negate then
            atom.negate = not atom.negate
        end
        atom.join = join
        rows[#rows + 1] = atom
        words = {}
        negate = false
        return true
    end
    for word in string.gmatch(src, "%S+") do
        local lw = string.lower(word)
        if lw == "and" or lw == "or" then
            if not Flush() then
                return nil
            end
            join = lw
        elseif lw == "not" and #words == 0 then
            negate = not negate
        else
            words[#words + 1] = word
        end
    end
    if not Flush() then
        return nil
    end
    return rows
end

--"a" or "an" before a name.
local function Article(name)
    if string.match(string.lower(name or ""), "^[aeiou]") then
        return "an"
    end
    return "a"
end

--One row -> its atom text, without the join.
function E.ConditionAtomText(row)
    local value = E.LineText(row.value)
    local kind = row.kind
    local text
    if kind == "tier" then
        text = value == "4" and "crit" or ("tier" .. value)
    elseif kind == "speaks" then
        text = "PC speaks " .. value
    elseif kind == "skilled" then
        text = "PC is skilled in " .. value
    elseif kind == "perk" then
        text = string.format("PC has the %s perk", value)
    elseif kind == "has" then
        text = "PC has " .. value
    elseif kind == "can" then
        text = "PC can " .. value
    elseif kind == "career" then
        text = string.format("PC was %s %s", Article(value), value)
    elseif kind == "kindred" then
        text = string.format("PC is %s %s", Article(value), value)
    elseif kind == "is" then
        text = "PC is " .. value
    elseif kind == "chose" then
        text = "PC chose " .. value
    else
        text = value
    end
    if row.negate then
        text = "not " .. text
    end
    return text
end

--Rows -> condition text (no "if" / "then").
function E.ConditionText(rows)
    local parts = {}
    for i, row in ipairs(rows) do
        if i > 1 then
            parts[#parts + 1] = row.join == "or" and "or" or "and"
        end
        parts[#parts + 1] = E.ConditionAtomText(row)
    end
    return table.concat(parts, " ")
end

--- outcomes as forms ------------------------------------------------------------
--
--A tier line (or a Consequence:, a no-roll rule, a dice-table row) is free
--text with mechanical clauses in it. The builder shows it as the free text
--plus one row per mechanical clause (EncounterScript.CLAUSES). The free text
--is every clause the grammar reads as flavour, in order, with the
--punctuation it was written with; the effects follow it when the line is
--written back. An effect the author did not touch keeps its own wording.

--One tier line -> { text = the free text, effects = { effect, ... } }. Each
--effect is ParseClause's table (kind, target, qty, name, ...) plus:
--  hidden  written in {braces}
--  text    the clause as written (kept while the row is untouched)
--  sep     the punctuation that ended it ("" at the end of the line)
--  prefix  flavour written between the previous effect and this one ("At
--          the start of the next combat, "), glued to it
--  suffix  (last effect only) flavour written after it
--The free text is the flavour before the first effect, so an untouched line
--is written back exactly as it was.
function E.ReadOutcome(line)
    local lead = {}
    local pending = {}
    local effects = {}
    line = line or ""
    local spans = EncounterScript.ParseEffectSpans(line)
    --the punctuation after span i, whole ("..." or "?!", which the
    --splitter cut at its first character).
    local function Sep(i)
        local stop = spans[i + 1] ~= nil and spans[i + 1].from - 1 or #line
        local gap = string.sub(line, spans[i].to + 1, stop)
        return (string.gsub(gap, "[^%.,;!%?]", ""))
    end
    local function Piece(effect, sep)
        local piece = effect.text
        if effect.hidden then
            piece = "{" .. piece .. "}"
        end
        return piece .. sep
    end
    for i, span in ipairs(spans) do
        local effect = span.effect
        if EncounterScript.EffectIsMechanical(effect) then
            local copy = {}
            for k, v in pairs(effect) do
                copy[k] = v
            end
            copy.hidden = effect.hidden == true
            copy.sep = Sep(i)
            if #pending > 0 then
                copy.prefix = table.concat(pending, " ") .. " "
                pending = {}
            end
            effects[#effects + 1] = copy
        elseif #effects == 0 then
            lead[#lead + 1] = Piece(effect, Sep(i))
        else
            pending[#pending + 1] = Piece(effect, Sep(i))
        end
    end
    if #pending > 0 then
        effects[#effects].suffix = table.concat(pending, " ")
    end
    return { text = trim(table.concat(lead, " ")), effects = effects }
end

--The clause an effect row writes: its own words when untouched, else the
--catalogue's; braced when hidden from the players (unless `bare`).
function E.EffectClauseText(effect, bare)
    local clause = effect.text
    if clause == nil or clause == "" then
        clause = EncounterScript.ClauseText(effect) or ""
    end
    clause = E.LineText(string.gsub(clause, "[{}]", ""))
    if effect.hidden and not bare and clause ~= "" then
        clause = "{" .. clause .. "}"
    end
    return clause
end

--{ text, effects } -> the tier text (no "|" or teaser): the free text, then
--each effect as its own sentence (with any flavour glued to it). Hidden
--effects next to each other share one pair of braces, as authors write
--them ("{Unlock X. Bane on Y}").
function E.OutcomeText(outcome)
    local text = E.LineText(outcome.text)
    local effects = {}
    for _, effect in ipairs(outcome.effects or {}) do
        if E.EffectClauseText(effect) ~= "" then
            effects[#effects + 1] = effect
        end
    end
    local parts = {}
    if text ~= "" then
        if #effects > 0 and not string.match(text, "[%.,;!%?]$") then
            text = text .. "."
        end
        parts[#parts + 1] = text
    end
    local function Stop(piece)
        if string.match(piece, "[%.,;!%?]$") then
            return piece
        end
        return piece .. "."
    end
    local i = 1
    while i <= #effects do
        local first = effects[i]
        --the run of effects written as one piece: hidden ones with nothing
        --written between them share braces.
        local last = i
        if first.hidden then
            while effects[last + 1] ~= nil and effects[last + 1].hidden
                and E.LineText(effects[last].suffix or "") == "" and E.LineText(effects[last + 1].prefix or "") == "" do
                last = last + 1
            end
        end
        local piece = E.LineText(first.prefix or "")
        if piece ~= "" then
            piece = piece .. " "
        end
        if first.hidden then
            local inner = {}
            for m = i, last do
                local clause = E.EffectClauseText(effects[m], true)
                if m < last then
                    clause = Stop(clause .. (effects[m].sep or ""))
                end
                inner[#inner + 1] = clause
            end
            piece = piece .. "{" .. table.concat(inner, " ") .. "}"
        else
            piece = piece .. E.EffectClauseText(first)
        end
        local lastEffect = effects[last]
        piece = piece .. (lastEffect.sep or "")
        local suffix = E.LineText(lastEffect.suffix or "")
        if suffix ~= "" then
            if not string.match(piece, "[%.,;!%?]$") then
                piece = piece .. ","
            end
            piece = piece .. " " .. suffix
        end
        --the next sentence needs a stop in front of it.
        if last < #effects then
            piece = Stop(piece)
        end
        parts[#parts + 1] = piece
        i = last + 1
    end
    return table.concat(parts, " ")
end

--- the script builder: beats, narratives and the encounter -------------------------

--"trap" -> "Trap".
local function Cap(s)
    s = trim(tostring(s or ""))
    return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

--"A", "A and B", "A, B and C".
local function JoinAnd(list)
    if #list <= 1 then
        return list[1] or ""
    end
    local head = {}
    for i = 1, #list - 1 do
        head[i] = list[i]
    end
    return table.concat(head, ", ") .. " and " .. list[#list]
end

--A setup line of the "# Encounter" beat, from the parser's instruction
--table (kind "placeobjects", "bystanders" or "victory"; `label` is the
--word before the colon).
function E.SetupLine(ins)
    if ins.kind == "victory" then
        local who = "enemy"
        if ins.who ~= nil and ins.who ~= "" then
            who = E.LineText(ins.whoText or ins.who)
        end
        return string.format("Victory: every %s on the map is defeated", who)
    elseif ins.kind == "bystanders" then
        local names = {}
        for _, n in ipairs(ins.names or {}) do
            n = E.LineText(n)
            if n ~= "" then
                names[#names + 1] = n
            end
        end
        return string.format("%s: %s tokens stay out of initiative", E.LineText(ins.label or "Bystanders"), JoinAnd(names))
    end
    local qty = tonumber(ins.qty) or 1
    local zone = Cap(ins.zone)
    local line = string.format("%s: Place %d %s %s in %s zones", E.LineText(ins.label or "Setup"), qty, E.LineText(ins.object),
        qty == 1 and "object" or "objects", zone)
    if ins.deleteOthers then
        line = line .. string.format(" and delete the other %s zones", zone)
    end
    return line
end

--The lines of a "## Reinforcements: <Name>" section.
function E.ArriveLine(schedule)
    return "Arrive: " .. EncounterScript.DescribeSchedule(schedule)
end

function E.EnterLine(zone)
    return string.format("Enter: the %s zone", Cap(zone))
end

function E.ShoutLine(text)
    return string.format("Shout: \"%s\"", (string.gsub(E.LineText(text), "\"", "'")))
end

--A narrative section's mode marker: "Choose together: Which way?".
function E.NarrativeModeLine(mode, prompt)
    local head = mode == "individual" and "Choose individually:" or "Choose together:"
    prompt = E.LineText(prompt)
    if prompt == "" then
        return head
    end
    return head .. " " .. prompt
end

function E.UnlockLine(featureName)
    return "Unlock: " .. E.LineText(featureName)
end

--Starter blocks for new beats and sections.
function E.NarrativeBeatBlock()
    return { "# Narrative", "", T("author.script_edit.starter.narrative.intro"), "",
        "## " .. T("author.script_edit.starter.narrative.section"), "", T("author.script_edit.starter.narrative.section_text"), "",
        "Choose together: " .. T("author.script_edit.starter.narrative.prompt"), "",
        "### " .. T("author.script_edit.starter.narrative.option1"), "", T("author.script_edit.starter.narrative.option1_text"), "", "|+1 hero token", "",
        "### " .. T("author.script_edit.starter.narrative.option2"), "", T("author.script_edit.starter.narrative.option2_text") }
end

function E.MontageBeatBlock()
    return { "# Montage", "", T("author.script_edit.starter.montage.intro"), "", "## Round 1" }
end

function E.EncounterBeatBlock()
    return { "# Encounter", "", "[[encounter]]" }
end

function E.StoryBlock(title, text)
    return { "# " .. E.LineText(title), "", E.LineText(text) }
end

function E.NarrativeSectionBlock(name)
    return { "## " .. E.LineText(name), "", T("author.script_edit.starter.section.text"), "",
        "Choose together: " .. T("author.script_edit.starter.section.prompt"), "",
        "### " .. T("author.script_edit.starter.section.option1"), "", "### " .. T("author.script_edit.starter.section.option2") }
end

function E.ReinforcementBlock(name)
    return { "## Reinforcements: " .. E.LineText(name), "", "Arrive: Round 3", "", "[[encounter]]" }
end

--- keeping [[tag]] islands on their data -------------------------------------------
--
--A journal document binds each [[tag]] to its saved data by order: the
--first [[scene]] is key "scene", the second "scene-1", and so on
--(MarkdownDocument:GetReferencedAnnotations). Moving or deleting a block
--that holds a tag would shift every later tag of that name onto the wrong
--data -- a beat's backdrop swapping with another's. These helpers track
--each tag through an edit so the caller can move its data to its new key.

--Every [[tag]] in `lines`, in order: { { line, name (the full text inside
--the brackets), key }, ... }.
function E.TagOccurrences(lines)
    local result = {}
    local seen = {}
    for i, l in ipairs(lines) do
        for name in string.gmatch(l, "%[%[(.-)%]%]") do
            local key = name
            local index = 1
            while seen[key] do
                key = name .. "-" .. index
                index = index + 1
            end
            seen[key] = true
            result[#result + 1] = { line = i, name = name, key = key }
        end
    end
    return result
end

--The old line -> new line map of a set of patches on ONE document (lines a
--patch replaced map to nil).
function E.PatchLineMap(lineCount, patches)
    local map = {}
    for l = 1, lineCount do
        ---@type integer|nil
        local new = l
        for _, p in ipairs(patches) do
            if l >= p.first and l <= p.last then
                new = nil
                break
            end
            if p.last < l then
                new = new + #p.lines - (p.last - p.first + 1)
            end
        end
        map[l] = new
    end
    return map
end

--Swap two blocks of lines a1..a2 and b1..b2 (a2 < b1), keeping the lines
--between them where they are. Returns the new lines and the line map.
function E.SwapBlocks(lines, a1, a2, b1, b2)
    local out, map = {}, {}
    local function Take(from, to)
        for l = from, to do
            out[#out + 1] = lines[l]
            map[l] = #out
        end
    end
    Take(1, a1 - 1)
    Take(b1, b2)
    Take(a2 + 1, b1 - 1)
    Take(a1, a2)
    Take(b2 + 1, #lines)
    return out, map
end

--How the tags' keys change between `oldLines` and `newLines` given the
--line map. A tag on a line that survived keeps its identity; a tag on a new
--line takes the identity of a removed tag of the same name, in order (a
--block moved as delete + insert). Returns { [oldKey] = newKey } for every
--tag that survived, and the list of old keys whose tag is gone.
function E.RekeyTags(oldLines, newLines, map)
    local old = E.TagOccurrences(oldLines)
    local new = E.TagOccurrences(newLines)
    local newByLine = {}
    for _, o in ipairs(new) do
        newByLine[o.line] = newByLine[o.line] or {}
        table.insert(newByLine[o.line], o)
    end
    local claimed = {}
    local remap = {}
    local unmatched = {}
    for _, o in ipairs(old) do
        local target = map[o.line]
        local found = nil
        for _, n in ipairs(target ~= nil and newByLine[target] or {}) do
            if not claimed[n] and n.name == o.name then
                found = n
                break
            end
        end
        if found ~= nil then
            claimed[found] = true
            remap[o.key] = found.key
        else
            unmatched[#unmatched + 1] = o
        end
    end
    local gone = {}
    for _, o in ipairs(unmatched) do
        local found = nil
        for _, n in ipairs(new) do
            if not claimed[n] and n.name == o.name then
                found = n
                break
            end
        end
        if found ~= nil then
            claimed[found] = true
            remap[o.key] = found.key
        else
            gone[#gone + 1] = o.key
        end
    end
    return remap, gone
end

--Does a remap change anything?
function E.RekeyChanges(remap, gone)
    if #(gone or {}) > 0 then
        return true
    end
    for k, v in pairs(remap or {}) do
        if k ~= v then
            return true
        end
    end
    return false
end
