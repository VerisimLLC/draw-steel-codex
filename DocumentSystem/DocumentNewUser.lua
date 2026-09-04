local mod = dmhub.GetModLoading()

local g_showDirectorWelcome = setting{
    id = "showdirectorwelcome",
    description = "Show Adventure Progress on Start",
    storage = "pergamepreference",
    default = true,
    editor = "check",
    section = "Game",
}

-- Returns the document id of an installed module's "Cover Document" (set when
-- the module was published via ModShare's Cover Document dropdown), or nil if
-- no loaded module has one whose document is present. Used as the director's
-- fallback welcome when no adventure document has been registered, so a
-- campaign module (e.g. Crows) can show a welcome on first start without the
-- director manually setting an adventure document. Picks the first loaded
-- module that has a cover document.
local function GetModuleCoverDocumentId()
    local documents = dmhub.GetTable(CustomDocument.tableName) or {}
    for _, moduleInfo in ipairs(module.GetLoadedModules()) do
        local coverid = moduleInfo.coverDocumentId
        if coverid ~= nil and coverid ~= "" and documents[coverid] ~= nil then
            return coverid
        end
    end
    return nil
end

function ShowDocumentOnStart(docname)
    dmhub.Coroutine(function()

        while (not GameHud.instance) or (not GameHud.instance.documentsPanel) or (not GameHud.instance.documentsPanel.valid) do
            coroutine.yield()
        end

        for i=1,5 do
            coroutine.yield()
        end

        print("EnterGame: Display")

        local description = string.lower(docname)
        local customDocs = dmhub.GetTable(CustomDocument.tableName) or {}
        for k,doc in unhidden_pairs(customDocs) do
            if string.lower(k) == description or string.lower(doc.description) == description then
                print("EnterGame: ShowDocument")
                doc:ShowDocument()
                return
            end
        end
    end)

end

dmhub.RegisterEventHandler("EnterGame", function()
    if dmhub.isDM then
        if not g_showDirectorWelcome:Get() then
            return
        end

        local adventuresDocument = GetCurrentAdventuresDocument()
        local docid = nil
        local bestOrd = nil
        local welcomeDocument = nil
        for k,v in pairs(adventuresDocument.data) do
            -- 'meta' holds the adventure panel's title/icon, not a document.
            if k ~= "meta" then
                if string.lower(v.name or "") == "director welcome" then
                    welcomeDocument = k
                end
                if bestOrd == nil or (v.order ~= nil and v.order < bestOrd) then
                    bestOrd = v.order
                    docid = k
                end
            end
        end

        if docid == nil and welcomeDocument ~= nil then
            dmhub.Execute('setadventuredocument 1 "Director Welcome"')
            docid = welcomeDocument
        end

        -- No adventure document registered: fall back to an installed module's
        -- cover document, if one was set when the module was published. Lets a
        -- campaign module show a director welcome on start without the director
        -- registering an adventure document by hand.
        if docid == nil then
            docid = GetModuleCoverDocumentId()
        end

        if docid ~= nil then
            ShowDocumentOnStart(docid)
        end
    end

    if dmhub.isDM or dmhub.currentToken ~= nil then
        print("EnterGame: HAS TOKEN")
        return
    end

    --see if we already have a character assigned.
    local characters = game.GetGameGlobalCharacters()
    for _,token in ipairs(characters) do
        if token.ownerId == dmhub.userid then
            print("EnterGame: HAS CHARACTER")
            return
        end
    end


    ShowDocumentOnStart("New Player Welcome")
end)

print("Loaded:: xxx")