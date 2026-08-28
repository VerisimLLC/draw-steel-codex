local mod = dmhub.GetModLoading()

--Monster Builder launcher: a Tools-menu entry and (optional) icon-rail
--button that opens the Monster Builder in the Draw Steel companion app.
--dmhub.OpenCompanionTool prefers a window in the bundled desktop
--companion -- reusing a running instance when there is one -- and falls
--back to draw-steel-codex.com/monsters in the browser; either way the
--session is signed in via the same handoff character popouts use.
--
--This is an ACTION registration (launch = fn, no content): activating it
--runs the launch and no panel window ever opens. Players never see it --
--the Monster Builder is a Director tool.

DockablePanel.Register{
    name = "Body Banks",
    icon = "phosphor/hammer.png",
    menu = "tools",
    dmonly = true,
    launch = function()
        dmhub.OpenCompanionTool("/monsters", function(msg)
            gui.ModalMessage{
                title = "Body Banks",
                message = "Couldn't open the Body Banks:\n\n" .. tostring(msg),
            }
        end)
    end,
}
