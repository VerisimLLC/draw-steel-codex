local mod = dmhub.GetModLoading()

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
        local adventuresDocument = GetCurrentAdventuresDocument()
        local docid = nil
        local bestOrd = nil
        local welcomeDocument = nil
        for k,v in pairs(adventuresDocument.data) do
            if string.lower(v.name or "") == "director welcome" then
                welcomeDocument = k
            end
            if bestOrd == nil or (v.order ~= nil and v.order < bestOrd) then
                bestOrd = v.order
                docid = k
            end
        end

        if docid == nil and welcomeDocument ~= nil then
            dmhub.Execute('setadventuredocument 1 "Director Welcome"')
            docid = welcomeDocument
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