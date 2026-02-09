local mod = dmhub.GetModLoading()

---@class MarkdownDocument:CustomDocument
MarkdownDocument = RegisterGameType("MarkdownDocument", "CustomDocument")
MarkdownDocument.vscroll = false

local g_markdownStyle = gui.MarkdownStyle {
    ["#  "] = "<size=200%><b>", ["/#  "] = "</b></size>",
    ["# "] = "<size=200%><b>", ["/# "] = "</b></size>",
    ["## "] = "<size=180%><b>", ["/## "] = "</b></size>",
    ["### "] = "<size=160%><b>", ["/### "] = "</b></size>",
    ["#### "] = "<size=140%><b>", ["/#### "] = "</b></size>",
    ["##### "] = "<size=120%><b>", ["/##### "] = "</b></size>",
}

---@class RichTag
---@field pattern false|string
RichTag = RegisterGameType("RichTag")
RichTag.pattern = false
RichTag.hasEdit = true

function RichTag.Create()
    return RichTag.new {}
end

function RichTag:GetDocument()
    return self:try_get("_tmp_document")
end

function RichTag:UploadDocument()
    if self:has_key("_tmp_document") then
        self._tmp_document:Upload()
    end
end

function RichTag.CreateDisplay(self)
    return gui.Panel {
        width = 10,
        height = 10,
    }
end

function RichTag.CreateEditor(self)
    return gui.Panel {
        width = 1,
        height = 1,
    }
end

function RichTag.GetColorFromToken(token)
    if token.stylingInfo ~= nil and token.stylingInfo.colorStack ~= nil and #token.stylingInfo.colorStack > 0 then
        return token.stylingInfo.colorStack[#token.stylingInfo.colorStack]
    end

    return nil
end

--- @type table<string, RichTag>
MarkdownDocument.RichTagRegistry = {}

--- @param info RichTag
function MarkdownDocument.RegisterRichTag(info)
    MarkdownDocument.RichTagRegistry[info.tag] = info
end

local function StripSpoilers(text)
    local result = ""
    local i, depth = 1, 0
    local markDepth = 0
    local markEnd = nil

    while true do
        local a, b, brace = text:find("([{}])", i)
        if not a then
            if depth == 0 then
                result = result .. text:sub(i)
            end
            break
        end

        if depth == 0 and a > i then
            result = result .. text:sub(i, a - 1)
        end

        if brace == "{" then
            if text:sub(a + 1, a + 1) == "!" and depth == 0 then
                markDepth = markDepth + 1
                b = b + 1
            elseif text:sub(a + 1, a + 1) == "#" and depth == 0 then
                if markDepth == 0 then
                    result = result .. "<alpha=#FF><mark=#ffffff><color=#ffffff>"
                    markEnd = "</color></mark>"
                end
                markDepth = markDepth + 1
                b = b + 1
            elseif text:sub(a + 1, a + 1) == ":" and depth == 0 then
                --start of a language.
                local x, y = text:find(":", a + 2)
                if x ~= nil then
                    b = y

                    markDepth = markDepth + 1
                    local langName = string.lower(text:sub(a + 2, x - 1))
                    local languages = dmhub.GetTable(Language.tableName) or {}
                    local bestScore = 0
                    local bestLanguage = nil
                    for langid, language in pairs(languages) do
                        local score = nil
                        local namelc = string.lower(language.name)
                        if namelc == langName then
                            score = 3
                        elseif string.starts_with(namelc, langName) then
                            score = 2
                        else
                            local speakerlc = string.lower(language.speakers)
                            if speakerlc == langName then
                                score = 1
                            elseif string.starts_with(speakerlc, langName) then
                                score = 0.5
                            elseif string.find(speakerlc, langName) ~= nil then
                                score = 0.3
                            end
                        end

                        if score ~= nil and score > bestScore then
                            bestScore = score
                            bestLanguage = language
                        end
                    end

                    if bestLanguage ~= nil then
                        result = result .. string.format("(in %s) ", bestLanguage.name)
                    end

                    local canSpeak = false
                    if not dmhub.isDM then
                        local token = dmhub.currentToken
                        if token ~= nil and token.properties:LanguagesKnown()[bestLanguage.id] then
                            canSpeak = true
                        end
                    end

                    if markDepth == 1 and not canSpeak then
                        --TODO: get fonts working.
                        result = result .. "<alpha=#FF><mark=#ffffff><color=#ffffff>"
                        markEnd = "</color></mark>"
                        --result = result .. "<font=\"Tengwar\">"
                        --markEnd = "</font>"
                    end
                end
            else
                depth = depth + 1
            end
        else --brace == "}"
            if depth > 0 then
                depth = depth - 1
            elseif markDepth > 0 then
                markDepth = markDepth - 1
                if markDepth == 0 and markEnd ~= nil then
                    result = result .. markEnd
                    markEnd = nil
                end
            end
        end
        i = b + 1
    end

    return result
end

local g_hardwiredPowerTableList = {
    { preset = "|easy", tiers = {"You succeed on the task and incur a consequence.", "You succeed on the task.", "You succeed on the task with a reward."}, },
    { preset = "|medium", tiers = {"You fail the task.", "You succeed on the task and incur a consequence.", "You succeed on the task."}, },
    { preset = "|hard", tiers = {"You fail the task and incur a consequence.", "You fail the task.", "You succeed on the task."}, },
}

local g_hardwiredPowerTables = {}

for _,info in ipairs(g_hardwiredPowerTableList) do
    g_hardwiredPowerTables[info.preset] = info.tiers
end

local BreakdownRichTags
BreakdownRichTags = function(content, result, options, extraOutput)
    extraOutput = extraOutput or {}
    options = options or {}
    local isPlayer = options.player

    if isPlayer then
        content = StripSpoilers(content)
    end

    local stylingInfo = options.stylingInfo or { colorStack = {} }

    local collapseNodes = {}

    result = result or {}
    content = content:gsub("\v", "\n") --replace vertical tabs with newlines.
    content = content:gsub("\r", "")
    local lines = string.split_allow_duplicates(content, '\n')

    local text = ""

    local EmitText = function(t, justification)
        if t == nil then
            t = text
            text = ""
        end
        if t ~= "" then
            local searchColorStr = t
            local pattern = '^[^\\0]*?(</color>|<color="?(?<color>.*?)"?>)(?<suffix>[^\\0]*)$'
            local matchColor = regex.MatchGroups(searchColorStr, pattern)
            while matchColor ~= nil do
                if matchColor.color ~= nil then
                    local color = matchColor.color
                    stylingInfo.colorStack[#stylingInfo.colorStack + 1] = color
                else
                    if #stylingInfo.colorStack > 0 then
                        stylingInfo.colorStack[#stylingInfo.colorStack] = nil
                    end
                end

                searchColorStr = matchColor.suffix
                matchColor = regex.MatchGroups(searchColorStr, pattern)
            end

            result[#result + 1] = {
                type = "text",
                text = t,
                justification = justification,
                player = isPlayer,
                --trace = debug.traceback(),
            }
        end
    end

    local parsingRollableTable = false

    local skipLines = 0

    for i, line in ipairs(lines) do
        local currentIndent = ""
        local skipping = false
        local str = line

        if skipLines <= 0 then
            local conditional = regex.MatchGroups(str, "^ *\\?\\?\\?(?<condition>.*)$")
            if conditional ~= nil and trim(conditional.condition) == "" then
                skipLines = 1
            elseif conditional ~= nil then
                local query = trim(conditional.condition)
                local result = dmhub.Execute(query)
                if result == nil then
                    result = false
                end
                local queries = extraOutput.queries or {}
                extraOutput.queries = queries
                queries[query] = result
                if tonumber(result) == 0 or result == "" or result == false then
                    local ndeep = 1

                    local nskip = 1

                    for j=i+1,#lines do
                        local line = lines[j]
                        local s = line
                        local m = regex.MatchGroups(s, "^ *\\?\\?\\?(?<condition>.*)$")
                        if m ~= nil then
                            if trim(m.condition) == "" then
                                ndeep = ndeep - 1
                            else
                                ndeep = ndeep + 1
                            end
                        end
                        nskip = nskip + 1
                        if ndeep == 0 then
                            break
                        end
                    end

                    skipLines = nskip
                else
                    skipLines = 1
                end
            end
        end



        if skipLines > 0 then
            skipLines = skipLines - 1
            str = ""
            skipping = true
        end

        while #collapseNodes > 0 do
            local indent = string.rep(" ", collapseNodes[#collapseNodes])
            if string.starts_with(str, indent) then
                str = str:sub(#indent + 1)
                currentIndent = indent
                break
            else
                EmitText()

                result[#result + 1] = {
                    type = "end_collapse_node",
                    player = isPlayer,
                    text = "",
                }

                collapseNodes[#collapseNodes] = nil
            end
        end

        local blockquoteMatch = regex.MatchGroups(str, "^> *(?<text>.*)$")
        if blockquoteMatch ~= nil then
            EmitText()
            local additionalLines = 0
            for j=i+1,#lines do
                if regex.MatchGroups(lines[j], "^> *(?<text>.*)$") ~= nil then
                    additionalLines = additionalLines + 1
                else
                    break
                end
            end

            local blockLines = {}
            for j=0,additionalLines do
                local match = regex.MatchGroups(lines[i + j], "^> *(?<text>.*)$")
                if match ~= nil then
                    blockLines[#blockLines + 1] = match.text
                else
                    break
                end
            end

            result[#result+1] = {
                type = "blockquote",
                text = table.concat(blockLines, "\n"),
                player = isPlayer,
            }

            skipping = true
            skipLines = additionalLines
            str = ""
        end

        local rollableTableHeaderMatch = regex.MatchGroups(str, "^\\|(?<name>[^:]+): *(?<dice>[0-9]+d[0-9]+) *$")
        if rollableTableHeaderMatch ~= nil and lines[i + 1] ~= nil and string.starts_with(lines[i + 1], "|") then
            EmitText()

            result[#result + 1] = {
                type = "rollable_table",
                name = rollableTableHeaderMatch.name,
                dice = rollableTableHeaderMatch.dice,
                player = isPlayer,
            }

            str = ""
            parsingRollableTable = true
        end

        local powerRollMatch = (not parsingRollableTable) and
        regex.MatchGroups(str, "^\\|(?<name>[^|]+): (?<attr>[^|]+)$")
        if powerRollMatch and lines[i+2] then
            local tiers = {}
            local hasMatch = true
            local nextLine = string.lower(trim(lines[i+1]))
            for j = 1, 3 do
                local match = lines[i + j] and
                regex.MatchGroups(lines[i + j], "^" .. currentIndent .. "\\|(?<text>[^|]*)$")
                if match == nil then
                    hasMatch = false
                    break
                end

                tiers[#tiers + 1] = match.text
            end

            if hasMatch then
                EmitText()

                result[#result + 1] = {
                    type = "power_roll",
                    name = powerRollMatch.name,
                    attr = powerRollMatch.attr,
                    tiers = tiers,
                    player = isPlayer,
                }
                skipLines = 3
                str = ""
            elseif g_hardwiredPowerTables[nextLine] then
                EmitText()
                skipLines = 1
                result[#result+1] = {
                    type = "power_roll",
                    name = powerRollMatch.name,
                    attr = powerRollMatch.attr,
                    tiers = g_hardwiredPowerTables[nextLine],
                    preset = nextLine,
                    lines = options.linesContext or lines,
                    lineIndex = options.lineIndexContext or i,
                    player = isPlayer,
                }
                str = ""
            end
        end

        local tableMatch = regex.MatchGroups(str, "^\\|(?<row>.*)(?<suffix>\\| *)$")

        --when parsing a rollable table we can be a little more generous with the match.
        if rollableTableHeaderMatch == nil and tableMatch == nil and parsingRollableTable then
            tableMatch = regex.MatchGroups(str, "^\\|(?<row>.*)$")
            if tableMatch == nil then
                parsingRollableTable = false
            end
        end

        if tableMatch ~= nil then
            EmitText()

            result[#result + 1] = {
                type = "row",
                player = isPlayer,
            }

            local linePrefix = "|"

            local cells = string.split_with_square_brackets(tableMatch.row, "|")
            for j, cell in ipairs(cells) do
                result[#result + 1] = {
                    type = "cell",
                    player = isPlayer,
                }
                BreakdownRichTags(cell, result, {
                    player = options.player,
                    linePrefix = linePrefix,
                    linesContext = lines,
                    lineIndexContext = i,
                    stylingInfo = stylingInfo,
                }, extraOutput)

                linePrefix = linePrefix .. cell .. "|"
            end

            result[#result + 1] = {
                type = "end_row",
                player = isPlayer,
            }

            str = ""
        end

        if tableMatch == nil and i ~= 1 and not skipping then
            text = text .. "\n"
        end

        if #lines > 1 and regex.MatchGroups(str, "^(---+|___+)$") ~= nil then
            EmitText()
            result[#result + 1] = {
                type = "divider",
                player = isPlayer,
            }
            str = ""
        end

        local collapseNodeMatch = regex.MatchGroups(str, "^\\+ (?<title>['\"a-zA-Z0-9-_ ]+)$")
        if collapseNodeMatch ~= nil and lines[i + 1] ~= nil then
            local leading = string.match(lines[i + 1], "^(%s*)")
            if #leading > 0 then
                EmitText()
                result[#result + 1] = {
                    type = "collapse_node",
                    title = collapseNodeMatch.title,
                    text = str,
                    player = isPlayer,
                }
                collapseNodes[#collapseNodes + 1] = #leading
                str = ""
            end
        end

        local justification = nil

        while str ~= "" do
            local match = regex.MatchGroups(str,
                "^(?<prefix>.*?)((?<spoiler>\\{)|(?<justification>:(<>|><|<|>))|(?<embed>\\[:[^\\[\\]]+\\])|(?<tag>\\[[ xX]\\] *(?<checkname>[a-zA-Z0-9 ]*))|\\[\\[(?<tag>[^\\]]*)\\]\\])(?<suffix>.*)$")
            if match == nil then
                text = text .. str
                if str ~= line:sub(#currentIndent + 1) and text ~= "" then
                    --we have emitted rich content this line, so emit this string now.
                    EmitText(nil, justification)
                end

                break
            end

            EmitText(nil, justification)

            if match.prefix ~= "" then
                EmitText(match.prefix, justification)
            end

            if match.spoiler ~= nil then

                if not isPlayer then

                    local linepos = (#line - #str) + #match.prefix

                    local suffix = match.suffix
                    local firstChar = suffix:sub(1,1)
                    local spoilerText = "Reveal to Players"
                    if firstChar == "!" then
                        spoilerText = "Hide from Players"
                    end

                    local spoilerInfo = extraOutput.spoilers or {}
                    extraOutput.spoilers = spoilerInfo

                    local guid = dmhub.GenerateGuid()

                    spoilerInfo[guid] = {
                        lines = options.linesContext or lines,
                        lineIndex = options.lineIndexContext or i,
                        linepos = linepos,
                    }

                    print("SPOILER: ADD spoiler", guid)

                    text = text .. string.format("<color=#00FFFF><size=70%%><link=spoiler:%s>%s</link></size></color>", guid, spoilerText)
                end

                text = text .. "{"
            elseif match.justification ~= nil then
                result[#result + 1] = {
                    type = "justification",
                    text = match.justification,
                    player = isPlayer,
                }

                if match.justification == ":<" then
                    justification = "left"
                elseif match.justification == ":>" then
                    justification = "right"
                else
                    justification = "center"
                end
            elseif match.embed ~= nil then
                result[#result + 1] = {
                    type = "embed",
                    text = match.embed,
                    justification = justification,
                    player = isPlayer,
                }
            else
                local linepos = (#line - #str) + #match.prefix
                local len = #line - (#match.prefix + #match.suffix)

                if options.linePrefix then
                    linepos = linepos + #options.linePrefix
                end

                local guid = dmhub.GenerateGuid()
                result[#result + 1] = {
                    guid = guid,
                    type = "tag",
                    text = match.tag,
                    justification = justification,

                    stylingInfo = DeepCopy(stylingInfo),

                    player = isPlayer,

                    --the lines this comes from.
                    lines = options.linesContext or lines,
                    lineIndex = options.lineIndexContext or i,
                    linepos = linepos,
                    length = len,
                }
            end

            str = match.suffix
        end

        if justification ~= nil then
            --EmitText(nil, justification)
        end
    end

    EmitText()

    while #collapseNodes > 0 do
        result[#result + 1] = {
            type = "end_collapse_node",
            text = "",
            player = isPlayer,
        }

        collapseNodes[#collapseNodes] = nil
    end

    return result
end

function MarkdownDocument:PatchToken(token, str)
    local lines = table.shallow_copy(token.lines)
    local line = token.lines[token.lineIndex]
    lines[token.lineIndex] = line:sub(1, token.linepos) .. str .. line:sub(token.linepos + token.length + 1)
    self:SetTextContent(table.concat(lines, "\n"))
end

function MarkdownDocument:GetRollableTableFromTokens(tableid, tokens, startPos)
    --look for the first "row" token within three spaces, otherwise we give up.
    local found = false
    for i=1,3 do
        if tokens[startPos+i] ~= nil and tokens[startPos+i].type == "row" then
            startPos = startPos + i
            found = true
            break
        end
    end

    if not found then
        return false
    end

    local t = RollTable.CreateNew()

    local currentRow = {}
    local processingRow = false

    local TryAddRow = function()
        if #currentRow > 0 then

            local value = VariantCollection.Create()
            for j,cell in ipairs(currentRow) do
                value:Add(Variant.CreateText(cell))
            end
            local row = RollTableRow.new{
                id = self.id .. "-" .. tableid .. "-" .. string.format("%d", #t.rows),
                value = value,
            }

            t.rows[#t.rows+1] = row

            currentRow = {}
        end
    end

    for i=startPos,#tokens do
        local token = tokens[i]
        if token.type == "row" then
            TryAddRow()
            processingRow = true
        elseif token.type == "end_row" then
            TryAddRow()
            processingRow = false
        elseif token.type == "text" then
            if not processingRow then
                break
            end

            currentRow[#currentRow+1] = token.text
        end
    end

    TryAddRow()

    return t
end

function MarkdownDocument:GetRollableTable(tableid)
    local rollableTablesByName = {}
    local tokens = BreakdownRichTags(self:GetTextContent(), nil, {})
    for i,token in ipairs(tokens) do
        if token.type == "rollable_table" then
            local tableName = token.name
            local count = rollableTablesByName[tableName] or 0
            rollableTablesByName[tableName] = count + 1
            if count > 0 then
                tableName = string.format("%s|%d", tableName, count)
            end

            if tableName == tableid then
                local result = self:GetRollableTableFromTokens(tableid, tokens, i)
                if result ~= nil then
                    result.text = true
                    result.name = token.name

                    for _,rollType in ipairs(RollTable.RollTypes) do
                        if rollType.id == token.dice or rollType.text == token.dice then
                            result.rollType = rollType.id
                            break
                        end
                    end

                    if result.rollType == "auto" then
                        result.customRoll = token.dice
                    end
                end
                return result
            end
        end
    end

    return nil
end

local function TierRoll(n)
    return gui.Panel {
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "horizontal",
        gui.Label {
            width = CustomDocument.ScaleFontSize(60),
            height = CustomDocument.ScaleFontSize(30),
            textAlignment = "center",
            fontFace = "DrawSteelGlyphs",
            text = string.format("%d", n),
            fontSize = CustomDocument.ScaleFontSize(36),
            valign = "top",
        },

        gui.Label {
            id = string.format("tier_%d", n),
            debugLogging = (n == 1),
            width = "100%-60",
            height = "auto",
            textAlignment = "topleft",
            fontSize = CustomDocument.ScaleFontSize(16),
            vmargin = 0,
            vpad = 0,
            markdown = true,
            markdownStyle = g_markdownStyle,
            refreshPowerRoll = function(element, info)
                element.text = info.tiers[n] or ""
            end,
        },
    }
end

local g_linkStyles = {
    gui.Style {
        color = "white",
    },
    gui.Style {
        selectors = { "hover" },
        color = "#FFD700",
    },
}

local function PowerRollDisplay(doc)
    local resultPanel

    local m_token = nil
    local m_info = nil

    resultPanel = gui.Panel {
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",

        gui.Panel{
            height = "auto",
            width = "auto",
            flow = "horizontal",
            halign = "left",
            gui.Label {
                styles = g_linkStyles,
                halign = "left",
                refreshPowerRoll = function(element, info)
                    m_info = info
                    element.text = string.format("%s: %s", info.name, info.attr)
                end,
                press = function(element)
                    local attr = string.lower(m_info.attr)
                    local characteristics = {}
                    for attrid, attrInfo in pairs(creature.attributesInfo) do
                        if string.find(attr, string.lower(attrInfo.description)) then
                            characteristics[attrid] = true
                        end
                    end

                    local skills = {}
                    local skillsList = Skill.skillsDropdownOptions
                    for _, skillInfo in ipairs(skillsList) do
                        if string.find(attr, string.lower(skillInfo.text)) ~= nil then
                            skills[#skills + 1] = skillInfo.id
                        end
                    end

                    if not doc:IsPlayerView(element) then
                        LaunchablePanel.LaunchPanelByName("Request Rolls", {
                            title = string.format("%s: %s", m_info.name, m_info.attr),
                            powerRollTable = PowerRollTable.Create {
                                tiers = m_info.tiers,
                            },
                            characteristics = characteristics,
                            skills = skills,
                        })
                    else
                        local token = dmhub.currentToken
                        if token ~= nil then
                            token.properties:RollCustomPowerTableTest(string.format("%s: %s", m_info.name, m_info.attr),
                                characteristics, skills, m_info.tiers)
                        end
                    end
                end,
                bold = true,
                fontSize = CustomDocument.ScaleFontSize(18),
            },

            gui.Label{
                styles = g_linkStyles,
                lmargin = 8,
                fontSize = 16,
                width = 120,
                height = 18,
                valign = "center",
                text = "",
                refreshPowerRoll = function(element, token)
                    if token.preset == nil then
                        element:SetClass("collapsed", true)
                        return
                    end

                    print("INFO::", token)
                    element.data.token = token
                    element:SetClass("collapsed", false)
                    element.text = string.sub(token.preset, 2)
                end,

                press = function(element)
                    local token = element.data.token
                    if token == nil then
                        return
                    end

                    local nextIndex = 1
                    for i=1,#g_hardwiredPowerTableList do
                        local info = g_hardwiredPowerTableList[i]
                        if info.preset == token.preset then
                            nextIndex = i+1
                            if nextIndex > #g_hardwiredPowerTableList then
                                nextIndex = 1
                            end
                            break
                        end
                    end

                    local lines = table.shallow_copy(token.lines)
                    lines[token.lineIndex+1] = g_hardwiredPowerTableList[nextIndex].preset
                    doc:SetTextContent(table.concat(lines, "\n"))
                    doc:Upload()
                end,
            },
        },

        TierRoll(1),
        TierRoll(2),
        TierRoll(3),
    }

    return resultPanel
end

local function CreateTreeNodePanel()
    local resultPanel

    local bodyPanel = gui.Panel {
        flow = "vertical",
        width = "100%-8",
        height = "auto",
        halign = "right",
        valign = "top",
        refreshTreeChildren = function(element, children)
            element.children = children
            element:HaltEventPropagation()
        end,
    }

    local headerPanel = gui.Panel {
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "left",
        gui.Panel {
            classes = { "expanded" },
            styles = gui.TriangleStyles,
            bgimage = "panels/triangle.png",
            press = function(element)
                element:SetClass("expanded", not element:HasClass("expanded"))
                bodyPanel:SetClass("collapsed", not element:HasClass("expanded"))
            end,
        },
        gui.Label {
            refreshTreeNode = function(element, title)
                element.text = title
                element:HaltEventPropagation()
            end,
            fontSize = CustomDocument.ScaleFontSize(16),
            bold = true,
            width = "auto",
            height = "auto",
        },
    }

    resultPanel = gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        valign = "top",
        headerPanel,
        bodyPanel,
    }

    return resultPanel
end

--given text, will run it through our normal formatter.
function MarkdownDocument.FormatRichText(text, options)
    local result = ""
    local tokens = BreakdownRichTags(text, nil, options)
    for _, token in ipairs(tokens) do
        if token.type == "text" then
            result = result .. token.text
        end
    end

    return result
end

function MarkdownDocument.DisplayPanel(self, args)
    args = args or {}
    local embedDepth = args.embedDepth or 0
    args.embedDepth = nil

    --TODO: respect this parameter.
    local m_noninteractive = args.noninteractive or false
    args.noninteractive = nil

    local resultPanel

    local m_rollableTableRowLabels = {}
    local m_textPanels = {}
    local m_richPanels = {}
    local m_richRows = {}
    local m_rollableTables = {}
    local m_tables = {}
    local m_tableRows = {}
    local m_dividers = {}
    local m_powerTables = {}
    local m_embeds = {}
    local m_treeNodes = {}
    local m_blockquotes = {}
    local m_tokenExtraInfo = {}

    local params = {
        styles = {
            Styles.Table,
            gui.Style {
                selectors = { "checkbox-label" },
                width = "auto",
                height = "auto",
            },
            gui.Style {
                selectors = { "checkbox-label", "parent:uploading" },
                opacity = 0.5,
            },
            gui.Style {
                selectors = { "checkbox" },
                minWidth = 0,
            },
        },
        width = "100%-24",
        height = "100%",
        flow = "vertical",
        halign = "center",
        valign = "center",
        hpad = 6,
        vscroll = true,
        think = function(element)
            if element.data.queries == nil then
                return
            end

            for k,v in pairs(element.data.queries) do
                local result = dmhub.Execute(k)
                if result == nil then
                    result = false
                end

                if result ~= v then
                    element:FireEvent("refreshDocument")
                    break
                end
            end
        end,
        savedoc = function(element)
            element:FireEvent("refreshDocument")
        end,
        refreshDocument = function(element, doc)
            if doc ~= nil then
                self = doc
            end

            local children = {}
            local childrenStack = {} --stack used by collapse nodes.
            local treeNodeStack = {}
            local newRollableTables = {}
            local newTables = {}
            local newTableRows = {}
            local newRollableTableRowLabels = {}
            local newTextPanels = {}
            local newRichPanels = {}
            local newRichRows = {}
            local newPowerTables = {}
            local newEmbeds = {}
            local newTreeNodes = {}
            local newBlockquotes = {}
            local currentRichRow = nil

            local rollableTablesByName = {}

            local newDividers = {}

            local currentRollableTable = nil --the panel controlling the current rollable table.
            local currentTable = nil
            local currentTableRow = nil

            local tagsSeen = {}

            m_tokenExtraInfo = {}
            local tokens = BreakdownRichTags(self:GetTextContent(), nil, { player = self:IsPlayerView(element) }, m_tokenExtraInfo)

            if m_tokenExtraInfo.queries ~= nil then
                element.thinkTime = 0.2
                element.data.queries = m_tokenExtraInfo.queries
            else
                element.thinkTime = nil
                element.data.queries = nil
            end

            --print("BREAKDOWN::", tokens)
            for i, token in ipairs(tokens) do
                if token.type == "justification" then
                    --pass, nothing needed here.
                elseif token.type == "collapse_node" then
                    local panel = m_treeNodes[#newTreeNodes + 1] or CreateTreeNodePanel()
                    if m_treeNodes[#newTreeNodes + 1] ~= nil then
                        panel:Unparent()
                    end
                    children[#children + 1] = panel
                    newTreeNodes[#newTreeNodes + 1] = panel
                    childrenStack[#childrenStack + 1] = children
                    children = {}
                    treeNodeStack[#treeNodeStack + 1] = panel

                    panel:FireEventTree("refreshTreeNode", token.title or "")
                elseif token.type == "end_collapse_node" then
                    local panel = treeNodeStack[#treeNodeStack]
                    treeNodeStack[#treeNodeStack] = nil
                    panel:FireEventTree("refreshTreeChildren", children)
                    children = childrenStack[#childrenStack]
                    childrenStack[#childrenStack] = nil
                elseif token.type == "embed" then
                    local embed = trim(token.text:sub(3, -2))
                    local original = embed
                    local count = 0

                    while newEmbeds[embed] ~= nil and count < 8 do
                        count = count + 1
                        embed = string.format("%s|%d", original, count)
                    end

                    if m_embeds[embed] then
                        newEmbeds[embed] = m_embeds[embed]
                        newEmbeds[embed]:Unparent()
                    else
                        local doc = CustomDocument.ResolveLink(original)
                        if doc ~= nil then
                            print("EMBED:: CREATE", original)
                            newEmbeds[embed] = CustomDocument.CreateEmbeddablePanel(doc, { embedDepth = embedDepth }) or
                            false
                        else
                            newEmbeds[embed] = false
                        end
                    end

                    if newEmbeds[embed] ~= false then
                        children[#children + 1] = newEmbeds[embed]
                    end
                elseif token.type == "power_roll" then
                    currentRollableTable = nil
                    currentTable = nil
                    currentTableRow = nil
                    currentRichRow = nil

                    local panel = m_powerTables[#newPowerTables + 1] or PowerRollDisplay(self)
                    panel:FireEventTree("refreshPowerRoll", token)
                    newPowerTables[#newPowerTables + 1] = panel
                    children[#children + 1] = panel
                elseif token.type == "divider" then
                    currentRollableTable = nil
                    currentTable = nil
                    currentTableRow = nil
                    currentRichRow = nil

                    local divider = m_dividers[#newDividers + 1] or gui.Divider {
                        tmargin = 0,
                        bmargin = 0,
                        valign = "top",
                        width = "100%",
                    }
                    print("DIVIDER:: ADD")

                    newDividers[#newDividers + 1] = divider
                    children[#children + 1] = divider
                elseif token.type == "rollable_table" then
                    local tableName = token.name
                    local count = rollableTablesByName[tableName] or 0
                    rollableTablesByName[tableName] = count + 1
                    if count > 0 then
                        tableName = string.format("%s|%d", tableName, count)
                    end

                    local panel = m_rollableTables[tableName] or gui.Label {
                        styles = {
                            {
                                color = "#ffbbff",
                            },
                            {
                                selectors = { "hover" },
                                color = "#ff00ff",
                            },
                        },
                        data = {
                            rolls = {},
                            diceToRollId = {},

                        },
                        valign = "top",
                        bold = true,
                        fontSize = CustomDocument.ScaleFontSize(18),
                        width = "auto",
                        height = "auto",
                        halign = "left",
                        text = string.format("%s (Roll %s)", token.name, token.dice),
                        textAlignment = "left",

                        diceface = function(element, guid, num, timeRemaining)
                            local rollid = element.data.diceToRollId[guid]
                            if rollid ~= nil and element.data.rolls[rollid] ~= nil and element.data.rolls[rollid].totals[guid] ~= nil then
                                element.data.rolls[rollid].totals[guid] = num
                                local total = 0
                                for _,v in pairs(element.data.rolls[rollid].totals) do
                                    total = total + v
                                end

                                if element.data.rowList ~= nil then
                                    local n = 0
                                    for i,row in ipairs(element.data.rowList) do
                                        if row.data.range ~= nil and total >= row.data.range.min and total <= row.data.range.max then
                                            row:SetClassTree("highlight", true)
                                            n = i
                                        else
                                            row:SetClassTree("highlight", false)
                                        end
                                    end

                                    print("DICE ROLL:: HIGHLIGHT:", n, #element.data.rowList)
                                else
                                    print("DICE ROLL:: NO ROW LIST")
                                end

                            end
                        end,

                        create = function(element)
                            element.data.eventHandler = dmhub.RegisterEventHandler("DiceRoll", function(info)
                                if info.properties ~= nil and rawget(info.properties, "tableRef") then
                                    local rollid = dmhub.GenerateGuid()
                                    element.data.rolls[rollid] = {
                                        info = info,
                                        totals = {},
                                        table = info.properties.tableRef:GetTable(),
                                        bonus = info.total - info.naturalRoll,
                                        total = info.total,
                                    }
                                    local ref = rawget(info.properties, "tableRef")
                                    if ref.docid == self.id and ref.tableid == tableName then
                                        print("DICE ROLL:: BEGIN WITH TIME", info.timeRemaining)
                                        local rolls = info.rolls
                                        for i,roll in ipairs(rolls) do
                                            local events = chat.DiceEvents(roll.guid)
                                            events:Listen(element)
                                            element.data.diceToRollId[roll.guid] = rollid
                                            element.data.rolls[rollid].totals[roll.guid] = 0

                                            if roll.partnerguid ~= nil then
                                                local partnerEvents = chat.DiceEvents(roll.partnerguid)
                                                partnerEvents:Listen(element)
                                                element.data.diceToRollId[roll.partnerguid] = rollid
                                                element.data.rolls[rollid].totals[roll.partnerguid] = 0
                                            end
                                        end
                                    end
                                end
                            end)
                        end,

                        destroy = function(element)
                            if element.data.eventHandler ~= nil then
                                dmhub.DeregisterEventHandler(element.data.eventHandler)
                                element.data.eventHandler = nil
                            end
                        end,

                        press = function(element)

                            local ref = RollTableReference.CreateDocumentReference(self.id, tableName)
                            if not self:IsPlayerView(element) then
                                LaunchablePanel.LaunchPanelByName("Request Rolls", {
                                    title = token.name,
                                    checkType = "Table",
                                    check = RollCheck.new{
                                        type = "table",
                                        id = "custom",
                                        group = "custom",
                                        text = token.name,
                                        tableRef = ref,
                                        rollProperties = RollOnTableProperties.new{
                                            tableRef = ref,
                                        },
                                    }
                                    --characteristics = characteristics,
                                    --skills = skills,
                                })
                            else
                                local charToken = dmhub.selectedOrPrimaryTokens[1]
                                local rollArgs = {
                                    title = "Roll on Table",
                                    description = token.name,
                                    roll = token.dice,
                                    tableRef = ref,
                                    type = "table",
                                    creature = charToken and charToken.properties or nil,
                                    rollProperties = RollOnTableProperties.new{
                                        tableRef = ref,
                                    },
                                }

                                GameHud.instance.rollDialog.data.ShowDialog(rollArgs)
                            end
                        end,
                    }

                    panel.data.tableData = self:GetRollableTable(tableName)
                    panel.data.rollInfo = panel.data.tableData:CalculateRollInfo()
                    panel.data.table = nil
                    currentRollableTable = panel

                    if m_rollableTables[tableName] ~= nil then
                        panel:Unparent()
                    end

                    newRollableTables[tableName] = panel

                    children[#children + 1] = panel
                elseif token.type == "row" then
                    currentRichRow = nil
                    if currentTable == nil then
                        currentTable = m_tables[#newTables + 1] or gui.Table {
                            halign = "left",
                            valign = "top",
                            width = "auto",
                            height = "auto",
                            flow = "vertical",
                            lmargin = 6,
                        }

                        currentTable.data.children = {}

                        if currentRollableTable ~= nil then
                            currentRollableTable.data.table = currentTable
                            currentRollableTable.data.row = 1
                        end

                        newTables[#newTables + 1] = currentTable
                        currentTableRow = nil
                        children[#children + 1] = currentTable
                    end

                    currentTableRow = m_tableRows[#newTableRows + 1] or gui.TableRow {
                        width = "auto",
                        height = "auto",
                    }

                    if m_tableRows[#newTableRows + 1] ~= nil then
                        currentTableRow:Unparent()
                    end

                    currentTableRow.data.children = {}

                    newTableRows[#newTableRows + 1] = currentTableRow

                    currentTable.data.children[#currentTable.data.children + 1] = currentTableRow

                    if currentRollableTable ~= nil then
                        local rollInfo = currentRollableTable.data.rollInfo
                        local range = rollInfo.rollRanges[currentRollableTable.data.row]
                        if range ~= nil then
                            newRollableTableRowLabels[#newRollableTableRowLabels + 1] = m_rollableTableRowLabels[#newRollableTableRowLabels + 1] or gui.Label{
                                fontSize = 16,
                                width = 70,
                                bold = true,
                                halign = "left",
                                height = "auto",
                            }

                            local label = newRollableTableRowLabels[#newRollableTableRowLabels]
                            label:Unparent()
                            if range.min == range.max then
                                label.text = string.format("%d.", range.min)
                            else
                                label.text = string.format("%d-%d.", range.min, range.max)
                            end

                            currentRollableTable.data.rowList = currentRollableTable.data.rowList or {}
                            currentRollableTable.data.rowList[currentRollableTable.data.row] = currentTableRow
                            currentTableRow.data.range = range

                            currentTableRow.data.children[#currentTableRow.data.children + 1] = label
                        end

                        currentRollableTable.data.row = currentRollableTable.data.row + 1
                    end
                elseif token.type == "end_row" then
                    currentTableRow = nil
                    currentRichRow = nil
                elseif token.type == "cell" then
                    currentRichRow = m_richRows[#newRichRows + 1] or gui.Panel {
                        flow = "horizontal",
                        height = "auto",
                        vmargin = 0,
                        pad = 4,
                    }
                    if m_richRows[#newRichRows + 1] ~= nil then
                        currentRichRow:Unparent()
                    end
                    currentRichRow.data.children = {}
                    currentRichRow.selfStyle.width = "auto"
                    currentRichRow.selfStyle.valign = "center"

                    --scan for the number of cells in this row.
                    local beginRowIndex = i
                    for j=i,1,-1 do
                        if tokens[j].type == "row" then
                            beginRowIndex = j
                            break
                        end
                    end

                    local cellCount = 0
                    for j=beginRowIndex,#tokens do
                        if tokens[j].type == "end_row" then
                            break
                        elseif tokens[j].type == "cell" then
                            cellCount = cellCount + 1
                        end
                    end

                    print("CELL COUNT::", cellCount)
                    local cellWidth = math.floor(100 / cellCount)
                    local tableHeaderSpacing = 0
                    if currentRollableTable ~= nil then
                        tableHeaderSpacing = 80/cellCount
                    end

                    --currentRichRow.selfStyle.width = string.format("%d%%-%d", round(cellWidth), round(tableHeaderSpacing))
                    currentRichRow.selfStyle.maxWidth = string.format("%d%%-%d", round(cellWidth), round(tableHeaderSpacing))

                    newRichRows[#newRichRows + 1] = currentRichRow
                    if currentTableRow ~= nil then
                        currentTableRow.data.children[#currentTableRow.data.children + 1] = currentRichRow
                    end
                elseif token.type == "text" and token.justification == nil and token.text == "\n" and currentRichRow ~= nil then
                    --this special case doesn't require inserting a text panel. Instead we just end the rich row of content.
                    currentRichRow = nil
                elseif token.type == "text" then
                    if currentTable ~= nil and currentTableRow == nil then
                        --end of table.
                        currentRollableTable = nil
                        currentRichRow = nil
                        currentTable = nil
                    end

                    local textPanel = m_textPanels[#newTextPanels + 1] or gui.Label {
                        width = "auto",
                        height = "auto",
                        maxWidth = "100%",
                        valign = "center",
                        vmargin = 0,
                        markdown = true,
                        markdownStyle = g_markdownStyle,
                        textAlignment = "topleft",
                        fontSize = CustomDocument.ScaleFontSize(14),
                        pad = 0,
                        links = true,
                        hoverLink = function(element, link)
                            print("LINK:: HOVER", link, element.linkHovered)
                            if string.starts_with(link, "spoiler:") then
                                return
                            end
                            CustomDocument.PreviewLink(element, link)
                        end,
                        dehoverLink = function(element, link)
                            element.tooltip = nil
                        end,
                        press = function(element)
                            if element.linkHovered ~= nil then
                                local link = element.linkHovered
                                print("LINK::", element.linkHovered)
                                if string.starts_with(link, "spoiler:") then
                                    local spoilerValue = link:sub(9)
                                    local spoilerInfo = (m_tokenExtraInfo.spoilers or {})[spoilerValue]
                                    if spoilerInfo == nil then
                                        print("SPOILER: INVALID INDEX", spoilerValue, "VS", table.keys(m_tokenExtraInfo.spoilers))
                                        return
                                    end

                                    local lines = table.shallow_copy(spoilerInfo.lines)
                                    local line = spoilerInfo.lines[spoilerInfo.lineIndex]
                                    print("SPOILER: SUBSTITUTING...", line)
                                    for i=spoilerInfo.linepos,#line do
                                        if line:sub(i,i) == "{" then
                                            local nextChar = line:sub(i+1,i+1)
                                            if nextChar == "!" then
                                                line = line:sub(1,i) .. line:sub(i+2)
                                            else
                                                line = line:sub(1,i) .. "!" .. line:sub(i+1)
                                            end
                                            print("SPOILER: NEW LINE...", line)
                                            lines[spoilerInfo.lineIndex] = line
                                            self:SetTextContent(table.concat(lines, "\n"))
                                            self:Upload()
                                            break
                                        end
                                    end

                                    return
                                end

                                local doc = CustomDocument.ResolveLink(element.linkHovered)
                                if doc ~= nil then
                                    CustomDocument.OpenContent(doc)
                                else
                                    local guid = dmhub.GenerateGuid()
                                    local markdownDoc = MarkdownDocument.new {
                                        id = guid,
                                        description = element.linkHovered,
                                        content = "# " .. element.linkHovered,
                                        annotations = {},
                                    }

                                    dmhub.SetAndUploadTableItem(MarkdownDocument.tableName, markdownDoc)
                                    markdownDoc:ShowDocument { edit = true }
                                end
                            end
                        end,
                    }

                    textPanel.selfStyle.halign = token.justification or "left"

                    if m_textPanels[#newTextPanels + 1] ~= nil then
                        textPanel:Unparent()
                    end

                    local text = token.text
                    if string.starts_with(text, "\n") then
                        text = text:sub(2)
                    end

                    --make it so that leading or trailing spaces are non-breaking
                    if string.starts_with(text, " ") then
                        text = "<color=#00000000>.</color>" .. text:sub(2)
                    end

                    if string.ends_with(text, " ") then
                        text = text:sub(1, -2) .. "<color=#00000000>.</color>"
                    end

                    textPanel.text = text
                    newTextPanels[#newTextPanels + 1] = textPanel

                    --find if the string only has a newline at the end or no newline,
                    --in which case it can go inline.
                    if (currentRichRow ~= nil and token.text:match("^[^\n]*\n?$") ~= nil) or (currentRichRow == nil and string.find(token.text, "\n") == nil) then
                        if currentRichRow == nil then
                            currentRichRow = m_richRows[#newRichRows + 1] or gui.Panel {
                                flow = "horizontal",
                                height = "auto",
                                vmargin = 0,
                            }
                            if m_richRows[#newRichRows + 1] ~= nil then
                                currentRichRow:Unparent()
                            end
                            currentRichRow.selfStyle.width = "100%"
                            currentRichRow.selfStyle.valign = "top"
                            currentRichRow.selfStyle.maxWidth = nil
                            currentRichRow.data.children = {}
                            newRichRows[#newRichRows + 1] = currentRichRow
                            children[#children + 1] = currentRichRow
                        end

                        if token.justification then
                            currentRichRow.selfStyle.width = "100%"
                        end

                        textPanel.selfStyle.valign = "center"
                        currentRichRow.data.children[#currentRichRow.data.children + 1] = textPanel
                    else
                        textPanel.selfStyle.valign = "top"
                        children[#children + 1] = textPanel
                    end

                    if currentRichRow ~= nil and string.find(token.text, "\n") then
                        currentRichRow = nil
                    end
                elseif token.type == "blockquote" then
                    currentRichRow = nil
                    local blockquote = m_blockquotes[#newBlockquotes + 1] or gui.Panel {
                        bgimage = true,
                        bgcolor = "#333333",
                        opacity = 0.4,
                        borderColor = "white",
                        border = {x1 = 4, y1 = 0, x2 = 0, y2 = 0},
                        width = "100%",
                        height = "auto",
                        halign = "left",
                        valign = "top",
                        flow = "horizontal",
                        savedoc = function(element)
                            element:HaltEventPropagation()
                        end,
                        refreshDocument = function(element)
                            element:HaltEventPropagation()
                        end,
                        editDocument = function(element)
                            element:HaltEventPropagation()
                        end,
                        refreshTag = function(element)
                            element:HaltEventPropagation()
                        end,

                        gui.MarkdownLabel{
                            width = "100%-20",
                            halign = "right",
                            markdownText = function(element, text)
                                element:HaltEventPropagation()
                                element.text = text
                            end,
                        }
                    }

                    if m_blockquotes[#newBlockquotes + 1] ~= nil then
                        blockquote:Unparent()
                    end

                    blockquote:FireEventTree("markdownText", token.text)

                    newBlockquotes[#newBlockquotes + 1] = blockquote

                    children[#children+1] = blockquote

                elseif token.type == "tag" then
                    if currentTable ~= nil and currentTableRow == nil then
                        --end of table.
                        currentRollableTable = nil
                        currentRichRow = nil
                        currentTable = nil
                    end

                    local text, suffix
                    local match = regex.MatchGroups(token.text, "^(?<text>.+?):(?<name>.+)$")
                    if match ~= nil then
                        text = match.text
                        suffix = match.name
                    end

                    local text, suffix = token.text:match("^(.-):(.*)$")
                    if suffix == nil then
                        text = token.text
                    end

                    local fullname = token.text
                    local richTagFromPattern = nil

                    local patternMatch = nil

                    for key, richTag in pairs(MarkdownDocument.RichTagRegistry) do
                        if richTag.pattern then
                            patternMatch = regex.MatchGroups(token.text, richTag.pattern)
                            print("BREAKDOWN:: TRYMATCH:", key, token.text, "with", richTag.pattern, patternMatch ~= nil)
                            if patternMatch ~= nil then
                                print("BREAKDOWN:: DO MATCH", token.text)
                                fullname = key
                                text = key
                                richTagFromPattern = richTag
                                break
                            end
                        end
                    end

                    local richTagInfo = MarkdownDocument.RichTagRegistry[string.lower(text)]

                    if richTagInfo ~= nil then
                        local candidate = fullname
                        local index = 1
                        while tagsSeen[candidate] do
                            candidate = fullname .. '-' .. index
                            index = index + 1
                        end

                        tagsSeen[candidate] = true

                        local richTag
                        
                        if richTagFromPattern then
                            richTag = DeepCopy(richTagFromPattern)
                        else
                            richTag = self.annotations[candidate]

                            --patch over any possible bugs where the saved annotation is not a proper table.
                            if richTag ~= nil and getmetatable(richTag) == nil then
                                richTag = nil
                                self.annotations[candidate] = nil
                            end
                        end

                        
                        if richTag ~= nil then
                            local panel = m_richPanels[candidate] or richTag:CreateDisplay()

                            if currentRichRow == nil then
                                currentRichRow = m_richRows[#newRichRows + 1] or gui.Panel {
                                    flow = "horizontal",
                                    height = "auto",
                                    vmargin = 0,
                                }
                                if m_richRows[#newRichRows + 1] ~= nil then
                                    currentRichRow:Unparent()
                                end
                                currentRichRow.selfStyle.width = "100%"
                                currentRichRow.selfStyle.valign = "top"
                                currentRichRow.selfStyle.maxWidth = nil
                                currentRichRow.data.children = {}
                                newRichRows[#newRichRows + 1] = currentRichRow
                                children[#children + 1] = currentRichRow
                            end

                            if m_richPanels[candidate] ~= nil and panel.parent ~= currentRichRow then
                                panel:Unparent()
                            end

                            if token.justification then
                                currentRichRow.selfStyle.width = "100%"
                            end

                            richTag._tmp_document = self
                            panel:FireEventTree("refreshTag", richTag, patternMatch or match, token)

                            newRichPanels[candidate] = panel
                            currentRichRow.data.children[#currentRichRow.data.children + 1] = panel
                        end
                    end
                end
            end

            for i, row in ipairs(newRichRows) do
                row.children = row.data.children
                row.data.children = nil
            end

            for i, row in ipairs(newTableRows) do
                row.children = row.data.children
                row.data.children = nil
            end

            for i, t in ipairs(newTables) do
                t.children = t.data.children
                t.data.children = nil
            end

            m_rollableTableRowLabels = newRollableTableRowLabels
            m_rollableTables = newRollableTables
            m_richRows = newRichRows
            m_richPanels = newRichPanels
            m_textPanels = newTextPanels
            m_tableRows = newTableRows
            m_tables = newTables
            m_dividers = newDividers
            m_powerTables = newPowerTables
            m_embeds = newEmbeds
            m_treeNodes = newTreeNodes
            m_blockquotes = newBlockquotes
            element.children = children
        end,
    }

    for k, v in pairs(args) do
        params[k] = v
    end

    resultPanel = gui.Panel(params)
    resultPanel:FireEventTree("refreshDocument")

    return resultPanel
end

local MarkdownReferenceTooltip

function MarkdownDocument:EditPanel(args)
    local resultPanel

    local markdownReferenceLabel = gui.Label {
        width = "auto",
        height = "auto",
        text = "Formatting Guide",
        fontSize = CustomDocument.ScaleFontSize(16),
        color = "#FF00FF",
        halign = "left",
        valign = "top",
        hover = function(element)
            element.tooltip = MarkdownReferenceTooltip()
        end,
    }

    local editInput

    local savePanel = gui.Panel{
        flow = "horizontal",
        width = 160,
        height = 16,
        halign = "right",

        gui.Label{

            styles = {
                {
                    selectors = {"changes"},
                    collapsed = 1,
                },
                {
                    selectors = {"savePending"},
                    collapsed = 1,
                },
            },

            text = "Changes Saved",
            fontSize = 14,
            width = "auto",
            height = "auto",
        },

        gui.Label{
            color = "#888888",
            styles = {
                {
                    selectors = {"changes"},
                    collapsed = 1,
                },
                {
                    selectors = {"~savePending"},
                    collapsed = 1,
                },
            },

            text = "Saving...",
            fontSize = 14,
            width = "auto",
            height = "auto",
        },

        gui.Label{
            styles = {
                {
                    selectors = {"~changes"},
                    collapsed = 1,
                }
            },
            text = "Unsaved Changes",
            fontSize = 14,
            width = "auto",
            height = "auto",
        },

        gui.Button{
            styles = {
                {
                    selectors = {"~changes"},
                    collapsed = 1,
                }
            },
            inputEvents = { "save" },
            text = "Save",
            width = 40,
            height = 16,
            fontSize = 12,
            save = function(element)
                if element:HasClass("changes") then
                    element:FireEvent("press")
                end
            end,
            press = function(element)
                local documentPanel = element:FindParentWithClass("documentPanel")
                if documentPanel ~= nil then
                    print("DOCUMENT:: Saving document...")
                    resultPanel:SetClassTree("savePending", true)
                    documentPanel:FireEvent("saveDocument")
                else
                    print("DOCUMENT:: No document panel found!")
                end
            end,

            saveConfirmed = function(element)
                resultPanel:SetClassTree("savePending", false)
            end,
        },
    }

    local charactersUsedLabel = gui.Label {
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "center",
        fontSize = CustomDocument.ScaleFontSize(16),
        color = "white",
        refreshLength = function(element, text)
            local len = #text
            local remaining = CustomDocument.MaxLength - len
            if remaining < 1000 then
                if remaining < 200 then
                    element.selfStyle.color = "red"
                else
                    element.selfStyle.color = "white"
                end

                element.text = string.format("%d characters remaining...", remaining)
                element:SetClass("hidden", false)
            else
                element:SetClass("hidden", true)
            end
        end,
        refreshDocument = function(element)
            element:FireEvent("refreshLen", #self:GetTextContent())
        end,
        editDocument = function(element)
            element:FireEvent("refreshLen", #self:GetTextContent())
        end,
    }

    editInput = gui.Input {
        id = "editorPanel",
        width = "100%",
        height = "100%",
        halign = "center",
        fontSize = CustomDocument.ScaleFontSize(16),
        fontFace = "Courier",
        multiline = true,
        textAlignment = "topleft",
        text = self:GetTextContent(),
        vscroll = true,
        selectAllOnFocus = false,
        characterLimit = CustomDocument.MaxLength,

        editlag = 0.3,
        edit = function(element)
            if resultPanel ~= nil then
                resultPanel:FireEventTree("editDocument", element.text)
            end
            charactersUsedLabel:FireEvent("refreshLength", element.text)
        end,
        refreshDocument = function(element)
            element.text = self:GetTextContent()
        end,
        needsave = function(element, result)
            if self:GetTextContent() ~= element.text then
                result.save = true
            end
        end,
        savedoc = function(element)
            self:SetTextContent(element.text)
            element.text = self:GetTextContent()
        end,

        checkChanges = function(element, baseDoc)
            resultPanel:SetClassTree("changes", element.text ~= baseDoc:GetTextContent())
        end,
    }

    local m_richPanels = {}

    local annotationsPanel = gui.Panel {
        width = "98%",
        height = "auto",
        maxHeight = 200,
        vscroll = true,
        vmargin = 8,
        flow = "horizontal",
        wrap = true,

        refreshDocument = function(element, doc)
            if doc ~= nil then
                element:FireEvent("editDocument", doc:GetTextContent())
            end
        end,

        editDocument = function(element, content)
            local tagsSeen = {}

            local newRichPanels = {}
            local children = {}
            local tokens = BreakdownRichTags(content)
            for i, token in ipairs(tokens) do
                if token.type == "tag" then
                    local text, suffix = token.text:match("^(.-):(.*)$")
                    if suffix == nil then
                        text = token.text
                    end

                    local richTagInfo = MarkdownDocument.RichTagRegistry[string.lower(text)]

                    if richTagInfo ~= nil and richTagInfo.hasEdit then
                        local candidate = token.text
                        local index = 1
                        while tagsSeen[candidate] do
                            candidate = token.text .. '-' .. index
                            index = index + 1
                        end

                        tagsSeen[candidate] = true

                        local richTag = self.annotations[candidate]
                        --patch over any possible bugs where the saved annotation is not a proper table.
                        if richTag ~= nil and getmetatable(richTag) == nil then
                            richTag = nil
                            self.annotations[candidate] = nil
                        end

                        if richTag == nil then
                            richTag = richTagInfo.Create()
                            richTag.identifier = suffix or false
                            self.annotations[candidate] = richTag
                        end

                        if richTagInfo.hasEdit ~= "hidden" then
                            local richPanel = m_richPanels[candidate] or gui.Panel {
                                width = "auto",
                                height = 120,
                                flow = "vertical",
                                halign = "left",
                                valign = "top",
                                hmargin = 4,
                                gui.Panel {
                                    width = "auto",
                                    height = 96,
                                    richTag:CreateEditor(),
                                },
                                gui.Label {
                                    text = candidate,
                                    fontSize = CustomDocument.ScaleFontSize(12),
                                    textAlignment = "center",
                                    width = 96,
                                    height = "auto",
                                    halign = "center",
                                    valign = "center",
                                },
                            }

                            newRichPanels[candidate] = richPanel
                            children[#children + 1] = richPanel

                            richPanel:FireEventTree("refreshEditor", richTag)
                        end
                    end
                end
            end

            m_richPanels = newRichPanels
            element.children = children
        end,
    }

    resultPanel = gui.Panel {
        classes = { "collapsed" },
        width = "100%",
        height = "100%-0",
        valign = "top",
        tmargin = 2,
        flow = "vertical",
        refreshDocument = function(element, doc)
            self = doc or self
        end,

        gui.Panel{
            width = "98%",
            height = "90% available",
            halign = "center",
            valign = "top",
            flow = "horizontal",
            editInput,
        },
        gui.Panel {
            width = "100%",
            height = 16,
            markdownReferenceLabel,
            charactersUsedLabel,
            savePanel,
        },
        annotationsPanel,
    }

    resultPanel:FireEventTree("editDocument", self:GetTextContent())

    return resultPanel
end

function MarkdownDocument:MatchesSearch(search)
    if string.find(string.lower(self:GetTextContent()), search, 1, true) then
        return true
    end

    return false
end

CustomDocument.Register {
    id = "markdown",
    text = "New Text Document",
    create = function()
        return MarkdownDocument.new {
            content = "",
            annotations = {},
        }
    end,
}

local g_markdownSamples = {
    "# Title", "*italics*", "**bold**", "__underline__", "~~strike~~",
    [[* point 1
* point 2
* point 3]],
    "{hidden from players}",
    "{#redacted from players}",
    "{!revealed to players}",

    "Before divider\n---\nAfter divider",

    [[|Disarm the Scythe Trap: Agility Test
|The hero triggers the trap.
|The hero fails to disarm the trap, but doesn't trigger it.
|The hero disarms the trap.]],

    '<color=red>Red Text</color>',
    "Interest: [[##--]]",

    "[[image]]",
    "[[sound]]",

}

MarkdownReferenceTooltip = function()
    local annotations = {
        image = RichImage.new {
            image = "98fa8fcd-5a62-4736-924d-0753b2900b2e",
            uiscale = 0.15,
        },
        sound = RichAudio.new{
            sound = "f6bc62cc-7225-48cf-b719-b86280ea198d",
        },
    }

    local resultPanel

    local children = {}

    children[#children + 1] = gui.TableRow {
        width = "100%",
        height = "auto",
        bgcolor = "clear",
        bgimage = true,
        borderColor = "white",
        border = 1,

        gui.Panel {
            width = "50%",
            height = "auto",
            pad = 6,
            gui.Label {
                fontSize = CustomDocument.ScaleFontSize(24),
                width = "100%",
                height = "auto",
                text = "You Type",
                bold = true,
            },
        },

        gui.Panel {
            width = "50%",
            height = "auto",
            pad = 6,
            gui.Label {
                fontSize = CustomDocument.ScaleFontSize(24),
                width = "100%",
                height = "auto",
                text = "You See",
                bold = true,
            },
        },
    }

    for _, sample in ipairs(g_markdownSamples) do
        local doc = MarkdownDocument.new {
            content = sample,
            annotations = annotations,
        }
        children[#children + 1] = gui.TableRow {
            width = "100%",
            height = "auto",
            bgcolor = "clear",
            bgimage = true,
            borderColor = "white",
            border = 1,
            gui.Panel {
                width = "50%",
                height = "auto",
                pad = 6,
                gui.Label {
                    width = "100%",
                    height = "auto",
                    text = string.format("<noparse>%s</noparse>", sample),
                    fontSize = CustomDocument.ScaleFontSize(14),
                    textAlignment = "topleft",
                    fontFace = "Courier",
                },
            },
            gui.Panel {
                width = "50%",
                height = "auto",
                pad = 6,
                doc:DisplayPanel {
                    width = "100%-24",
                    vscroll = false,
                    height = "auto",
                },
            }
        }
    end

    local t = gui.Table {
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "vertical",
        children = children,
    }

    local panel = gui.Panel {
        width = "100%",
        height = "auto",
        flow = "horizontal",
        t,
    }

    resultPanel = gui.TooltipFrame(panel, {
        halign = "right",
        width = 1100,
        height = "auto",
    })

    resultPanel:MakeNonInteractiveRecursive()

    return resultPanel
end
