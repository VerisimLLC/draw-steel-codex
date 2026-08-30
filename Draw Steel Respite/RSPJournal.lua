local mod = dmhub.GetModLoading()

--- Writes a finished Respite up as a journal document.
--- Everything here reads the Respite that is ending, so it has to run before
--- the session is cleared away. The activities supply their own words: this
--- file knows how to lay a document out and nothing about what happened in it.
RSPJournal = RegisterGameType("RSPJournal")

--- The folder the write-ups go in, or nil when it does not exist yet
--- @return string|nil folderid
local function FolderId()
    for id, folder in pairs(assets.documentFoldersTable or {}) do
        if folder.description == RSPConstants.journalFolder
            and tostring(folder.parentFolder) == RSPConstants.journalRoot then
            return id
        end
    end
    return nil
end

--- A name no document in the table is using
--- Today's date, then the usual bracketed number when the table already holds
--- one - a Respite can end more than once in a day.
--- @return string
local function UniqueName()
    local base = string.format("Respite %s", os.date("%Y-%m-%d"))

    local taken = {}
    for _, doc in pairs(dmhub.GetTable(CustomDocument.tableName) or {}) do
        taken[doc.description or ""] = true
    end

    if not taken[base] then
        return base
    end

    local n = 1
    while taken[string.format("%s (%d)", base, n)] do
        n = n + 1
    end
    return string.format("%s (%d)", base, n)
end

--- The characters this Respite was taken by
--- Those who ticked in, not everyone it covered: the list doubles as the record
--- of who actually got a Respite in the game's terms.
--- @return string[] charids
local function Participants()
    local result = {}
    for _, charid in ipairs(RSPSession.Roster()) do
        if RSPSession.IsParticipating(charid) then
            result[#result + 1] = charid
        end
    end
    return result
end

--- The activities the Director left switched on, in the order they register
--- @return table[] activities
local function OfferedActivities()
    local result = {}

    local registry = rawget(_G, "RSPActivity")
    if registry == nil then
        return result
    end

    for _, activity in ipairs(registry.All()) do
        if RSPSession.IsActivityAvailable(activity.key) then
            result[#result + 1] = activity
        end
    end

    return result
end

--- Builds the document's text
--- Words only. Token art in a generated document has never rendered reliably -
--- the Montage write-ups fought it and lost - so the layout does not depend on
--- it and the tables it would have needed are gone with it.
--- @return string markdown
function RSPJournal.Build()
    local lines = {}

    lines[#lines + 1] = string.format("*%s*", os.date("%A, %d %B %Y"))
    lines[#lines + 1] = ""

    local location = RSPSession.Location()
    if location ~= "" then
        lines[#lines + 1] = string.format("**Location:** %s", location)
    end

    lines[#lines + 1] = string.format("**Days Elapsed:** %d",
        RSPSession.DaysElapsed())
    lines[#lines + 1] = string.format("**Downtime Activities:** %d",
        RSPSession.ActivityCount())

    local activities = OfferedActivities()
    local names = {}
    for _, activity in ipairs(activities) do
        names[#names + 1] = activity.name
    end
    lines[#lines + 1] = string.format("**Activities:** %s",
        #names > 0 and table.concat(names, ", ") or "None")

    -- What each activity has to say about its own setup, if anything.
    for _, activity in ipairs(activities) do
        local detail = activity:try_get("journalDetail")
        if detail ~= nil then
            local text = detail()
            if text ~= nil and text ~= "" then
                lines[#lines + 1] = string.format("**%s Detail:** %s",
                    activity.name, text)
            end
        end
    end

    -- Who took it belongs with the rest of the terms rather than in a section
    -- of its own now that it is a list of names.
    local participants = Participants()
    local who = {}
    for _, charid in ipairs(participants) do
        local token = dmhub.GetCharacterById(charid)
        if token ~= nil then
            who[#who + 1] = token.name or "Unnamed Hero"
        end
    end
    lines[#lines + 1] = string.format("**Participants:** %s",
        #who > 0 and table.concat(who, ", ") or "Nobody")

    -- What everyone got up to. The whole roster, not just the participants:
    -- a milestone belongs to whoever owns the project, and somebody else's roll
    -- can carry it there. Leaving that out of the write-up hid the very thing
    -- the Director has to deal with. A character nobody has anything to say
    -- about is left out rather than given an empty heading, so the section only
    -- grows by the people who actually did something.
    local told = {}
    for _, charid in ipairs(RSPSession.Roster()) do
        local said = {}
        for _, activity in ipairs(activities) do
            local summarise = activity:try_get("journalSummary")
            if summarise ~= nil then
                -- since, as the Director's feed gets it: an activity that
                -- reports against a window needs one, or it reports the whole
                -- campaign.
                local entries = summarise{
                    charid = charid,
                    since = RSPSession.StartedAt,
                }
                for _, entry in ipairs(entries or {}) do
                    said[#said + 1] = entry
                end
            end
        end

        if #said > 0 then
            told[#told + 1] = {charid = charid, said = said}
        end
    end

    if #told > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "## What Happened"

        for _, entry in ipairs(told) do
            local token = dmhub.GetCharacterById(entry.charid)

            lines[#lines + 1] = ""
            lines[#lines + 1] = string.format("### %s",
                (token ~= nil and token.name) or "Unnamed Hero")
            lines[#lines + 1] = ""

            for _, said in ipairs(entry.said) do
                lines[#lines + 1] = string.format("- %s", said)
            end
        end
    end

    return table.concat(lines, "\n")
end

--- Writes the document into the Respites folder
--- @param folderid string
local function Upload(folderid)
    local markdown = RSPJournal.Build()

    local doc = MarkdownDocument.new{
        id = dmhub.GenerateGuid(),
        parentFolder = folderid,
        description = UniqueName(),
        annotations = {},
    }

    doc:SetTextContent(markdown)
    doc:Upload()
end

--- Writes the Respite up, making the folder first if this is the first time
--- Creating a folder hands nothing back, so the id has to be looked up again
--- once the table has caught up. A Respite that cannot find its folder is
--- written to the Shared Documents root rather than thrown away.
function RSPJournal.Write()
    if not dmhub.isDM then
        return
    end

    local folderid = FolderId()
    if folderid ~= nil then
        Upload(folderid)
        return
    end

    -- Everything the write-up reads is gone by the time this comes back, so
    -- the document is built now and only its home is waited on.
    local markdown = RSPJournal.Build()
    local name = UniqueName()

    assets:UploadNewDocumentFolder{
        description = RSPConstants.journalFolder,
        parentFolder = RSPConstants.journalRoot,
    }

    dmhub.Schedule(0.5, function()
        if mod.unloaded then
            return
        end

        local doc = MarkdownDocument.new{
            id = dmhub.GenerateGuid(),
            parentFolder = FolderId() or RSPConstants.journalRoot,
            description = name,
            annotations = {},
        }

        doc:SetTextContent(markdown)
        doc:Upload()
    end)
end
