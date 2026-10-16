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
            return nil, "that place is not in any document"
        end
        return E.Patch(docid, a, a - 1, lines)
    end
    local docid, a, b = E.SourceRange(parse, first, last)
    if docid == nil then
        return nil, "that text spans more than one document"
    end
    return E.Patch(docid, a, b, lines)
end

--Insert lines after expanded line `after`: in the document `after` came
--from, right below it (an insertion at the end of a sub-document stays in
--that sub-document, which inserting before the next expanded line would not).
function E.PatchAfter(parse, after, lines)
    local docid, a = E.Source(parse, after)
    if docid == nil then
        return nil, "that place is not in any document"
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
            return "a line starts with '#', which would start a new heading"
        elseif string.match(line, "^|") then
            return "a line starts with '|', which is a rules line"
        elseif string.match(line, "^%-%-%-+$") then
            return "a '---' line would start a scene"
        elseif string.match(line, "^%[%[.+%]%]$") then
            return "a [[tag]] line"
        elseif string.match(string.lower(line), "^consequences?:") or string.match(string.lower(line), "^options?:") then
            return "a line starting 'Consequence:' or 'Options:' means something else"
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

--table = { name, dice = "1d6", rows = { {lo, hi, text} } }
function E.TableLines(t)
    local name = string.gsub(E.LineText(t.name), ":", "")
    local lines = { string.format("|%s: %s", trim(name), E.LineText(t.dice or "1d6")) }
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
        return nil, "that place is not in any document"
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
        return nil, "that element is not in any document"
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
    return nil, string.format("tier %d has no line to write", t)
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
            return nil, "this option has rider lines outside its roll block; edit it as text"
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
            return nil, "these rules are split up; edit them as text"
        end
    end
    return One(E.PatchExpanded(parse, first, last, block))
end

--Append a whole element block (entry, option, knack) after the element
--headed at expanded line `line` of that level, in the same document.
function E.InsertAfterElement(parse, docTexts, line, level, block)
    local docid, _, last = E.ElementRange(parse, docTexts, line, level)
    if docid == nil then
        return nil, "that element is not in any document"
    end
    local lines = E.Split(docTexts[docid]).lines
    return { E.Patch(docid, last + 1, last, Padded(lines, last, block)) }
end

--Delete the element headed at expanded line `line` (with the blank lines
--that followed it, so no gap is left behind).
function E.DeleteElement(parse, docTexts, line, level)
    local docid, first, last = E.ElementRange(parse, docTexts, line, level)
    if docid == nil then
        return nil, "that element is not in any document"
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
