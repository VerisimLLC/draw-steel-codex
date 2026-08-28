local mod = dmhub.GetModLoading()

--- The open body of water
--- One at a time, opened and closed by the Director, and the only gate on
--- whether players may start fishing. Held in a shared document so every client
--- sees the same water without the module pushing anything.
--- @class FSHWater
FSHWater = RegisterGameType("FSHWater")

local documentName = "fsh_water"

--- Gets the path for document monitoring in UI
--- @return string path The document path for monitoring
function FSHWater.GetDocumentPath()
    return mod:GetDocumentSnapshot(documentName).path
end

--- Returns the water document, initializing it when absent
--- @return table doc The water document
function FSHWater._safeDoc()
    local doc = mod:GetDocumentSnapshot(documentName)
    if doc.data == nil or type(doc.data) ~= "table" then
        doc:BeginChange()
        doc.data = {
            open = false
        }
        doc:CompleteChange("Initialize fishing water", { undoable = false })
    end
    return doc
end

--- Determines whether a water is currently open
--- @return boolean open True when players may start fishing
function FSHWater.IsOpen()
    return FSHWater._safeDoc().data.open == true
end

--- Gets the name of the open water
--- @return string name The water name, empty when unnamed or closed
function FSHWater.GetName()
    return FSHWater._safeDoc().data.name or ""
end

--- Gets the type of the open water
--- @return string waterType An FSHConstants.WATER_TYPE key
function FSHWater.GetWaterType()
    return FSHWater._safeDoc().data.waterType or FSHConstants.WATER_TYPE.FRESH.key
end

--- Gets the id of the current session
--- Trips and log entries carry this, so closing the water and opening another
--- separates one outing's content from the next without deleting anything.
--- @return string sessionId The session id, empty when no water has been opened
function FSHWater.GetSessionID()
    return FSHWater._safeDoc().data.sessionId or ""
end

--- Gets when the current water was opened
--- @return number openedAt The server time the water opened, zero when never
function FSHWater.GetOpenedAt()
    return FSHWater._safeDoc().data.openedAt or 0
end

--- What the ancient fish is owed, by character
--- A hero who fails the Might test on event 9 ends the Respite one Recovery
--- down, but the debt cannot be taken until the Respite has rested them: usage
--- recorded before the rest is stamped with the old refresh id and ignored. So
--- it is parked here until the Respite says everyone has been rested.
--- Kept on the water rather than the Trip because a Trip is closed and filed
--- long before the Respite ends.
--- @return table owed charid to the number of Recoveries owed
function FSHWater.OwedRecoveries()
    return FSHWater._safeDoc().data.owedRecoveries or {}
end

--- Records that a character owes a Recovery
--- Written by whichever client answered the event, the way a Trip is.
--- @param charid string The character's id
function FSHWater.OweRecovery(charid)
    if charid == nil or charid == "" then
        return
    end

    local doc = FSHWater._safeDoc()
    doc:BeginChange()

    --Rebuilt rather than mutated in place: handing a document back a table it
    --already owns does not reliably carry the new value.
    local owed = {}
    for id, count in pairs(doc.data.owedRecoveries or {}) do
        owed[id] = count
    end
    owed[charid] = (owed[charid] or 0) + 1
    doc.data.owedRecoveries = owed

    doc:CompleteChange("Owe a fishing Recovery", { undoable = false })
end

--- Forgets every outstanding Recovery debt
--- Called once the debts have been taken, so a second Respite cannot charge for
--- the same ancient fish.
function FSHWater.ClearOwedRecoveries()
    local doc = FSHWater._safeDoc()
    doc:BeginChange()
    doc.data.owedRecoveries = {}
    doc:CompleteChange("Clear fishing Recovery debts", { undoable = false })
end

--- Describes the water for the panel header
--- @return string description The name and type, or a closed notice
function FSHWater.Describe()
    if not FSHWater.IsOpen() then
        return "No water is open"
    end

    local typeText = string.format("%s Water",
        DTConstants.GetDisplayText(FSHConstants.WATER_TYPE, FSHWater.GetWaterType()))
    local name = FSHWater.GetName()
    if name == "" then
        return string.format("Open water  |  %s", typeText)
    end

    return string.format("%s  |  %s", name, typeText)
end

--- Normalizes a water type, falling back to Fresh
--- @param waterType any The candidate water type
--- @return string waterType A valid FSHConstants.WATER_TYPE key
function FSHWater._validWaterType(waterType)
    for _, valid in ipairs(FSHConstants.WATER_TYPE) do
        if waterType == valid.key then
            return valid.key
        end
    end
    return FSHConstants.WATER_TYPE.FRESH.key
end

--- Opens a water, making Start Fishing available to every player
--- Starts a new session, which is what separates this outing's log from the
--- last one. Director only.
--- @param name string|nil Optional water name
--- @param waterType string An FSHConstants.WATER_TYPE key
--- @return boolean opened True when the water was opened
function FSHWater.Open(name, waterType)
    if not dmhub.isDM then
        return false
    end

    local doc = FSHWater._safeDoc()
    doc:BeginChange()
    doc.data = {
        open = true,
        name = type(name) == "string" and name or "",
        waterType = FSHWater._validWaterType(waterType),
        sessionId = dmhub.GenerateGuid(),
        openedAt = dmhub.serverTime
    }
    doc:CompleteChange("Open fishing water", { undoable = false })

    return true
end

--- Closes the water, blocking new Trips
--- Never interrupts a Trip already running: those finish on their own terms,
--- shop included. Director only.
--- @return boolean closed True when the water was closed
function FSHWater.Close()
    if not dmhub.isDM then
        return false
    end

    local doc = FSHWater._safeDoc()
    doc:BeginChange()
    doc.data = {
        open = false,
        sessionId = doc.data.sessionId,
        --Kept through the close: the Respite's setup fields are where the name
        --and type are chosen, and a Respite that ends should not blank what
        --the Director typed for the next one.
        name = doc.data.name,
        waterType = doc.data.waterType,
        --Also kept, and for a harder reason: the Respite closes the water on
        --its way out, before it rests anybody. The debts are taken after that
        --rest, so wiping them here would forgive every one of them.
        owedRecoveries = doc.data.owedRecoveries
    }
    doc:CompleteChange("Close fishing water", { undoable = false })

    return true
end

--- Renames the open water without disturbing the session
--- Open() starts a new session every time, so it cannot be reused to edit a
--- water already in use. Usable before the water is opened, so a Respite can
--- settle the name and type ahead of time. Director only.
--- @param name string|nil The water name, blank when nil
--- @return boolean changed True when the name was written
function FSHWater.SetName(name)
    if not dmhub.isDM then
        return false
    end

    local doc = FSHWater._safeDoc()
    doc:BeginChange()
    doc.data.name = type(name) == "string" and name or ""
    doc:CompleteChange("Rename fishing water", { undoable = false })

    return true
end

--- Changes the type of the open water without disturbing the session
--- Director only.
--- @param waterType string An FSHConstants.WATER_TYPE key
--- @return boolean changed True when the type was written
function FSHWater.SetWaterType(waterType)
    if not dmhub.isDM then
        return false
    end

    local doc = FSHWater._safeDoc()
    doc:BeginChange()
    doc.data.waterType = FSHWater._validWaterType(waterType)
    doc:CompleteChange("Change fishing water type", { undoable = false })

    return true
end
