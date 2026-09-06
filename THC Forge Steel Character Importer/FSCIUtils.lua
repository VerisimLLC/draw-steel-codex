--- @class FSCIUtils: GameType
FSCIUtils = RegisterGameType("FSCIUtils")
FSCIUtils.__index = FSCIUtils

local FSCI_DEBUG = false
local FSCI_VERBOSE = false

--- Status flags for `FSCIUtils.writeLog()`
--- These control both logging behavior and text coloring
FSCIUtils.STATUS = {
    INFO  = "#aaaaaa",
    ERROR = "#aa0000",
    IMPL  = "#00aaaa",
    GOOD  = "#00aa00",
    WARN  = "#ff8c00",
}

--- Translate strings from Forge Steel names to Codex names.
local FSCI_TRANSLATIONS = {
    -- Abilities
    ["Demon Unleashed"] = "A Demon Unleashed",
    ["Force Orb"] = "Force Orbs",
    ["Halt, Miscreant!"] = "Halt Miscreant!",

    -- Ancestries
    ["Elf (high)"] = "Elf, High",
    ["Elf (wode)"] = "Elf, Wode",

    -- Ancestry Features
    ["Draconic Pride"] = "Draconian Pride",
    ["Perseverence"] = "Perseverance",
    ["Resist the Unnatural"] = "Resist the Supernatural",

    -- Choice Types
    ["Elementalist Ward"] = "Ward",

    -- Classes & Subclasses
    ["Chronokinetic"] = "Disciple of the Chronokinetic",
    ["Cryokinetic"] = "Disciple of the Cryokinetic",
    ["Metakinetic"] = "Disciple of the Metakinetic",

    -- Feats
    ["I've Got You"] = "I've Got You!",
    ["Put Your Back Into It"] = "Put Your Back Into It!",
    ["Prayer"] = "Prayers",

    -- Inciting Incidents
    ["Near-Death Experience"] = "Near Death Experience",

    -- Kits
    ["Rapid Fire"] = "Rapid-Fire",

    -- Languages
    ["Kalliac"] = "Kalliak",
    ["Yllric"] = "Yllyric",

    -- Psionic Augmentations & Wards
    ["Battle Augmentation"] = "Battle Augmentation ",
    ["Steel Ward"] = "Steel Ward ",
    ["Talent Ward"] = "Ward",

    -- Skills
    -- ["Perform"] = "Performance"
}

--- Sets the debug mode state.
--- @param v boolean The debug mode state to set
function FSCIUtils.SetDebugMode(v)
    FSCI_DEBUG = v
end

--- Toggles the debug mode between enabled and disabled.
function FSCIUtils.ToggleDebugMode()
    FSCI_DEBUG = not FSCI_DEBUG
end

--- Sets the verbose mode state.
--- @param v boolean The verbose mode state to set
function FSCIUtils.SetVerboseMode(v)
    FSCI_VERBOSE = v
end

-- Sets the debug & verbose state
--- @param v boolean The verbose mode state to set
function FSCIUtils.SetDebugVerboseMode(v)
    FSCI_DEBUG = v
    FSCI_VERBOSE = v
end

--- Toggles the verbose mode between enabled and disabled.
function FSCIUtils.ToggleVerboseMode()
    FSCI_VERBOSE = not FSCI_VERBOSE
end

--- Returns whether verbose mode is currently enabled.
--- @return boolean verbose True if verbose mode is active, false otherwise
function FSCIUtils.inVerboseMode()
    return FSCI_VERBOSE
end

--- Returns whether debug mode is currently enabled.
--- @return boolean debug `true` if debug mode is active; `false` otherwise.
function FSCIUtils.inDebugMode()
    return FSCI_DEBUG
end

--- Writes a debug message to the debug log, if we're in debug mode
--- Suports param list like `string.format()`
--- @param fmt string Text to write
--- @param ...? string Tags for filling in the `fmt` string
function FSCIUtils.writeDebug(fmt, ...)
    if FSCI_DEBUG and fmt and #fmt > 0 then
        print("FSCI::", string.format(fmt, ...))
    end
end

--- Retrieves the line number from the call stack at a given level.
-- Useful for logging or debugging purposes.
--- @param level number (optional) The stack level to inspect. Defaults to 2 (the caller of this function).
--- @return number line The line number in the source file at the specified call stack level.
function FSCIUtils.curLine(level)
    level = level or 2
    return debug.getinfo(level, "l").currentline
end

--- Tracks the current indentation level for activity log messages.
--- This value is used to format output written to the user-facing log (not debug output),
--- allowing nested or hierarchical operations to visually reflect structure.
--- It is modified by logging functions to increase or decrease indentation as needed.
FSCIUtils.indentLevel = 0

--- Writes a formatted message to the log with optional status and indentation.
--- Applies color based on status and prepends indentation for nested output.
--- Typically indent at the start of a function and outdent at the end.
--- Indentation level is tracked globally and adjusted based on the `indent` value:
---   - A positive indent increases the level *after* the current message.
---   - A negative indent decreases the level *before* the current message.
---
--- @param message string The message to log.
--- @param status? string (optional) The status color code from FSCIUtils.STATUS (default: INFO).
--- @param indent? number (optional) A relative indent level (e.g., 1 to increase, -1 to decrease).
function FSCIUtils.writeLog(message, status, indent)
    status = status or FSCIUtils.STATUS.INFO
    indent = indent or 0

    if FSCI_VERBOSE or status ~= FSCIUtils.STATUS.INFO then
        -- Apply negative indent before logging
        if indent < 0 then FSCIUtils.indentLevel = math.max(0, FSCIUtils.indentLevel + indent) end

        -- Prepend caller's line number for warnings and errors
        if status == FSCIUtils.STATUS.WARN or status == FSCIUtils.STATUS.ERROR then
            message = string.format("%s (line %d)", message, FSCIUtils.curLine(3))
        end

        local indentPrefix = string.rep(" ", 2 * math.max(0, FSCIUtils.indentLevel))
        local indentedMessage = string.format("%s%s", indentPrefix, message)
        local formattedMessage = string.format("<color=%s>%s</color>", status, indentedMessage)

        import:Log(formattedMessage)

        -- Apply positive indent after logging
        if indent > 0 then FSCIUtils.indentLevel = FSCIUtils.indentLevel + indent end
    end
end

function FSCIUtils.AppendToTable(t, k, v)
    t[k] = t[k] or {}
    table.insert(t[k], v)
end

--- Merges all key-value pairs from source table into target table.
--- Overwrites any existing keys in the target table with values from the source table.
--- Modifies the target table in place and returns it for convenience.
--- @param target table The table to merge data into (modified in place)
--- @param source table The table to copy data from (unchanged)
--- @return table target The modified target table containing merged data
function FSCIUtils.MergeTables(target, source)
    for key, value in pairs(source) do
        target[key] = value
    end
    return target
end

--- Compares two strings for equality after sanitizing and normalizing them.
--- This function removes special characters, trims whitespace, and converts both
--- strings to lowercase before comparison. Useful for fuzzy string matching where
--- formatting differences should be ignored.
--- @param s1 string|nil The first string to compare (nil treated as empty string)
--- @param s2 string|nil The second string to compare (nil treated as empty string)
--- @return boolean True if the sanitized strings match, false otherwise
function FSCIUtils.SanitizedStringsMatch(s1, s2)
    local function sanitize(s)
        s = s or ""

        local replacements = {
            -- Lower-case accents
            ["\195\161"] = "a", ["\195\160"] = "a", ["\195\162"] = "a", ["\195\164"] = "a",
            ["\195\169"] = "e", ["\195\168"] = "e", ["\195\170"] = "e", ["\195\171"] = "e",
            ["\195\173"] = "i", ["\195\172"] = "i", ["\195\174"] = "i", ["\195\175"] = "i",
            ["\195\179"] = "o", ["\195\178"] = "o", ["\195\180"] = "o", ["\195\182"] = "o",
            ["\195\186"] = "u", ["\195\185"] = "u", ["\195\187"] = "u", ["\195\188"] = "u",
            ["\195\177"] = "n", ["\195\167"] = "c", ["\195\189"] = "y",

            -- Upper-case accents
            ["\195\129"] = "A", ["\195\128"] = "A", ["\195\130"] = "A", ["\195\132"] = "A",
            ["\195\137"] = "E", ["\195\136"] = "E", ["\195\138"] = "E", ["\195\139"] = "E",
            ["\195\141"] = "I", ["\195\140"] = "I", ["\195\142"] = "I", ["\195\143"] = "I",
            ["\195\147"] = "O", ["\195\146"] = "O", ["\195\148"] = "O", ["\195\150"] = "O",
            ["\195\154"] = "U", ["\195\153"] = "U", ["\195\155"] = "U", ["\195\156"] = "U",
            ["\195\145"] = "N", ["\195\135"] = "C", ["\195\157"] = "Y",

            -- Ligatures
            ["\195\134"] = "AE", ["\195\166"] = "ae",

            -- Icelandic/Old English
            ["\195\144"] = "D",  ["\195\176"] = "d",
            ["\195\158"] = "Th", ["\195\190"] = "th",

            -- French
            ["\197\147"] = "oe", ["\197\146"] = "OE",

            -- German
            ["\195\159"] = "B",

            -- Norwegian
            ["\195\152"] = "O", ["\195\184"] = "o",
            ["\195\133"] = "A", ["\195\165"] = "a",

            -- Special punctuation
            ["\226\128\147"] = "-",  ["\226\128\148"] = "-",
            ["\226\128\152"] = "'",  ["\226\128\153"] = "'",
            ["\226\128\156"] = "\"", ["\226\128\157"] = "\"",
            ["\226\128\166"] = "...",
            ["\194\173"]     = "-",
        }
        s = s:gsub("[\194-\244][\128-\191]*", replacements)
        return s:gsub("[^%w%s;:!@#%$%%^&*()%-+=%?,]", ""):trim()
    end

    local ns1 = string.lower(sanitize(s1))
    local ns2 = string.lower(sanitize(s2))

    return ns1 == ns2
end

--- Searches a game table for an item by name using both import system and fallback lookup.
--- First attempts to find the item using the import system's existing item lookup,
--- then falls back to manual table iteration with sanitized string matching.
--- @param tableName string The name of the Codex game table to search
--- @param name string The name of the item to find
--- @return string|nil id The GUID of the matching item if found, nil otherwise
--- @return table|nil row The complete item data if found, nil otherwise
function FSCIUtils.TableLookupFromName(tableName, name)
    FSCIUtils.writeDebug("TFLN:: [%s] [%s]", tableName, name)

    local translatedName = FSCIUtils.TranslateFStoCodex(name)
    FSCIUtils.writeDebug("TFLN:: TRANSLATED:: [%s]", translatedName)

    if import then
        local itemFound = import:GetExistingItem(tableName, translatedName)
        if itemFound then return itemFound.id, itemFound end
    end

    FSCIUtils.writeLog(string.format("TLFN fallthrough table [%s]->[%s].", tableName, translatedName), FSCIUtils.STATUS.WARN)

    local t = dmhub.GetTable(tableName) or {}
    for id, row in pairs(t) do
        if not row:try_get("hidden", false) and FSCIUtils.SanitizedStringsMatch(row.name, translatedName) then
            return id, row
        end
    end

    return nil, nil
end

function FSCIUtils.TranslateFeatureChoiceToCodex(name, description)
    local s = name or ""
    if string.lower(s) == "damage modifier" then
        s = string.match(description, "^(.*Immunity)")
    else
        s = FSCIUtils.TranslateFStoCodex(s)
    end
    return s
end

--- Translates Forge Steel strings to Codex equivalents using FSCI_TRANSLATIONS.
--- @param fsString string The Forge Steel string to translate
--- @return string The translated string or original if no translation exists
function FSCIUtils.TranslateFStoCodex(fsString)
    return FSCI_TRANSLATIONS[fsString] or fsString
end

--- FSCIFillFlattener handles flattening hierarchical feature structures from both
--- FSCILeveledChoiceImporter (leveled features) and FSCIChoiceImporter (direct features)
--- @class FSCIFillFlattener: GameType
FSCIFillFlattener = RegisterGameType("FSCIFillFlattener")
FSCIFillFlattener.__index = FSCIFillFlattener

--- Static configuration for target types and properties to keep
FSCIFillFlattener._targetTypes = {
    ["CharacterSkillChoice"] = true,
    ["CharacterFeatChoice"] = true,
    ["CharacterLanguageChoice"] = true,
    ["CharacterFeatureChoice"] = true,
    ["CharacterDeityChoice"] = true,
    ["CharacterSubclassChoice"] = true
}

FSCIFillFlattener._propertiesToKeep = {
    "guid",
    -- "typeName",
    "name",
    "categories",
    "options"
}

--- Helper function to extract only the properties we want from a feature
--- @param feature table The feature to extract properties from
--- @return table extracted The extracted properties
--- @private
function FSCIFillFlattener._extractProperties(feature)
    FSCIUtils.writeDebug("CLASSFILL:: EXTRACT:: %s", json(feature))
    local extracted = {
        __typeName = feature.typeName
    }
    for _, prop in ipairs(FSCIFillFlattener._propertiesToKeep) do
        if feature:try_get(prop) then
            extracted[prop] = feature[prop]
        end
    end
    return extracted
end

--- Recursive function to process features at any level
--- @param features table Array of features to process
--- @param result table Array to store results in
--- @private
function FSCIFillFlattener._processFeatures(features, result)
    if not features then return end

    for _, feature in pairs(features) do
        -- Check if this feature is a target type we want to keep
        if feature.typeName and FSCIFillFlattener._targetTypes[feature.typeName] then
            table.insert(result, FSCIFillFlattener._extractProperties(feature))
        end

        -- Recursively process nested features
        FSCIUtils.writeDebug("CLASSFILL:: FEATURE:: %s", json(feature))
        if feature:try_get("features") then
            FSCIFillFlattener._processFeatures(feature.features, result)
        end
    end
end

--- Flattens leveled features structure (for FSCILeveledChoiceImporter data)
--- @param leveledFeatures table Array of level objects, each containing features
--- @return table Flat array of filtered feature objects
function FSCIFillFlattener.FlattenLeveledFeatures(leveledFeatures)
    local result = {}

    if leveledFeatures then
        for _, level in pairs(leveledFeatures) do
            if level.features and next(level.features) then
                FSCIFillFlattener._processFeatures(level.features, result)
            end
        end
    end

    return result
end

--- Flattens direct features structure (for FSCIChoiceImporter data)
--- @param features table Array of feature objects
--- @return table Flat array of filtered feature objects
function FSCIFillFlattener.FlattenFeatures(features)
    local result = {}

    if features then
        FSCIFillFlattener._processFeatures(features, result)
    end

    return result
end
