local mod = dmhub.GetModLoading()

--PDF character sheet export.
--
--Fills a fillable (AcroForm) PDF character sheet with a hero's data and saves the
--result to a user-chosen location. The blank sheet PDF ships as a PDF document
--asset in the module; the engine fills it via PDFDocument:FillForm and the bytes
--are written to disk via dmhub.SaveFileDialog.
--
--Sheet layouts are data-driven: each PDF sheet registers a template that maps the
--PDF's field names to extractor functions. Adding support for a new sheet layout
--means registering a new template; no engine changes are needed.
--
--template = {
--   id = string,                 --unique template id
--   name = string,               --human readable name
--   docid = nil|string,          --the PDF document asset id (preferred lookup)
--   docName = nil|string,        --fallback: case-insensitive match on the asset description
--   fields = table<string, function(token, creature) -> nil|string|number>,
--                                --text fields: PDF field name -> extractor. nil leaves the
--                                --field blank; errors are logged and leave the field blank.
--   checks = table<string, function(token, creature) -> nil|boolean>,
--                                --checkbox fields: PDF field name -> extractor.
--   multi = nil|function(token, creature, fields)[],
--                                --extractors that write many fields at once (skill grids,
--                                --victory tracks, project rows). They set entries directly
--                                --on the fields table: strings/numbers for text fields,
--                                --booleans for checkboxes.
--}

CharSheetPDFExport = {
    templates = {},
    templateOrder = {},
}

function CharSheetPDFExport.RegisterTemplate(template)
    if CharSheetPDFExport.templates[template.id] == nil then
        CharSheetPDFExport.templateOrder[#CharSheetPDFExport.templateOrder+1] = template.id
    end
    CharSheetPDFExport.templates[template.id] = template
end

function CharSheetPDFExport.GetTemplates()
    local result = {}
    for _,id in ipairs(CharSheetPDFExport.templateOrder) do
        result[#result+1] = CharSheetPDFExport.templates[id]
    end
    return result
end

--Shallow-merges any number of {fieldName -> extractor} tables into a new table;
--later tables override earlier ones. Used to compose a template's field set from the
--shared base plus per-sheet additions.
function CharSheetPDFExport.MergeFields(...)
    local result = {}
    for _,t in ipairs({...}) do
        for k,v in pairs(t) do
            result[k] = v
        end
    end
    return result
end

--Concatenates any number of multi-extractor arrays into a new array.
function CharSheetPDFExport.ConcatMulti(...)
    local result = {}
    for _,t in ipairs({...}) do
        for _,fn in ipairs(t) do
            result[#result+1] = fn
        end
    end
    return result
end

--The hero's primary class name (e.g. "Summoner", "Beastheart"), or nil.
local function ClassNameOf(creature)
    local className = nil
    pcall(function()
        local classInfo = creature:GetClass()
        if classInfo ~= nil then
            className = classInfo.name
        end
    end)
    return className
end

--Resolves the template to use for a given variant ("simple" or "expanded") and hero.
--For "expanded", a template whose classMatch equals the hero's class name wins (the
--Summoner/Beastheart sheets), otherwise the generic expanded template is used. Only
--templates whose PDF asset actually resolves are considered.
function CharSheetPDFExport.ResolveTemplateForVariant(creature, variant)
    local className = ClassNameOf(creature)

    local generic = nil
    for _,template in ipairs(CharSheetPDFExport.GetTemplates()) do
        if template.variant == variant and CharSheetPDFExport.ResolveDocumentAsset(template) ~= nil then
            if variant == "expanded" and template.classMatch ~= nil then
                if className ~= nil and string.lower(template.classMatch) == string.lower(className) then
                    return template
                end
            elseif generic == nil then
                generic = template
            end
        end
    end

    return generic
end

--Which variants ("simple"/"expanded") are available for this hero right now (i.e. a
--matching template with an installed PDF asset exists).
function CharSheetPDFExport.AvailableVariants(creature)
    local result = {}
    for _,variant in ipairs({"simple", "expanded"}) do
        if CharSheetPDFExport.ResolveTemplateForVariant(creature, variant) ~= nil then
            result[#result+1] = variant
        end
    end
    return result
end

--Reduces a name to lowercase alphanumerics so asset descriptions match loosely:
--"DrawSteel_CharacterSheetBlank" matches docName "draw steel character sheet".
local function NormalizeName(name)
    return string.gsub(string.lower(name or ""), "[^a-z0-9]", "")
end

--Finds the PDF document asset backing a template: by asset id first, then by a
--normalized prefix match on the asset description. Prefix (not substring) matching
--keeps the generic "expanded character sheet" from grabbing the "beastheart expanded
--character sheet" PDF -- the beastheart description does not START with the generic
--docName. Set docid to an asset guid for an exact, unambiguous match.
function CharSheetPDFExport.ResolveDocumentAsset(template)
    local docsTable = assets.pdfDocumentsTable
    if docsTable == nil then
        return nil
    end

    if template.docid ~= nil and docsTable[template.docid] ~= nil then
        return docsTable[template.docid]
    end

    if template.docName ~= nil then
        local target = NormalizeName(template.docName)
        if target ~= "" then
            for _,doc in pairs(docsTable) do
                local description = NormalizeName(doc.description)
                --description begins with the docName (target), e.g.
                --"drawsteelcharactersheetblank" begins with "drawsteelcharactersheet".
                if description ~= "" and string.sub(description, 1, #target) == target then
                    return doc
                end
            end
        end
    end

    return nil
end

--Runs every extractor for the template and returns the {fieldName -> value} table
--to hand to PDFDocument:FillForm. Extractors run inside pcall: a nil result or an
--error leaves the field blank (errors are logged once per export).
function CharSheetPDFExport.BuildFields(template, token)
    local creature = token.properties
    local fields = {}
    local errors = {}

    for fieldName,extract in pairs(template.fields or {}) do
        local ok, value = pcall(extract, token, creature)
        if ok then
            if value ~= nil then
                fields[fieldName] = value
            end
        else
            errors[#errors+1] = string.format("%s: %s", fieldName, tostring(value))
        end
    end

    for fieldName,extract in pairs(template.checks or {}) do
        local ok, value = pcall(extract, token, creature)
        if ok then
            if value ~= nil then
                fields[fieldName] = (value and true) or false
            end
        else
            errors[#errors+1] = string.format("%s: %s", fieldName, tostring(value))
        end
    end

    for _,fill in ipairs(template.multi or {}) do
        local ok, err = pcall(fill, token, creature, fields)
        if not ok then
            errors[#errors+1] = tostring(err)
        end
    end

    if #errors > 0 then
        print("PDFExport:: field extraction errors:", table.concat(errors, " | "))
    end

    return fields
end

--The complete export flow: resolve the template's PDF asset, extract the hero's
--fields, fill the form, and offer a save dialog for the result.
function CharSheetPDFExport.Export(token, templateId)
    local template = CharSheetPDFExport.templates[templateId]
    if template == nil then
        gui.ModalMessage{ title = "Export Failed", message = "Unknown character sheet template." }
        return
    end

    local docAsset = CharSheetPDFExport.ResolveDocumentAsset(template)
    if docAsset == nil or docAsset.doc == nil then
        gui.ModalMessage{
            title = "Export Failed",
            message = "The character sheet PDF could not be found. Make sure the module containing it is installed.",
        }
        return
    end

    --PDF form filling is a newer engine feature; on an out-of-date build the C#
    --PDFDocument:FillForm method is absent. Silently no-op (the export button is
    --already hidden on such builds) rather than crash on a nil method call.
    if docAsset.doc.FillForm == nil then
        return
    end

    local fields = CharSheetPDFExport.BuildFields(template, token)

    docAsset.doc:FillForm{
        fields = fields,
        callback = function(bytes, err)
            if bytes == nil then
                gui.ModalMessage{ title = "Export Failed", message = err or "Could not fill the PDF character sheet." }
                return
            end

            local heroName = token.name
            if heroName == nil or heroName == "" then
                heroName = "Hero"
            end

            dmhub.SaveFileDialog{
                data = bytes,
                filename = string.format("%s - Character Sheet.pdf", heroName),
                extensions = {"pdf"},
                title = "Export Character Sheet",
                message = "Choose where to save the character sheet",
            }
        end,
    }
end

--Dev helper: dumps every form field in a template's PDF to the console. Useful when
--building the field mapping for a new sheet; drive from the console or MCP bridge:
--  CharSheetPDFExport.DumpFields("mcdm-hero-sheet")
function CharSheetPDFExport.DumpFields(templateId)
    local template = CharSheetPDFExport.templates[templateId]
    if template == nil then
        print("PDFExport:: unknown template", templateId)
        return
    end

    local docAsset = CharSheetPDFExport.ResolveDocumentAsset(template)
    if docAsset == nil or docAsset.doc == nil then
        print("PDFExport:: could not resolve PDF asset for", templateId)
        return
    end

    if docAsset.doc.GetFormFields == nil then
        print("PDFExport:: GetFormFields is unavailable in this build")
        return
    end

    docAsset.doc:GetFormFields(function(fieldList)
        if fieldList == nil then
            print("PDFExport:: could not read form fields")
            return
        end

        print(string.format("PDFExport:: %d form fields:", #fieldList))
        for _,field in ipairs(fieldList) do
            print(string.format("PDFExport:: page %d [%s] '%s' value='%s' export='%s' checked=%s",
                field.page, field.type, field.name, field.value or "", field.exportValue or "", tostring(field.checked)))
        end
    end)
end

--Text formatting helpers shared by templates.

--Formats a numeric modifier with an explicit sign: +2, -1, +0.
function CharSheetPDFExport.FormatSigned(n)
    if n == nil then
        return nil
    end
    n = round(n)
    if n >= 0 then
        return string.format("+%d", n)
    end
    return string.format("%d", n)
end

--Joins a list of strings with the given separator, returning nil for an empty list.
function CharSheetPDFExport.Join(list, sep)
    if list == nil or #list == 0 then
        return nil
    end
    return table.concat(list, sep or ", ")
end

--Splits text across two fixed-size sheet boxes: returns (first, second), breaking at
--a line boundary once the first part exceeds the budget in characters.
function CharSheetPDFExport.SplitIntoTwo(lines, budget)
    if lines == nil or #lines == 0 then
        return nil, nil
    end

    local first = {}
    local second = {}
    local count = 0
    for _,line in ipairs(lines) do
        if count < budget then
            first[#first+1] = line
            count = count + #line + 1
        else
            second[#second+1] = line
        end
    end

    return CharSheetPDFExport.Join(first, "\n"), CharSheetPDFExport.Join(second, "\n")
end

--Exports the given variant ("simple"/"expanded") for the hero, resolving the right
--template (class-specific expanded sheets win for Summoner/Beastheart heroes).
function CharSheetPDFExport.ExportVariant(token, variant)
    local template = CharSheetPDFExport.ResolveTemplateForVariant(token.properties, variant)
    if template == nil then
        gui.ModalMessage{ title = "Export Failed", message = "No character sheet PDF is installed for that option." }
        return
    end
    CharSheetPDFExport.Export(token, template.id)
end

--Downloads the hero as a Codex-native JSON file. Wraps the hero's serialized properties
--with the token name (which lives on the token, not the properties) so the file is
--self-contained. dmhub.ToJson / dmhub.FromJson are the engine's matched round-trip pair.
function CharSheetPDFExport.ExportJson(token)
    --No save API on out-of-date builds; silently no-op (the button is hidden there).
    if dmhub.SaveFileDialog == nil then
        return
    end

    local export = {
        codexHero = true,
        formatVersion = 1,
        name = token.name,
        properties = token.properties,
    }

    local jsonString = dmhub.ToJson(export)

    local heroName = token.name
    if heroName == nil or heroName == "" then
        heroName = "Hero"
    end

    dmhub.SaveFileDialog{
        data = jsonString,
        filename = string.format("%s.json", heroName),
        extensions = {"json"},
        title = "Download Character (JSON)",
        message = "Choose where to save the character JSON",
    }
end

local g_variantLabels = { simple = "Simple Sheet", expanded = "Expanded Sheet" }

--Builds the ordered list of export options offered by the sheet button: one entry per
--available PDF sheet variant, then the always-available Codex JSON download.
function CharSheetPDFExport.GetExportOptions(token)
    local options = {}
    for _,variant in ipairs(CharSheetPDFExport.AvailableVariants(token.properties)) do
        local v = variant
        options[#options+1] = {
            text = g_variantLabels[v] or v,
            run = function() CharSheetPDFExport.ExportVariant(token, v) end,
        }
    end
    options[#options+1] = {
        text = "Codex JSON",
        run = function() CharSheetPDFExport.ExportJson(token) end,
    }
    --Prototype: only offered once the Forge Steel builder (in the MCDM mapping file)
    --has loaded.
    if CharSheetPDFExport.ExportForgeSteel ~= nil then
        options[#options+1] = {
            text = "Forge Steel (Beta)",
            run = function() CharSheetPDFExport.ExportForgeSteel(token) end,
        }
    end
    return options
end

--The character sheet's corner button. Visible for any hero. Clicking offers the
--available PDF sheet variants (Expanded picks the Summoner/Beastheart layout for those
--classes) plus a Codex JSON download; a single option exports directly.
CharSheet.RegisterSheetAction{
    id = "pdfexport",
    --A pure-white icon mask so the theme tints it identically to the neighboring
    --windowed/close nav buttons; ui-icons/downloadicon.png has a warm baked-in
    --tint that renders a different shade.
    icon = "game-icons/cloud-download.png",
    tooltip = "Export",
    visible = function(creature)
        --dmhub.SaveFileDialog is a newer engine method that every export path needs to
        --write its file. On an out-of-date build it (and PDFDocument:FillForm) are
        --absent, so hide the whole button rather than let a click crash.
        return creature.typeName == "character" and dmhub.SaveFileDialog ~= nil
    end,
    click = function(token, element)
        local options = CharSheetPDFExport.GetExportOptions(token)
        if #options == 0 then
            return
        end

        if #options == 1 then
            options[1].run()
            return
        end

        local entries = {}
        for _,option in ipairs(options) do
            local o = option
            entries[#entries+1] = {
                text = o.text,
                click = function()
                    element.popup = nil
                    o.run()
                end,
            }
        end

        element.popup = gui.ContextMenu{
            entries = entries,
        }
    end,
}

--------------------------------------------------------------------------------
-- Codex Character JSON import
-- Reads a file produced by CharSheetPDFExport.ExportJson and creates a hero from it.
-- Uses dmhub.FromJson (not ParseJsonFile) so the embedded game-typed "character" is
-- reconstructed as a live object, not a plain table.
--------------------------------------------------------------------------------

--Creates a hero token from a parsed Codex-hero wrapper and finalizes it through the
--import framework. Returns the new token, or nil on failure.
local function DoImportCodexHero(parsed)
    if parsed == nil or parsed.codexHero ~= true or parsed.properties == nil then
        gui.ModalMessage{ title = "Import Failed", message = "This file is not a Codex character JSON export." }
        return nil
    end

    local token = import:CreateCharacter()
    token.properties = parsed.properties
    token.partyId = GetDefaultPartyID()
    token.name = parsed.name or "Imported Hero"

    import:ImportCharacter(token)
    return token
end

--Opens a file dialog to import a Codex character JSON and opens the new hero's sheet.
function CharSheetPDFExport.ImportCharacterFromFile()
    dmhub.OpenFileDialog{
        id = "ImportCodexCharacter",
        extensions = {"json"},
        multiFiles = false,
        prompt = "Choose Codex Character JSON File",
        open = function(path)
            local text = dmhub.ReadTextFile(path, function(err)
                gui.ModalMessage{ title = "Import Failed", message = "Could not read the file." }
            end)
            if text == nil then
                return
            end

            local result = dmhub.FromJson(text)
            local parsed = result and result.result
            if parsed == nil then
                gui.ModalMessage{ title = "Import Failed", message = "The file is not valid JSON." }
                return
            end

            --Track existing characters so we can find and open the newly created one.
            local knownCharacters = {}
            for _,v in ipairs(table.values(game.GetGameGlobalCharacters())) do
                knownCharacters[v.charid] = true
            end

            import:ClearState()
            local ok = DoImportCodexHero(parsed) ~= nil
            import:CompleteImportStep()

            if ok then
                dmhub.Coroutine(function()
                    for i = 1,100 do
                        coroutine.yield()
                        for _,token in ipairs(table.values(game.GetGameGlobalCharacters())) do
                            if not knownCharacters[token.charid] then
                                if not dmhub.isDM then
                                    token.ownerId = dmhub.userid
                                end
                                token:ChangeLocation(core.Loc{x = 0, y = 0})
                                token:ShowSheet("Builder")
                                return
                            end
                        end
                    end
                end)
            end
        end,
    }
end

--Registers the importer with the DMHub import framework (Tools -> Import Assets ->
--Codex Character (JSON)).
if import ~= nil and import.Register ~= nil then
    import.Register{
        id = "codexherojson",
        description = "Codex Character (JSON)",
        input = "plaintext",
        priority = 200,
        text = function(importer, text)
            local result = dmhub.FromJson(text)
            DoImportCodexHero(result and result.result)
        end,
    }
end

--Chat macro alternative that also opens the imported hero's sheet.
if Commands ~= nil and Commands.RegisterMacro ~= nil then
    Commands.RegisterMacro{
        name = "importcodexhero",
        summary = "import Codex character",
        doc = "Usage: /importcodexhero\nOpens a file dialog to import a Codex character from a JSON file.",
        command = function(str)
            CharSheetPDFExport.ImportCharacterFromFile()
        end,
    }
end
