local mod = dmhub.GetModLoading()

--- Assembles the Respite wizards and puts them on the Game menu.
RSPDialog = {}

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

    -- TESTING: Complete Respite wipes the Respite so the loop can be run
    -- again from Setup.
    local function Complete()
        RSPSession.HideFromPlayers()
        RSPSession.Complete()
        Close()
    end

    root = RSPShell.Create{
        steps = {
            RSPDirectorSetupPanel.Step(Offer, Close),
            RSPDirectorPartPanel.Step(RSPSession.Start),
            RSPDirectorActPanel.Step(Complete),
        },
    }

    return root
end

--- What a player sees. Reached from the Game menu at any time, and pushed onto
--- their screen when the Director offers a Respite. The two arrive by
--- different routes, so the caller says how its copy is dismissed.
--- @param args {framed: nil|boolean, makeClose: fun(root: Panel): fun()}
--- @return Panel
function RSPDialog.CreatePlayerView(args)
    local root

    root = RSPShell.Create{
        framed = args.framed,
        steps = {
            RSPPlayerRespitePanel.IdleStep(function()
                args.makeClose(root)()
            end),
            RSPPlayerRespitePanel.Step(),
            RSPPlayerActPanel.Step(),
        },
    }

    return root
end

--- @return Panel
function RSPDialog.Create()
    if dmhub.isDM then
        return RSPDialog.CreateDirectorView()
    end

    -- Launched from the Game menu, so the launchable host owns the window
    -- and paints the frame around it.
    return RSPDialog.CreatePlayerView{
        makeClose = function(root)
            return function()
                if root ~= nil and root.valid and root.parent ~= nil then
                    root.parent:FireEvent("close")
                end
            end
        end,
    }
end

--- The pushed copy. Returning nil leaves the Director's own screen alone, and
--- keeps the push from raising a window with nothing in it.
--- @return Panel|nil
function RSPDialog.CreatePresentedPlayerView()
    if dmhub.isDM or RSPSession.Active() == nil then
        return nil
    end

    -- Pushed onto the hud rather than hosted, so it draws its own frame, and
    -- closing is local to this client: the Respite carries on without it.
    return RSPDialog.CreatePlayerView{
        framed = true,
        makeClose = function(root)
            return function()
                if root ~= nil and root.valid then
                    root:DestroySelf()
                end
            end
        end,
    }
end

GameHud.RegisterPresentableDialog{
    id = RSPConstants.dialogId,
    keeplocal = false,
    create = RSPDialog.CreatePresentedPlayerView,
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
