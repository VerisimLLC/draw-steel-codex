--- @class code Provides Lua access to the code mod system, allowing listing, creating, deleting, and diffing code mods.
--- @field hasGit boolean True if Git is available on the system for code mod version control.
--- @field loadedMods string[] Returns a list of all code mod IDs currently loaded in the game, including global mods.
--- @field loadedModsLocalToGame string[] Returns a list of code mod IDs that are loaded locally for the current game only.
--- @field monitorid string The ID of the code mod currently being monitored for live changes.
--- @field logEvent LuaEvent The event that fires when a code mod log entry is added.
--- @field modifyEvent LuaEvent The event that fires when a code mod is modified.
code = {}

--- UserEditCodeDevConfig: Opens the code development configuration file in an external editor.
--- @return nil
function code.UserEditCodeDevConfig()
	-- dummy implementation for documentation purposes only
end

--- GetCodeFromMD5: Retrieves the source code text for a code file identified by its MD5 hash.
--- @param md5 string The MD5 hash of the code file.
--- @return string
function code.GetCodeFromMD5(md5)
	-- dummy implementation for documentation purposes only
end

--- GetMod: Returns a CodeModLua wrapper for the code mod with the given ID.
--- @return CodeModLua
function code.GetMod(modid)
	-- dummy implementation for documentation purposes only
end

--- LaunchExternalDiff: Launches an external diff tool to compare two code files identified by their MD5 hashes.
--- @param md5a string
--- @param md5b string
--- @return nil
function code.LaunchExternalDiff(md5a, md5b)
	-- dummy implementation for documentation purposes only
end

--- Diff: Computes a line-by-line diff between two strings. Returns a list of entries, each with optional 'common', 'a', and 'b' keys containing arrays of lines.
--- @return table[]
function code.Diff(a, b)
	-- dummy implementation for documentation purposes only
end

--- CanDeleteMod: Returns true if the given mod can be deleted from the current game.
--- @param modid string
--- @return boolean
function code.CanDeleteMod(modid)
	-- dummy implementation for documentation purposes only
end

--- DeleteMod: Removes the code mod with the given ID from the current game's mod list and persists the change.
--- @param modid string
--- @return nil
function code.DeleteMod(modid)
	-- dummy implementation for documentation purposes only
end

--- CreateMod: Creates a new code mod with a unique name, uploads it, and adds it to the current game's mod list.
--- @return nil
function code.CreateMod()
	-- dummy implementation for documentation purposes only
end
