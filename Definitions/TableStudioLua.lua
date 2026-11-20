---@meta

--- The Table Studio: authoring tabletop backgrounds as data (a type, textures, settings and a layout), previewed live on the table while the studio is open. Admin-only. See TABLE_STUDIO_PLAN.md.
--- @class TableStudioLua
--- @field hasTable boolean True once a table has been started or loaded.
--- @field name string The table's name: empty until it is first saved.
--- @field type string The table's type id (fixed once the table is created).
--- @field preset string The id of the built-in table it started from.
--- @field hasUnsavedChanges boolean True if the table differs from its last save (or, never saved, from its starting table).
--- @field changeSeq number Bumped on every change, for panels that redraw when it moves.
--- @field previewing boolean While true, the table shows the table being edited instead of this user's own. The panel sets it while it is open.
--- @field comparing boolean While true, the preview shows the table's last save (Compare).
--- @field logoPreview string Which logo and logo layout the preview shows: "" for this build's white label, "drawsteel" or "dmhub".
--- @field paused boolean While true, the table's motion is frozen.
--- @field builtin string The built-in tabletop the open table is ("soulkiller"), or "" for a table made in the studio.
--- @field version number The version being edited.
--- @field liveVersion number The table's live version, or 0 if none is live.
--- @field isLiveVersion boolean True if the version open is the live one. Its first edit starts nextVersion.
--- @field nextVersion number The number the next new version gets.
--- @field notes string The version's notes.
--- @field access string Who gets the table: "everyone", "dice" for the owners of the dice set `dice`, or "nobody" (unpublished: set live, it leaves players' menus).
--- @field dice string The dice set (a dice asset id) the table is linked to, or "".
--- @field menuName string The table's name in the players' menu ("" uses its name).
--- @field position number The table's place in the players' menu, lower first (the built-ins are 1 to 9).
--- @field sendState string The last Upload or Set Live: "" (none yet), "sending", "sent" or "failed".
--- @field viewAsPlayer boolean View as Player: while true, this admin's table menus offer only what this account would get without admin rights (the Table Studio's switch; Tabletop.lua reads it). Not saved.
TableStudioLua = {}

--- The seven table types: a list of {id, reflects, parallax, tiled, timed}.
--- @return table
function TableStudioLua:GetTypes() end

--- The built-in tables a new table can start from: a list of {id, type}, ids as dmhub.tabletopSurface uses them.
--- @return table
function TableStudioLua:GetPresets() end

--- Starts a new, unsaved table as a copy of a built-in one (an id from GetPresets). False if that table can't be loaded.
--- @param presetId? string
--- @return boolean
function TableStudioLua:NewTable(presetId) end

--- Plays the type's timed effect (glint, forge, pulse) now. False if the type has none.
--- @return boolean
function TableStudioLua:PlayNow() end

--- The shader's editable settings: a list of {name, type ("float", "range", "color", "vector" or "texture"), description, min, max}. Settings the engine sets itself are left out.
--- @return table
function TableStudioLua:GetProperties() end

--- A number setting's value.
--- @param prop? string
--- @return number
function TableStudioLua:GetFloat(prop) end

--- The starting table's value for a number setting (what Reset to Default restores).
--- @param prop? string
--- @return number
function TableStudioLua:GetDefaultFloat(prop) end

--- Sets a number setting; the table shows it at once.
--- @param prop? string
--- @param value? number
function TableStudioLua:SetFloat(prop, value) end

--- A colour setting's value.
--- @param prop? string
--- @return any
function TableStudioLua:GetColor(prop) end

--- The starting table's value for a colour setting.
--- @param prop? string
--- @return any
function TableStudioLua:GetDefaultColor(prop) end

--- Sets a colour setting.
--- @param prop? string
--- @param color? any
function TableStudioLua:SetColor(prop, color) end

--- One component (1 = x .. 4 = w) of a vector setting. Shaders pack several knobs into one vector; the panel shows each as its own slider.
--- @param prop? string
--- @param index? number
--- @return number
function TableStudioLua:GetVectorComponent(prop, index) end

--- The starting table's value for one component of a vector setting.
--- @param prop? string
--- @param index? number
--- @return number
function TableStudioLua:GetDefaultVectorComponent(prop, index) end

--- Sets one component (1 = x .. 4 = w) of a vector setting.
--- @param prop? string
--- @param index? number
--- @param value? number
function TableStudioLua:SetVectorComponent(prop, index, value) end

--- A colour stored in linear light in a vector setting (a lava or forge ramp stop), as a colour for a colour picker.
--- @param prop? string
--- @return any
function TableStudioLua:GetLinearColor(prop) end

--- The starting table's linear colour for a vector setting.
--- @param prop? string
--- @return any
function TableStudioLua:GetDefaultLinearColor(prop) end

--- Sets a vector setting's rgb from a colour picker's colour, converted to linear light (its w is kept).
--- @param prop? string
--- @param color? any
function TableStudioLua:SetLinearColor(prop, color) end

--- The layout: {tileSize (screen heights per tile), offsetX, offsetY (fractions of a tile), showLogo}.
--- @return table
function TableStudioLua:GetLayout() end

--- The starting table's layout, as GetLayout.
--- @return table
function TableStudioLua:GetDefaultLayout() end

--- Sets the layout from a table with any of tileSize, offsetX, offsetY, showLogo.
--- @param layout? any
function TableStudioLua:SetLayout(layout) end

--- The type's texture slots: a list of {prop, kind ("colour", "data" or "logo"), state ("builtin", "loading" or "loaded"), builtin, assetid, width, height}.
--- @return table
function TableStudioLua:GetTextures() end

--- Replaces a texture slot with an uploaded image (a cloud image asset id, as from an image picker), or nil / "" to put the built-in texture back. False for an unknown slot or image.
--- @param prop? string
--- @param assetid? string
--- @return boolean
function TableStudioLua:SetTexture(prop, assetid) end

--- The names of the tables saved on this machine.
--- @return string[]
function TableStudioLua:GetLocalTables() end

--- Opens a table saved on this machine. False if it can't be read.
--- @param name? string
--- @return boolean
function TableStudioLua:Load(name) end

--- Saves the table under its name. False if it has none yet (use SaveAs).
--- @return boolean
function TableStudioLua:Save() end

--- Saves the table under a new name, as a new table. False if the name is empty once characters a folder can't hold are removed.
--- @param name? string
--- @return boolean
function TableStudioLua:SaveAs(name) end

--- Goes back to the table's last save, dropping the changes since.
function TableStudioLua:Revert() end

--- Writes the unsaved changes to the draft file (the panel calls this every few seconds while there are any).
function TableStudioLua:SaveDraft() end

--- The autosaved draft, if there is one: {name ("" for a table never saved), savedAt (unix seconds)}; nil if none.
--- @return any
function TableStudioLua:GetDraft() end

--- Opens the autosaved draft as the table being edited. False if there is none.
--- @return boolean
function TableStudioLua:RestoreDraft() end

--- Deletes the autosaved draft.
function TableStudioLua:DiscardDraft() end

--- Peek: hides windows and panels until the mouse button is released. Call it from a press.
function TableStudioLua:HoldPeek() end

--- Compare: shows the table's last save until the mouse button is released. Call it from a press.
function TableStudioLua:HoldCompare() end

--- Writes the texture a slot shows now to a PNG in the TableStudio Exports folder (a starting file in the right format). Its path, or nil.
--- @param prop? string
--- @return string
function TableStudioLua:ExportTexture(prop) end

--- "picture" if the image uploaded to a data-map slot looks like an ordinary picture rather than a data map; nil otherwise, and while it loads.
--- @param prop? string
--- @return string
function TableStudioLua:GetTextureWarning(prop) end

--- Opens a built-in tabletop (an id from GetPresets) for editing: the work saved on this machine, else its live version, else the built-in itself, named name, linked to the dice asset id dice (or nil) and at position in the players' menu. Set live, it replaces that tabletop. False if it can't be loaded.
--- @param id? string
--- @param name? string
--- @param dice? string
--- @param position? number
--- @return boolean
function TableStudioLua:EditBuiltin(id, name, dice, position) end

--- The table's saved versions, lowest first, as a list of {version, status}; status is "live", "uploaded", "changed" (since upload) or "local". The version open is included even if it isn't saved yet.
--- @return table
function TableStudioLua:GetVersions() end

--- Opens one of the table's saved versions. False if it can't be read.
--- @param version? number
--- @return boolean
function TableStudioLua:LoadVersion(version) end

--- Sets who gets the table ("everyone", "dice" or "nobody") and its dice set (a dice asset id, or "").
--- @param access? string
--- @param dice? string
function TableStudioLua:SetAccess(access, dice) end

--- Sets the table's menu name and place.
--- @param menuName? string
--- @param position? number
function TableStudioLua:SetMenu(menuName, position) end

--- Who gets the live version of the open table now, as {access, dice}; nil if none is live.
--- @return any
function TableStudioLua:GetLiveAccess() end

--- Saves the version and uploads it to the admin-only version history. Players see nothing. False if it couldn't start (no name yet: SaveAs first). Progress is in sendState.
--- @return boolean
function TableStudioLua:Upload() end

--- Saves the version, uploads it and makes it the version players get (replacing the built-in, for an edited built-in tabletop). False if it couldn't start. Progress is in sendState.
--- @return boolean
function TableStudioLua:SetLive() end

--- Repeats the last Upload or Set Live.
--- @return boolean
function TableStudioLua:RetrySend() end

--- The tables saved on this machine with who gets them: a list of {name, type, access, dice}.
--- @return table
function TableStudioLua:GetTableList() end

--- Live tables made in the studio that this machine has no files for: a list of {id, name, type, access, dice}.
--- @return table
function TableStudioLua:GetCloudTables() end

--- Opens a live table from GetCloudTables and keeps it on this machine. False if it isn't live.
--- @param id? string
--- @return boolean
function TableStudioLua:OpenCloudTable(id) end
