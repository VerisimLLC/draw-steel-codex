local mod = dmhub.GetModLoading()

---@class RichTimer
RichTimer = RegisterGameType("RichTimer", "RichTag")
RichTimer.tag = "timer"
RichTimer.identifier = false
RichTimer.clicks = 0

function RichTimer.Create()
    return RichTimer.new{
    }
end

function RichTimer.CreateDisplay(self)
    local resultPanel
    print("TIMER:: CREATE")

    local clicks = self.clicks
    
    resultPanel = gui.Panel {
        width = 100,
        height = 100,
        halign = "left",
        gui.ProgressDice {
            halign = "center",
            valign = "center",
            hmargin = 28,
            vmargin = 28,
            width = 96,
            height = 96,
            thinkTime = 0.01,
            progress = 1,

            -- read the number from the tag text (e.g. [[timer:5]])
            refreshTag = function(element, tag)
                self = tag or self
                if self.clicks ~= clicks then
                    clicks = self.clicks
                    element.data.startTime = element.aliveTime
                    element:SetClass("loaded", false)
                    element.thinkTime = 0.01
                end
                element.data.duration = tonumber(self.identifier) or 5
            end,


            think = function(element)
                if element.data.startTime then
                    local elapsed  = element.aliveTime - element.data.startTime
                    local duration = element.data.duration or 5
                    local progress = math.max(0, 1 - elapsed / duration)

                    element:FireEventTree("progress", progress)

                    if progress <= 0 then
                        element.data.startTime = nil
                        element:SetClass("loaded", true)
                    end
                end
            end,

            press = function(element)
                self.clicks = self.clicks + 1
                self:UploadDocument()
            end,



        },
    }

    return resultPanel
end

MarkdownDocument.RegisterRichTag(RichTimer)
