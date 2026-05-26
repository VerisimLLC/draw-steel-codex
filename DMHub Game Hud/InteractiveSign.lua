local mod = dmhub.GetModLoading()


RegisterGameType("SignInteractive", "Interactive")

SignInteractive.id = "Sign"
SignInteractive.text = "Sign"

Interactive.Register(SignInteractive)

function SignInteractive.Create()
    return SignInteractive.new{}
end

SignInteractive.displayText = "This is a sign"

function SignInteractive:Interact(controller, token)
    return gui.Label{
        gui.Button{
            classes = {"closeButton"},
            halign = "right",
            valign = "top",
            floating = true,
            click = function(element)
                element.parent:DestroySelf()
            end,
        },
        halign = "center",
        valign = "center",
        width = 800,
        height = 500,
        text = self.displayText,
        bgimage = "panels/square.png",
        bgcolor = "black",
        color = "white",
        fontSize = 40,
        textAlignment = "center",
        captureEscape = true,
        escape = function(element)
            element:DestroySelf()
        end,
    }
end


function SignInteractive:Edit(controller)
    return gui.Panel{
        width = 800,
        height = 500,
        bgimage = "panels/square.png",
        bgcolor = "black",
        halign = "center",
        valign = "center",
        flow = "vertical",
        captureEscape = true,
        escapePriority = EscapePriority.DMHUB_POPUP,
        escape = function(element)
            element:DestroySelf()
        end,

        gui.Button{
            classes = {"closeButton"},
            halign = "right",
            valign = "top",
            floating = true,
            click = function(element)
                element.parent:FireEvent("escape")
            end,
        },

        gui.Input{
            width = 400,
            height = 40,
            fontSize = 14,
            text = self.displayText,
            change = function(element)
                controller:BeginChanges()
                self.displayText = element.text
                controller:CompleteChanges()
            end,
        }
    }
end
