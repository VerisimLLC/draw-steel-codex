---@meta

--- A 3D miniature standing on the tabletop, made from an STL file (dice.CreateTableFigure). The file is simplified once on a worker thread and cached, so the first load of a big file takes a moment (status is 'loading') and later loads are instant. Drag it to move it; Lua shares where it is. Positions are screen pixels from the top-left, the measure of dmhub.mouseScreenPosition.
--- @class TableFigureLua
--- @field valid boolean (Read-only) false once the figure has been destroyed.
--- @field status string (Read-only) 'loading' while the file is read and simplified, 'ready', or 'error: ...'.
--- @field x number (Read-only) Where the figure stands, x in screen pixels from the left.
--- @field y number (Read-only) Where the figure stands, y in screen pixels from the top.
--- @field yaw number Its turn about its own up, in degrees.
--- @field tilt number How far it leans back from standing straight up at the camera, in degrees (0-85), so the top-down table shows its front.
--- @field height number Its height in screen pixels when standing straight up.
--- @field callbacks {onMove: nil|fun(x: number, y: number, yaw: number), onClick: nil|fun(x: number, y: number), onRightClick: nil|fun(x: number, y: number)} Callbacks: {onMove = function(x, y, yaw), onClick = function(x, y), onRightClick = function(x, y)}. onMove fires when the figure is dragged and let go; yaw is its turn then, as the mouse wheel turns a held figure.
TableFigureLua = {}

--- Stands the figure at (x, y) screen pixels.
--- @param x number
--- @param y number
--- @return nil
function TableFigureLua:SetRest(x, y) end

--- Keeps the figure inside this rectangle (screen pixels from the top-left).
--- @param x1 number
--- @param y1 number
--- @param x2 number
--- @param y2 number
--- @return nil
function TableFigureLua:SetBounds(x1, y1, x2, y2) end

--- Shows or hides the figure.
--- @param visible boolean
--- @return nil
function TableFigureLua:SetVisible(visible) end

--- Uploads the figure's simplified mesh (not the STL) so other clients can make it with dice.CreateTableFigure{blob = id}. callbacks.done(id) on success, callbacks.error(message) on failure. Only once status is 'ready'.
--- @param callbacks {done: fun(blobid: string), error: nil|fun(message: string)}
--- @return nil
function TableFigureLua:Upload(callbacks) end

--- Removes the figure.
--- @return nil
function TableFigureLua:Destroy() end
