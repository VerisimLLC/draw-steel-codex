local mod = dmhub.GetModLoading()

--- Assembles the Respite wizards and puts them on the Game menu.
RSPDialog = RegisterGameType("RSPDialog")

--- The Director's wizard. Every step it knows about is handed to the shell,
--- which shows whichever one the session's phase calls for.
--- @return Panel
function RSPDialog.CreateDirectorView()
    RSPSession.Ensure()

    local root

    -- The launchable host owns this window's lifetime, so closing is a
    -- request to the parent rather than a DestroySelf.
    local function Close()
        if root ~= nil and root.valid and root.parent ~= nil then
            root.parent:FireEvent("close")
        end
    end

    local function Offer()
        RSPSession.Offer()
        if root ~= nil and root.valid then
            RSPSession.PresentToPlayers(root)
        end
    end

    -- Pushed again when the Respite actually begins, so a player who closed
    -- their window during the offer is not left out of the Respite they are
    -- in. Safe to repeat: the push opens a window on a client that has none
    -- and leaves an open one alone, so it can never shut one in someone's
    -- face.
    local function Start()
        RSPSession.Start()
        if root ~= nil and root.valid then
            RSPSession.PresentToPlayers(root)
        end
    end

    -- Setup is the one phase with nothing to preserve, so closing out of it
    -- throws the Respite away rather than leaving a half-built one sitting in
    -- the document with no way back to it.
    local function Abandon()
        RSPSession.Abandon()
        Close()
    end

    -- TESTING: Complete Respite wipes the Respite so the loop can be run
    -- again from Setup.
    local function Complete()
        RSPSession.HideFromPlayers()
        RSPSession.Complete()
        Close()
    end

    root = RSPShell.Create{
        steps = {
            RSPDirectorSetupPanel.Step(Offer, Abandon),
            RSPDirectorPartPanel.Step(Start),
            RSPDirectorActPanel.Step(Complete),
        },
    }

    return root
end

--- What a player sees. The Game menu opens it, and the Director's offer opens
--- the same window by the same route, so there is only one of these.
--- @return Panel
function RSPDialog.CreatePlayerView()
    local root

    -- The launchable host owns this window's lifetime, so closing is a
    -- request to the parent rather than a DestroySelf.
    local function Close()
        if root ~= nil and root.valid and root.parent ~= nil then
            root.parent:FireEvent("close")
        end
    end

    root = RSPShell.Create{
        steps = {
            RSPPlayerRespitePanel.IdleStep(Close),
            RSPPlayerRespitePanel.Step(),
            RSPPlayerActPanel.Step(),
        },
    }

    return root
end

--- @return Panel|nil
function RSPDialog.Create()
    -- A Respite cannot begin mid-fight: the game mode it puts the table into
    -- is the one combat is already using, so the window is refused outright
    -- rather than opening onto a Respite that could never start.
    if RSPSession.CombatInProgress() then
        gui.ModalMessage{
            title = RSPConstants.panelName,
            message = "A Respite cannot be taken during combat. End the encounter first.",
        }
        return nil
    end

    if dmhub.isDM then
        return RSPDialog.CreateDirectorView()
    end

    return RSPDialog.CreatePlayerView()
end

--- The Director's offer, arriving on a player's client. Rather than building
--- a window of its own it opens the Game menu's, so a Respite raised for a
--- player is the same window in the same host they would have opened.
---
--- Presenting a dialog only calls this to have a panel built; returning
--- nothing leaves the presentation machinery with nothing to tear down, so
--- ending the Respite leaves the window standing on its idle step rather than
--- yanking it away mid-click.
--- @return nil
function RSPDialog.RaiseForPlayer()
    if dmhub.isDM or RSPSession.Active() == nil then
        return nil
    end

    -- LaunchPanelByName toggles, so a player who already opened it from the
    -- menu would have it shut in their face. Asking first is per-client: this
    -- runs on each player's own machine.
    if not RSPShell.IsOpen() then
        LaunchablePanel.LaunchPanelByName(RSPConstants.panelName)
    end

    return nil
end

GameHud.RegisterPresentableDialog{
    id = RSPConstants.dialogId,
    keeplocal = false,
    create = RSPDialog.RaiseForPlayer,
}

-- LaunchablePanel.Register is keyed by name, so this replaces the stock
-- Respite entry rather than sitting beside it.
LaunchablePanel.Register{
    name = RSPConstants.panelName,
    menu = "game",
    icon = RSPConstants.icon,
    halign = "center",
    valign = "center",
    content = function()
        return RSPDialog.Create()
    end,
}
