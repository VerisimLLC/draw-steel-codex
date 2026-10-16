local mod = dmhub.GetModLoading()

local g_showDirectorWelcome = setting{
    id = "showdirectorwelcome",
    description = "Show Adventure Progress on Start",
    storage = "pergamepreference",
    default = true,
    editor = "check",
    section = "Game",
}

--Which module cover document THIS game has already opened. The cover fallback
--below is a first-start welcome, not a per-session one, and nothing remembered
--that it had fired -- so a director with an adventure module installed got its
--welcome page reopened on every single entry, in every campaign, with no way to
--stop it. Per-game rather than global: installing the same module in a new
--campaign should still get its welcome once.
--
--No description/editor/section on purpose: this is bookkeeping, not something
--anybody should meet in the Game panel (same shape as glossaryhints:toastseen).
local g_shownCoverDocument = setting{
    id = "showncoverdocument",
    default = "",
    storage = "pergamepreference",
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

--Encounter of the Week games show no welcome documents: the player has no
--character at EnterGame (their heroes are pasted during arrival setup, after
--this fires), so the "New Player Welcome" gate below would otherwise open it
--over the encounter. Several signals, any suffices, because the EotW codemod
--may not have loaded yet when we check: its own IsEotwGame; the account's
--EotW slot (lobby.eotwGameid, set by the titlescreen's create/join flows);
--the arrival args the titlescreen parks before entering
--(_G.EotwPendingArrival, keyed by gameid); and an authoring test, parked or
--on the record. All pcall-guarded.
local function IsEotwGame()
    local eotw = false
    pcall(function() eotw = EncounterOfTheWeekGame.IsEotwGame() end)
    if eotw then
        return true
    end
    pcall(function() eotw = (lobby.eotwGameid ~= nil and lobby.eotwGameid == dmhub.gameid) end)
    if eotw then
        return true
    end
    pcall(function()
        local pending = rawget(_G, "EotwPendingArrival")
        eotw = (type(pending) == "table" and pending.gameid ~= nil and pending.gameid == dmhub.gameid)
    end)
    if eotw then
        return true
    end
    --an EotW authoring test: the Director's refresh into player-host mode
    --re-enters the game as a player with no character yet. The request is
    --still parked (_G.EotwPendingTest) when this runs; a test already on
    --the record covers a resume.
    pcall(function()
        local pending = rawget(_G, "EotwPendingTest")
        eotw = (type(pending) == "table" and pending.gameid ~= nil and pending.gameid == dmhub.gameid)
    end)
    if eotw then
        return true
    end
    pcall(function()
        eotw = dmhub.playerHostMode == true and EncounterOfTheWeekGame.GetTest() ~= nil
    end)
    return eotw
end

function ShowDocumentOnStart(docname)
    dmhub.Coroutine(function()

        while (not GameHud.instance) or (not GameHud.instance.documentsPanel) or (not GameHud.instance.documentsPanel.valid) do
            coroutine.yield()
        end

        for i=1,5 do
            coroutine.yield()
        end

        if IsEotwGame() then
            print("EnterGame: Encounter of the Week game; not showing " .. tostring(docname))
            return
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
        --
        -- ONCE per game, though: this is a welcome, and reopening it on every entry
        -- is what "I keep getting the welcome to the delian tomb message and have no
        -- idea how to make it stop" is describing. Only the cover fallback is gated;
        -- the adventure-document branch above is the director's explicit
        -- /setadventuredocument choice and keeps opening each session as before.
        if docid == nil then
            local coverid = GetModuleCoverDocumentId()
            if coverid ~= nil and g_shownCoverDocument:Get() ~= coverid then
                g_shownCoverDocument:Set(coverid)
                docid = coverid
            end
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