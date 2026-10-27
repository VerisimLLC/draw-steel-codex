---@meta

--- A 3D die resting on the tabletop (dice.CreateTableDie). Click it to roll it in place, drag to move it, drag and release fast to throw it. The engine plays rolls; Lua shares them: the die calls the onRoll(roll) callback when this client rolls it, and other clients replay that record with PlayRoll. Positions are screen pixels from the top-left, the measure of dmhub.mouseScreenPosition.
--- @class TableDieLua
--- @field valid boolean (Read-only) false once the die has been destroyed.
--- @field face number (Read-only) The value on the die's top face.
--- @field x number (Read-only) Where the die rests, x in screen pixels from the left.
--- @field y number (Read-only) Where the die rests, y in screen pixels from the top.
--- @field aboveUI boolean True to draw the die over all the UI, like a roll's dice (the drawer's preview dice). False, the default: it lies on the table, under windows and panels, and a panel over it gets the mouse.
--- @field scale number The die's size (1 is a normal roll's die).
--- @field callbacks {onRoll: nil|fun(roll: table), onMove: nil|fun(x: number, y: number), onRightClick: nil|fun(x: number, y: number)} Callbacks: {onRoll = function(roll), onMove = function(x, y), onRightClick = function(x, y)}. onRoll fires when this client starts a roll (a click or a throw); roll is the record to pass to PlayRoll on the other clients. onMove fires when the die is dragged and put down without a throw.
TableDieLua = {}

--- Puts the die at rest at (x, y) screen pixels showing the face value. yaw turns it about the view axis (degrees); pick chooses among sides with the same value.
--- @param x number
--- @param y number
--- @param face number
--- @param yaw? number
--- @param pick? number
--- @return nil
function TableDieLua:SetRest(x, y, face, yaw, pick) end

--- Plays a roll record (as given to onRoll), elapsed seconds in; one already over just comes to rest where it ended.
--- @param roll table
--- @param elapsed? number
--- @return nil
function TableDieLua:PlayRoll(roll, elapsed) end

--- Keeps throws inside this rectangle (screen pixels from the top-left).
--- @param x1 number
--- @param y1 number
--- @param x2 number
--- @param y2 number
--- @return nil
function TableDieLua:SetBounds(x1, y1, x2, y2) end

--- Shows or hides the die (a hidden die cannot be clicked).
--- @param visible boolean
--- @return nil
function TableDieLua:SetVisible(visible) end

--- Removes the die.
--- @return nil
function TableDieLua:Destroy() end
