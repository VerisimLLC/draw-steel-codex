local mod = dmhub.GetModLoading()

--- A dated line in a project's history that moves no progress: the Director's
--- downtime event roll ("event") or the item the project gave ("gave"). Kept
--- apart from rolls and adjustments so GetProgress never counts them; they
--- live in the project's projectEvents list. The Hero sheet's Downtime tab
--- reads them into its one history.
--- @class DTProjectEvent: DTProgressItem
--- @field new fun(o?: table): DTProjectEvent
--- @field kind string "event" or "gave"
--- @field tableName string The event table rolled on (an event)
--- @field total number The table roll's total (an event)
--- @field text string The table row's text (an event)
--- @field itemId string The item given (gave)
DTProjectEvent = RegisterGameType("DTProjectEvent", "DTProgressItem")
DTProjectEvent.kind = "event"
DTProjectEvent.tableName = ""
DTProjectEvent.total = 0
DTProjectEvent.text = ""
DTProjectEvent.itemId = ""

DTProjectEvent.KIND_EVENT = "event"
DTProjectEvent.KIND_GAVE = "gave"

--- @param args nil|table
--- @return DTProjectEvent
function DTProjectEvent.CreateNew(args)
    args = args or {}
    args.id = args.id or dmhub.GenerateGuid()
    return DTProjectEvent.new(args)
end

--- @return string kind DTProjectEvent.KIND_EVENT or KIND_GAVE
function DTProjectEvent:GetKind()
    return self.kind or DTProjectEvent.KIND_EVENT
end

--- @return string
function DTProjectEvent:GetTableName()
    return self.tableName or ""
end

--- @return number
function DTProjectEvent:GetTotal()
    return self.total or 0
end

--- @return string
function DTProjectEvent:GetText()
    return self.text or ""
end

--- @return string
function DTProjectEvent:GetItemID()
    return self.itemId or ""
end

--- Events never move progress, whatever is stored.
--- @return number
function DTProjectEvent:GetAmount()
    return 0
end

--- @return string
function DTProjectEvent:GetDescription()
    return self:GetText()
end
