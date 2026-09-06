---@meta

--- Provides Lua access to the code mod system, allowing listing, creating, deleting, and diffing code mods.
--- @class code
--- @field hasGit boolean True if Git is available on the system for code mod version control.
--- @field loadedMods string[] Returns a list of all code mod IDs currently loaded in the game, including global mods.
--- @field loadedModsLocalToGame string[] Returns a list of code mod IDs that are loaded locally for the current game only.
--- @field loadedModsFromModules string[] Returns a deduplicated list of code mod IDs that were installed into the current game by module dependencies (i.e. came from gameInfo.codeModsFromModules rather than being authored locally). Used by the module publishing UI so codemods pulled in from dependencies can be explicitly bundled into a new module version.
--- @field monitorid string The ID of the code mod currently being monitored for live changes.
--- @field logEvent EventSourceLua The event that fires when a code mod log entry is added.
--- @field modifyEvent EventSourceLua The event that fires when a code mod is modified.
code = {}

--- Opens the code development configuration file in an external editor.
function code.UserEditCodeDevConfig() end

--- Retrieves the source code text for a code file identified by its MD5 hash.
--- @param md5 string The MD5 hash of the code file.
--- @return string
function code.GetCodeFromMD5(md5) end

--- Returns a CodeModLua wrapper for the code mod with the given ID.
--- @return CodeModLua
--- @param modid? string
function code.GetMod(modid) end

--- Launches an external diff tool to compare two code files identified by their MD5 hashes.
--- @param md5a? string
--- @param md5b? string
function code.LaunchExternalDiff(md5a, md5b) end

--- Computes a line-by-line diff between two strings. Returns a list of entries, each with optional 'common', 'a', and 'b' keys containing arrays of lines.
--- @return table[]
--- @param a? string
--- @param b? string
function code.Diff(a, b) end

--- Returns true if the given mod can be deleted from the current game.
--- @param modid? string
--- @return boolean
function code.CanDeleteMod(modid) end

--- Removes the code mod with the given ID from the current game's mod list and persists the change.
--- @param modid? string
function code.DeleteMod(modid) end

--- Creates a new code mod with a unique name, uploads it, and adds it to the current game's mod list.
function code.CreateMod() end
