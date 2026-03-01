--- @class dmhub The main interface to dmhub.
--- @field version string The current version of the DMHub engine.
--- @field commandLineArguments string[] The command line arguments passed to the app.
--- @field systemHardwareRating number The power level of the system hardware. 1 or greater is a relatively high power system.
--- @field gameLoadingProgress number Game loading progress. nil = not loading a game. 0 = just started loading, 1 = fully loaded.
--- @field whiteLabel WhiteLabel The current 'white label' version of the engine this is. May be 'dmhub' or 'mcdm'
--- @field whiteLabelEntityName string The name of the publisher of the product the engine is running as.
--- @field whiteLabelAppName string The name of the app the engine is running as, suitable for showing to users.
--- @field nodiagonals boolean If true, the game rules are set up to have no pythagorean theorem when calculating diagonals.
--- @field betaBranch nil|string Which branch the app is opted-in to updating from. This is not relevant if the app is being updated from Steam, Itch, or similar.
--- @field GetSelectedCharacters fun(): string[]|nil A function that can be set to tell the engine which characters are currently selected. Returns a list of token ids.
--- @field GetSelectedMonster fun(): {monsterid: string, quantity: number}|string|nil A function that can be set to tell the engine which bestiary entry monster is selected. Returns a string representing the id of the bestiary entry.
--- @field GetSelectedObject fun(): string|nil A function that can be set to tell the engine which object asset id is selected in the UI.
--- @field GetSelectedTerrain fun(): string|nil A function that can be set to tell the engine which terrain asset id is selected in the UI.
--- @field GetSelectedFloor fun(): string|nil A function that can be set to tell the engine which floor asset id is selected in the UI.
--- @field GetSelectedWall fun(): string|nil A function that can be set to tell the engine which wall asset id is selected in the UI.
--- @field GetSelectedEffect fun(): string|nil A function that can be set to tell the engine which effect asset id is selected in the UI.
--- @field SelectTerrain fun(terrainid: string): nil A function that can be set to select a terrain asset by id in the UI.
--- @field SelectFloor fun(floorid: string): nil A function that can be set to select a floor asset by id in the UI.
--- @field SelectWall fun(wallid: string): nil A function that can be set to select a wall asset by id in the UI.
--- @field SelectEffect fun(effectid: string): nil A function that can be set to select an effect asset by id in the UI.
--- @field ObjectsSelected fun(objectids: string[]): nil A function that is called when objects are selected on the map, receiving a list of object ids.
--- @field GetLightingInfo fun(floorid: string): {cacheable: boolean, indoors: Color, outdoors: Color, illumination: number, shadow: {dir: Vector2, color: Color} } A function that can be set to tell the engine what the current lighting looks like. It will be called every frame to set the lighting.
--- @field ObjectEditingEnabled fun(): boolean A function that returns whether object editing mode is currently enabled in the UI.
--- @field SelectionToolEnabled fun(): boolean A function that returns whether the selection tool is currently enabled in the UI.
--- @field GetActiveClipboardItem fun(): ClipboardItem A function that returns the currently active clipboard item, if any.
--- @field TokenVisionUpdated fun(): nil A function that is called when token vision has been recalculated and updated.
--- @field GetFocus fun(): Panel|nil A function that returns the currently focused UI panel, or nil if nothing is focused.
--- @field CreateLootComponent fun(): table A function that creates a loot component table for attaching to an object.
--- @field CreateTextComponent fun(): table A function that creates a text component table for attaching to an object.
--- @field GetObjectInteractives fun(): table A function that returns the list of interactive components available for objects.
--- @field ShowObjectInteractive fun(): nil A function that is called to show the object interactive UI.
--- @field CreateObjectInteractive fun(): table A function that creates an interactive component table for attaching to an object.
--- @field CreateGameHud fun(container: SheetContainer, sheethud: SheetHud): Panel 
--- @field DataStreamed fun(eventName: string, path: string, payload: string): nil 
--- @field DataTransmitted fun(method: string, path: string, payload: string): nil 
--- @field DistanceDisplayFunction fun(distance: number): string Given a distance in the world, converts to a string ready to be displayed to the player.
--- @field RankPrimaryToken fun(creature: Creature): number|nil Given a creature, this function should return a score to reflect how likely this creature is to be a player character. It is used so if a player has control of multiple tokens, to determine which one, by default, is considered their primary character.
--- @field GetActiveWhiteboardTool fun(): { tool: string, color: Color, width: Number } A function that returns the currently active whiteboard drawing tool and its settings.
--- @field CancelEditing fun(sheet: Sheet): boolean A function that attempts to cancel editing a sheet, returning true if editing was successfully cancelled.
--- @field GetSymbolTypesDocumentation fun(typename: string): nil|{name: string, type: string, desc: string}[] A function that returns documentation for symbol types of the given type name, or nil if not found.
--- @field IsDialogOpen fun(): boolean Function that can be used to communicate to the engine whether a modal dialog is currently open.
--- @field SetTokenSize fun(token: CharacterToken, sizeid: string): nil A function that sets the size of a token to the given size id.
--- @field ShowGameContextMenu fun(entries: {text: string, tooltip: string, icon: string, click: fun(): nil}[]): nil A function that displays a context menu with the given entries when right-clicking in the game.
--- @field CreateKeyFrameComponent fun(): table A function that creates a keyframe animation component table for attaching to an object.
--- @field CreateEventHandlerComponent fun(): table A function that creates an event handler component table for attaching to an object.
--- @field CreateEventTriggerComponent fun(): table A function that creates an event trigger component table for attaching to an object.
--- @field CreateDataInputComponent fun(): table A function that creates a data input component table for attaching to an object.
--- @field CreateDataOutputComponent fun(): table A function that creates a data output component table for attaching to an object.
--- @field TokensAreFriendly fun(a: CharacterToken, b: CharacterToken): boolean A function that determines whether two tokens are considered friendly to each other.
--- @field DescribeToken fun(token: CharacterToken): string A function that returns a human-readable description of the given token.
--- @field DataError fun(message: string): nil Function which is called by the engine when a networking error occurs allowing display of a message to the user.
--- @field GetHeightEditingInfo fun(): {opacity: number, blend: number, height: number, directional: boolean} Editor callback function: Used to determine what height editing options the user has selected in the UI.
--- @field SelectHeight fun(height: number): nil Editor callback function: Used when the user uses the eyedropper tool to select a height to notify the interface what height they selected.
--- @field GetWallHeight fun(): number Editor callback function: Used to determine the height the user is currently editing walls at.
--- @field CreateTargetableComponent fun(): table A function that creates a targetable component table for attaching to an object.
--- @field CreateCorpseComponent fun(): table A function that creates a corpse component table for attaching to an object.
--- @field TokenMovingOnPath fun(args: {token: CharacterToken, path: Path, position: vector3, delta: vector3, distanceMoved: number}): nil A function that is called each frame while a token is moving along a path, receiving movement details.
--- @field GetSelectedEncounter fun(): {groups = table<string,number>[]}|nil A function that can be set to tell the engine which encounter is currently selected. The selected encounter should be deployable onto the map.
--- @field CreateAuraComponent fun(): table A function that creates an aura component to attach to an object.
--- @field ObjectDirectImport fun(string, vector3): nil A function that is called when we directly import an object.
--- @field tokensLoggedInAs nil|string[] If the GM is forcibly logged in as a token or set of tokens so they can view through their eyes, this returns a list of the token ids that the GM is logged in as.
--- @field tokenVision nil|string[] If the GM is viewing token vision this is equal to a list of the tokenids whose vision the GM is seeing through.
--- @field blockTokenSelection boolean Whether token selection via clicking is currently blocked.
--- @field tokenInfo SheetHud The SheetHud instance that displays token information in the UI.
--- @field diagnosticStatus string (read-only) The most important diagnostic message to display to the user currently, or an empty string if there is none.
--- @field status string (read-only) A general status message that describes the mouse's position in world space and information about the tile the user is pointing at, such as its terrain type and position.
--- @field uploadQuotaTotal number The amount of data this user can upload each month, in bytes.
--- @field uploadQuotaRemaining number The remaining data this user can upload this month, in bytes.
--- @field singleFileUploadQuota number The maximum size file the user can upload, in bytes.
--- @field singleFilePatreonUpgradeMessage string The message displayed to the user explaining how to upgrade their Patreon tier to get larger single-file uploads.
--- @field currentTerrainFill string|nil The terrain background the map currently has set. Nil means no background.
--- @field MapExport MapExportCameraLua The MapExport interface which allows export of a map to an image or video.
--- @field tablesUpdateId number A number which increases by 1 every time the compendium assets are updated. Can save this value and then compare to it later to see if the compendium has changed at all since we last checked.
--- @field ngameupdate integer (read-only) A sequential integer that is unique to the game being updated from the cloud. Anytime this value changes we have new data from the cloud and the game is in a different state.
--- @field gameupdateid string (read-only) A guid that is unique to the game being updated from the cloud. Anytime this value changes we have new data from the cloud and the game is in a different state.
--- @field currentRollGuid nil|string (Read-only) The guid that has been assigned to the current roll that is being previewed.
--- @field debugLog (string|{message: string, trace: string})[] All debug log messages that have been recorded.
--- @field frozen boolean If the game state is frozen. Setting this value will upload the update to the cloud immediately.
--- @field game game (read-only) the game interface.
--- @field loginUserid string The userid the user logged in with.
--- @field userid string (read-only) the userid of the current user. Note that this may be the userid the game owner is impersonating within their game. @see loginUserid to get their true id.
--- @field userDisplayName string The display name of the current user. When written to, the new display name will be sent to the cloud. Remote users will take up to a minute to reflect the new name.
--- @field unitsPerSquare number (read-only) the measurement units per square. Typically this is 5.
--- @field titleBarContainer SheetPanel A UI container suitable for containing the title bar at the top of the screen.
--- @field floorid string (read-only) the id of the current floor.
--- @field isGameOwner boolean (read-only) true if the current user has ownership privileges in the game.
--- @field isDM boolean (read-only) true if the current user has GM status in the game.
--- @field inGame boolean (read-only) true if we are currently in-game
--- @field isLobbyGame boolean (read-only) true if in lobby
--- @field gameid string (Read-only) The gameid of the current game.
--- @field editorMode boolean (Read-only) returns true if the user is doing some kind of map/game editing, rather than in normal play mode.
--- @field undoState table (Read-only) Returns a table describing the current undo/redo state for user editing actions.
--- @field connectionErrorStatus any The current connection error status, if any. Used to display connection issues to the user.
--- @field patronTier number The Patreon tier level of the current user. 0 means not a patron.
--- @field subscriptionTier number The subscription tier level of the current user. 0 means no subscription.
--- @field isAdminAccount boolean True if the current user has admin privileges on their account.
--- @field hasStoreAccess boolean (Read-only) controls whether there is a store in this version of the app.
--- @field networkLogLevel number The log level we use for networking messages. 0 = all, 1 = information, 2 = warning, 3 = error, 4 = exception, 5 = none
--- @field activeObjectsPath string The game path pattern pointing to active objects. Can be used with monitorGame on a panel to monitor for object changes.
--- @field users string[] (Read-only) A list of userids of all users in the game. You may call @see GetSessionInfo to find more information about each of them.
--- @field despawnedTokens CharacterToken[] (Read-only) A list of all tokens that are on the current map but despawned from it.
--- @field despawnedTokensCount number (Read-only) The number of despawned tokens on this map.
--- @field allTokens CharacterToken[] (Read-only) A list of all tokens active and deployed on the map.
--- @field allTokensIncludingObjects CharacterToken[] (Read-only) A list of all tokens active and deployed on the map, including object tokens.
--- @field allObjectTokens CharacterToken[] (Read-only) A list of all object tokens active and deployed on the map.
--- @field selectedTokens CharacterToken[] The list of currently selected tokens. Can be set to change the selection.
--- @field currentToken nil|CharacterToken (Read-only) the token the player is assumed to be currently controlling -- the token they have control of and is selected, or their primary character. May return nil, though it won't if the player has a PC assigned to them.
--- @field selectedOrPrimaryTokens CharacterToken[] (Read-only) a list consisting of the tokens selected, or the 'primary' token of the player if there is one. This can be used to get the token the player is presumably acting as if they perform an action. May return an empty list but does not return nil.
--- @field primaryCharacter CharacterToken|nil (Read-only) the primary character for the current player. This can be an off-map token.
--- @field tokenHovered nil|CharacterToken (Read-only) Gets the currently hovered token, or nil if there is none.
--- @field modKeys @return {ctrl: nil|boolean, alt: nil|boolean, shift: nil|boolean} Returns which mod keys are currently depressed.
--- @field mouseWheel @return number Returns a positive or negative number if the mousewheel has been moved this frame, based on the direction. Returns 0 if the mousewheel has not been moved this frame.
--- @field screenDimensions Vector2 (Read-only) The current screen dimensions in pixels as a Vector2 (width, height).
--- @field screenDimensionsBelowTitlebar Vector2 (Read-only) The screen dimensions in pixels below the title bar as a Vector2 (width, height).
--- @field uiVerticalScale number (Read-only) The vertical scale factor of the UI compared to a reference 1920x1080 resolution.
--- @field uiVerticalScaleBelowTitleBar number (Read-only) The vertical scale factor of the UI below the title bar compared to a reference 1920x1080 resolution.
--- @field uiscale number (Read-only) the amount the ui is being scaled by horizontally.
--- @field serverTime number (Read-only) The server time in seconds. Server time is designed to be the same (or at least as close as possible) across all computers connected to the game.
--- @field serverTimeMilliseconds number (Read-only) The server time in milliseconds. Server time is designed to be the same (or at least as close as possible) across all computers connected to the game.
--- @field infoBubbles table<string, InfoBubbleHudLua> (Read-only) The info bubbles available on the current map.
--- @field initiativeQueue nil|InitiativeQueue The initiative queue. Note: check to make sure it's not nil and that the hidden member isn't set to check if initiative is active.
--- @field inCharacterSheet boolean If the player is viewing their character sheet.
--- @field useParallax boolean (Read-only) if true the app is using parallax features.
--- @field parallaxRatio number The current parallax ratio the game is using.
--- @field settingsChangesRequireRestart boolean If true, some important settings have been changed so the user should be urgently prompted to restart the app.
--- @field inCoroutine boolean Returns true if we are currently running in a coroutine.
--- @field PlaceholderNil any A stand-in for nil when we want to put it in a table.
--- @field debugPropertyOutput string Engine debugging and performance information.
dmhub = {}

--- TestFunction
--- @return number
function dmhub.TestFunction()
	-- dummy implementation for documentation purposes only
end

--- RecreateTitlescreen: Recreates the title screen UI from scratch.
--- @return nil
function dmhub.RecreateTitlescreen()
	-- dummy implementation for documentation purposes only
end

--- PurgePrefs: Purges the player's app preferences. This will wipe all settings that are stored as 'preference' type settings.
--- @return nil
function dmhub.PurgePrefs()
	-- dummy implementation for documentation purposes only
end

--- SanitizeDatabaseKey: This accepts a key and returns a possibly modified version of the key that makes it suitable to store in the database. All keys of tables must be safe if we are to store them in the cloud. '.', '$', '[', ']', '#', '/' and non standard ascii characters or non-printable characters are not allowed as keys that will be stored in the cloud.
--- @param key string
--- @return string
function dmhub.SanitizeDatabaseKey(key)
	-- dummy implementation for documentation purposes only
end

--- UnloadMod: Unloads the mod with the given instance guid from the game.
--- @param instanceGuid string
--- @return nil
function dmhub.UnloadMod(instanceGuid)
	-- dummy implementation for documentation purposes only
end

--- GetTypeDocumentation: Returns documentation for all public members of the given Lua type, including names, types, and descriptions.
--- @param typeid: string The name of the type to query information about.
--- @return {name: string, type: string, documentation: string|nil, typeSignature: string|nil}[]
function dmhub.GetTypeDocumentation(typeid)
	-- dummy implementation for documentation purposes only
end

--- RegisterEventHandler: Registers an event handler for the named global event that the engine can fire. Returns a unique id that can later be passed to @see DeregisterEventHandler to deregister and stop listening for this event.
--- @param eventName string
--- @param fn fun():nil
--- @return string
function dmhub.RegisterEventHandler(eventName, fn)
	-- dummy implementation for documentation purposes only
end

--- DeregisterEventHandler: Deregisters an event handler, so that it is no longer managed by the event system.
--- @param guid string
--- @return nil
function dmhub.DeregisterEventHandler(guid)
	-- dummy implementation for documentation purposes only
end

--- FireGlobalEvent: Fires the given global event
--- @param eventid string
--- @param arg any
function dmhub.FireGlobalEvent(eventid, arg)
	-- dummy implementation for documentation purposes only
end

--- RefreshCharacterSheet: Forces the character sheet to be re-built. This can be an expensive operation and is mostly designed to be used during development if you change the code driving the character sheet. Doing this unnecessarily will cause lots of character sheet slowdowns.
--- @return nil
function dmhub.RefreshCharacterSheet()
	-- dummy implementation for documentation purposes only
end

--- GetImageInfo: Asynchronously retrieves the width and height of an image by its asset id, calling the callback with the result.
--- @param id string The image asset id to query.
--- @param callback fun(info: {width: number, height: number}|nil): nil Called with image info or nil if the image could not be loaded.
function dmhub.GetImageInfo(id, callback)
	-- dummy implementation for documentation purposes only
end

--- GetAudioSpectrum: Returns an array of numbers representing the current audio volume at each frequency. Can be used to visualize the sounds currently being emitted by the engine.
--- @return number[]
function dmhub.GetAudioSpectrum()
	-- dummy implementation for documentation purposes only
end

--- UpdateGame
--- @return nil
function dmhub.UpdateGame()
	-- dummy implementation for documentation purposes only
end

--- RebuildGameHud: This rebuilds the main user interface from scratch. It will be performance intensive and should usually only be done if we are loading and unloading mods during development.
--- @return nil
function dmhub.RebuildGameHud()
	-- dummy implementation for documentation purposes only
end

--- GetModLoading: If we are currently loading a mod, returns that mod's interface. Otherwise will return nil.
--- @return CodeModInterface
function dmhub.GetModLoading()
	-- dummy implementation for documentation purposes only
end

--- InvalidateTokenUI: This rebuilds the token ui interfaces that show over tokens. Normally only used during development.
--- @return nil
function dmhub.InvalidateTokenUI()
	-- dummy implementation for documentation purposes only
end

--- GetWorldSpacePanel: Gets a UI container suitable for putting a UI into for the given floor. panelid is a unique id you can provide for your interface name.
--- @param floorid string
--- @param panelid string
--- @return SheetContainer
function dmhub.GetWorldSpacePanel(floorid, panelid)
	-- dummy implementation for documentation purposes only
end

--- CreateObjectImporter: Creates an object importer that will handle uploading objects to the cloud. paths should specify paths to image f iles containing objects. If breakup is specified, the files will automatically be broken into sheets, otherwise an image will be treated as one object. Threshold controls the sensitivity of the breakup.
--- @param options {path: string[], threshold: number|nil, breakup: boolean|nil}
--- return ObjectImportLua
function dmhub.CreateObjectImporter(options)
	-- dummy implementation for documentation purposes only
end

--- OpenFileDialog: Opens an operating system file dialog. id should uniquely identify this 'kind' of file open operation. The folder the user navigates to will be saved and future calls to this function with the same id will begin in that folder. The open callback will be called once for each file opened. If multiFiles is true, then openFiles will be called with a list of files opened. If the user cancels the interaction without opening a file, the cancel callback will be called. Extensions should contain possible file types that may be open, it should be in a format like {'wav', 'mp3', 'ogg'}
--- @param options {id: string, extensions: string[], multiFiles: boolean, prompt: string, open: nil|(fun(path: string): nil), openFiles: nil|(fun(paths: string[]): nil), cancel: nil|(fun(): nil)}
function dmhub.OpenFileDialog(options)
	-- dummy implementation for documentation purposes only
end

--- OpenFolderDialog: Opens an operating system file dialog allowing the user to open a folder. id should uniquely identify this 'kind' of file open operation. The folder the user navigates to will be saved and future calls to this function with the same id will begin in that folder. The open callback will be called and will include the folder's path and then all files within that folder that have matching extensions. Extensions should contain possible file types that may be open, it should be in a format like {'wav', 'mp3', 'ogg'}
--- @param options {id: string, extensions: string[], prompt: string, open: nil|(fun(folderPath: string, filePaths: string[]): nil), cancel: nil|(fun(): nil)}
function dmhub.OpenFolderDialog(value)
	-- dummy implementation for documentation purposes only
end

--- ParseJsonFile: Parses a json file at the given path, returning its parsed contents. Will return nil if an error occurred.
--- @param path string The path to the file.
--- @param errorCallback nil|(fun(string): nil) A callback that will be called if there is an error parsing the file.
--- @return any
function dmhub.ParseJsonFile(path, errorCallback)
	-- dummy implementation for documentation purposes only
end

--- OpenTextFileInConnectedEditor: Opens a text file in the user's default editor and watches for changes. Returns a file watcher object, or nil if the filename is invalid.
--- @param filename string The filename to create and open.
--- @param contents string The initial contents to write to the file.
--- @param callback fun(newContents: string): nil Called when the file is modified externally.
--- @return LuaFileWatcher|nil
function dmhub.OpenTextFileInConnectedEditor(filename, contents, callback)
	-- dummy implementation for documentation purposes only
end

--- ReadTextFile: Reads a text file at the given path, returning its contents as a string. Will return nil if an error occurred.
--- @param path string The path to the file.
--- @param errorCallback nil|(fun(string): nil) A callback that will be called if there is an error parsing the file.
--- @return string|nil
function dmhub.ReadTextFile(path, errorCallback)
	-- dummy implementation for documentation purposes only
end

--- WriteTextFile: Writes a text file to the user data directory. Only .txt and .json files are allowed. Returns the full path of the written file, or nil if the write failed.
--- @param directory string
--- @param filename string
--- @param contents string
--- @return string
function dmhub.WriteTextFile(directory, filename, contents)
	-- dummy implementation for documentation purposes only
end

--- GetTextFilePaths: Returns a list of all .txt and .json file paths in the given user data subdirectory. Returns nil if the directory does not exist.
--- @param directory string The subdirectory within user data to search.
--- @return string[]|nil
function dmhub.GetTextFilePaths(directory)
	-- dummy implementation for documentation purposes only
end

--- ParseDocxFile: Parses a Word/docx file at the given path, returning its parsed contents as a string in an html-like form. Will return nil if an error occurred.
--- @param path string The path to the file.
--- @param errorCallback nil|(fun(string): nil) A callback that will be called if there is an error parsing the file.
--- @return string|nil
function dmhub.ParseDocxFile(path, errorCallback)
	-- dummy implementation for documentation purposes only
end

--- FillTerrain: Sets the terrain background of the current map. Passing in nil will clear the background.
--- @param terrainid: string|nil
function dmhub.FillTerrain(terrainid)
	-- dummy implementation for documentation purposes only
end

--- --- @class MapToolInfo--- @field tool 'free'|'objectpoints'|'forbidden' The name of the tool to use.--- @field expires number The amount of time the tool will be set to, suggested to set to 0.5 or less.--- @field closed boolean If true then the tool will be along a closed path.
--- SetMapTool: Sets the map tool that is currently being used when the user is moused over the map.
--- @param toolInfo MapToolInfo
--- @return EventSourceLua
function dmhub.SetMapTool(toolInfo)
	-- dummy implementation for documentation purposes only
end

--- SaveImageDialog: Open a system file dialog inviting the user to save a file as an image. The named texture will be saved.
--- @field options {texture: string, error: (fun(message: string): nil)}
function dmhub.SaveImageDialog(options)
	-- dummy implementation for documentation purposes only
end

--- RemoveAndUploadImageFromLibrary: Remove an image from an image library. Changes will be synced to cloud.
--- @param libraryName string
--- @param imageid string
--- @return nil
function dmhub.RemoveAndUploadImageFromLibrary(libraryName, imageid)
	-- dummy implementation for documentation purposes only
end

--- AddAndUploadImageToLibrary: Upload an image to the cloud.
--- @param libraryName string
--- @param imageid string
--- @return nil
function dmhub.AddAndUploadImageToLibrary(libraryName, imageid)
	-- dummy implementation for documentation purposes only
end

--- SearchImages: Searches available images for entries matching the given search string. If libraryName is provided, only that library is searched. Returns a list of matching image asset ids.
--- @param searchString string The string to search for.
--- @param libraryName string|nil The library to search for.
--- @return string[] A list of image id's which match the search.
function dmhub.SearchImages(searchString, libraryName)
	-- dummy implementation for documentation purposes only
end

--- SearchSounds: Searches all available audio assets for entries matching the given search string. Returns a list of matching audio asset ids.
--- @param searchString string The string to search for.
--- @return string[] A list of audio id's which match the search.
function dmhub.SearchSounds(searchString)
	-- dummy implementation for documentation purposes only
end

--- ObliterateTableItem: This deletes an item from a table. If the item was created in this game, it will be completely removed and can't be undeleted. If it is from a module it will be hidden in this game.
--- @param tableName string
--- @param id string
--- @return nil
function dmhub.ObliterateTableItem(tableName, id)
	-- dummy implementation for documentation purposes only
end

--- SetAndUploadTableItem: Sets an item in the named data table and uploads it to the cloud. Returns the id of the item. If the item has no id, a new one is generated.
--- @param tableName string The name of the table the item is in.
--- @param item table The item to upload to the table.
--- @param options nil|{ deferUpload: boolean, success: (fun():nil), failure: (fun(message: string): nil) }
--- @return string
function dmhub.SetAndUploadTableItem(tableName, item, options)
	-- dummy implementation for documentation purposes only
end

--- GetTableTypes: Get all of the data tables that have been registered. These are all the possible values that  can be passed as the tableName parameter to @see SetAndUploadTableItem and @see GetTable
--- @return string[]
function dmhub.GetTableTypes()
	-- dummy implementation for documentation purposes only
end

--- GetTable: Get the specified data table. Returns nil if the table does not exist or is empty. Note that the return table includes items that are 'hidden' -- have been deleted by the user.
--- @param tableName string
--- @return table<string, table>
function dmhub.GetTable()
	-- dummy implementation for documentation purposes only
end

--- GetTableVisible: Get the specified data table. Returns nil if the table does not exist or is empty. Excludes table items that are 'hidden'.
--- @param tableName string
--- @return table<string, table>
function dmhub.GetTableVisible(tableName)
	-- dummy implementation for documentation purposes only
end

--- ExportTable: Exports a single object table to YAML files on disk. Creates a subdirectory named after the table containing _table.yaml (the whole table) and individual .yaml files per item. Returns nil if the table does not exist.
--- @param tableName string The name of the table to export.
--- @param options nil|{ directory: string, includeHidden: boolean, individualFiles: boolean }
--- @return { itemsExported: number, directory: string }|nil
function dmhub.ExportTable(tableName, options)
	-- dummy implementation for documentation purposes only
end

--- ExportAllTables: Exports all object tables to YAML files on disk. Each table becomes a subdirectory with _table.yaml and per-item .yaml files. A _manifest.yaml is also written listing all table names.
--- @param options nil|{ directory: string, includeHidden: boolean, individualFiles: boolean }
--- @return { tablesExported: number, itemsExported: number, directory: string }
function dmhub.ExportAllTables(options)
	-- dummy implementation for documentation purposes only
end

--- ImportTable: Imports a single object table from YAML files on disk into memory. Reads _table.yaml from the table's subdirectory. Does NOT upload to the cloud -- use UploadAllTables for that. Returns nil if no import source was found.
--- @param tableName string The name of the table to import into.
--- @param options nil|{ directory: string }
--- @return { itemsImported: number, errors: string[] }|nil
function dmhub.ImportTable(tableName, options)
	-- dummy implementation for documentation purposes only
end

--- ImportAllTables: Imports all object tables from YAML files on disk into memory. Reads each subdirectory in the export directory as a table. Does NOT upload to the cloud -- use UploadAllTables for that.
--- @param options nil|{ directory: string }
--- @return { tablesImported: number, itemsImported: number, errors: string[] }
function dmhub.ImportAllTables(options)
	-- dummy implementation for documentation purposes only
end

--- UploadAllTables: Uploads all in-memory object tables to the cloud. Optionally specify a list of table names to upload; by default uploads all tables.
--- @param options nil|{ tables: string[] }
--- @return { tablesUploaded: number, itemsUploaded: number }
function dmhub.UploadAllTables(options)
	-- dummy implementation for documentation purposes only
end

--- ExportAllMonsters: Exports all bestiary monsters to YAML files on disk. Each monster becomes a separate .yaml file in the export directory, named after the monster. A _manifest.yaml listing all monsters is also written.
--- @param options nil|{ directory: string, includeHidden: boolean }
--- @return { monstersExported: number, directory: string }
function dmhub.ExportAllMonsters(options)
	-- dummy implementation for documentation purposes only
end

--- ImportAllMonsters: Imports bestiary monsters from YAML files on disk into memory. Reads _manifest.yaml to find each monster file and its original ID, then deserializes each into the in-memory bestiary. Does NOT upload to the cloud -- use UploadAllMonsters for that.
--- @param options nil|{ directory: string }
--- @return { monstersImported: number, errors: string[] }|nil
function dmhub.ImportAllMonsters(options)
	-- dummy implementation for documentation purposes only
end

--- UploadAllMonsters: Uploads all in-memory bestiary monsters to the cloud. Optionally specify a list of monster IDs to upload; by default uploads all monsters.
--- @param options nil|{ monsters: string[] }
--- @return { monstersUploaded: number }
function dmhub.UploadAllMonsters(options)
	-- dummy implementation for documentation purposes only
end

--- SearchTable: Searches items in a data table for entries whose string fields match the given search string. Returns a table of matching items, excluding hidden entries.
--- @param tableName string The name of the table
--- @param searchString the string to search for.
--- @param options {fields: string[]} Fields can specify a list of fields that will be searched, rather than searching all fields.
--- @return table<string, table>
function dmhub.SearchTable(tableName, searchString, options)
	-- dummy implementation for documentation purposes only
end

--- RunWithModuleAssets: The given function is run. While the function is running, the module provided will be the only whose assets are available to inspect.
--- @param moduleScope string The module id of the module.
--- @param fn (fun(): nil) A function to execute.
function dmhub.RunWithModuleAssets(moduleScope, fn)
	-- dummy implementation for documentation purposes only
end

--- CreateCanvasOnMap: Creates a panel on the map at the given point.
--- @param options {point: Vector3, sheet: Panel}
--- @return SheetContainer
function dmhub.CreateCanvasOnMap(options)
	-- dummy implementation for documentation purposes only
end

--- MarkRadius: Mark an area on the map. You can provide a set of locations to the center argument, and can also specify a radius if you want to expand out from those locations. Call Destroy() on the returned object when you want to destroy the marker.
--- @param radius number|nil Default=1
--- @param color Color
--- @param center Loc[]
--- @return LuaObjectReference
function dmhub.MarkRadius(table)
	-- dummy implementation for documentation purposes only
end

--- MarkLocs: Mark a set of locations on the map. Call Destroy() on the returned object when you want to destroy the marker.
--- @param color Color
--- @param locs Loc[]
--- @return LuaMultiObjectReference
function dmhub.MarkLocs(args)
	-- dummy implementation for documentation purposes only
end

--- CalculateShape: Create an object describing a shape on the map.
--- @param args {shape: SpellShapes, token: CharacterToken, objectTemplate: nil|string, targetPoint: Vector3, range: nil|number, radius: nil|number, locOverride: nil|Loc, requireEmpty: nil|boolean, checklos: nil|boolean }
--- @return LuaShape
function dmhub.CalculateShape(args)
	-- dummy implementation for documentation purposes only
end

--- RegisterRollBonusType: Registers a bonus type used with rolls, e.g. "Circumstance" for circumstance bonuses in pf2e. Once registered, dice rolls may use these identifiers as keywords to identify the type of a bonus.
--- @param name string
--- @return nil
function dmhub.RegisterRollBonusType(name)
	-- dummy implementation for documentation purposes only
end

--- ClearRollBonusTypes: Clears all roll bonus types that have been registered. This would typically be done in a module where you want to clear out the game system and start fresh.
--- @return nil
function dmhub.ClearRollBonusTypes()
	-- dummy implementation for documentation purposes only
end

--- Roll: Execute a dice roll. Returns an object that manages the roll.
--- @param rolldef RollDefinition
--- @return nil|ActiveRollLua
function dmhub.Roll(rolldef)
	-- dummy implementation for documentation purposes only
end

--- CancelCurrentRoll: Cancels out the current dice roll we are previewing. (Doesn't cancel rolls that have already begun)
--- @return nil
function dmhub.CancelCurrentRoll()
	-- dummy implementation for documentation purposes only
end

--- ParseRoll: Parses a textual roll description into a structured table suitable for passing to Roll().
--- @param text string
--- @param lookupFunction function
--- @param nil|table options
--- @return {exploding = nil|boolean, categories = table<string, {mod=number, groups={numDice=number, numFaces=number, numKeep=number,subtract=nil|boolean}[]}>}
function dmhub.ParseRoll(text, lookupFunction, options)
	-- dummy implementation for documentation purposes only
end

--- RollToString: Converts a structured roll table into a human-readable string such as '2d6 + 2 [slashing]'.
--- @param rollInfo any
--- @return string
function dmhub.RollToString(rollInfo)
	-- dummy implementation for documentation purposes only
end

--- NormalizeRoll: Normalize a roll into a standard, human-readable format.
--- @param text string The roll text.
--- @param lookupFunction nil|function
--- @param reason nil|string
--- @param options nil|table
--- @result string
function dmhub.NormalizeRoll(text, lookupFunction, reason, options)
	-- dummy implementation for documentation purposes only
end

--- GetRollAdvantage: Determines from a roll text string whether it has advantage, disadvantage, or normal rolling. Returns 'advantage', 'disadvantage', or 'normal'.
--- @param text string
--- @return string
function dmhub.GetRollAdvantage(text)
	-- dummy implementation for documentation purposes only
end

--- ForceRollAdvantage: Modifies a roll text string to force the given advantage state. advantageState should be 'advantage', 'disadvantage', or 'normal'.
--- @param text string
--- @param advantageState string
--- @return string
function dmhub.ForceRollAdvantage(text, advantageState)
	-- dummy implementation for documentation purposes only
end

--- RollExpectedValue: Returns the expected (average) value of a roll described by the given text.
--- @param text string
--- @return number
function dmhub.RollExpectedValue(text)
	-- dummy implementation for documentation purposes only
end

--- RollMinValue: Returns the minimum possible value of a roll described by the given text.
--- @param text string
--- @return number
function dmhub.RollMinValue(text)
	-- dummy implementation for documentation purposes only
end

--- RollMaxValue: Returns the maximum possible value of a roll described by the given text.
--- @param text string
--- @return number
function dmhub.RollMaxValue(text)
	-- dummy implementation for documentation purposes only
end

--- RegisterGoblinScriptDebugger: Registers a callback function to be invoked for GoblinScript debugging purposes.
--- @param callbackFunction any
--- @return nil
function dmhub.RegisterGoblinScriptDebugger(callbackFunction)
	-- dummy implementation for documentation purposes only
end

--- EvalGoblinScript: Evaluates the given goblinscript as much as possible, looking up any strings and returns the script reduced to hopefully just a dice roll or even numeric result. Always returns a string with a best effort to reduce the formula.
--- @param goblinscript string
--- @param lookupFunction function
--- @param reason string
--- @result string
function dmhub.EvalGoblinScript(goblinscript, lookupFunction, reason)
	-- dummy implementation for documentation purposes only
end

--- EvalGoblinScriptToObject: This evaluates the given goblinscript string with the support of the lookup function which can be used to lookup the value of symbols. The goblinscript should not contain any dice rolls. It will evaluate to a Lua object containing the result. It might be, for instance, a creature or an ability.
--- @param goblinscript string
--- @param lookupFunction function
--- @param reason nil|string
function dmhub.EvalGoblinScriptToObject(goblinscript, lookupFunction, reason)
	-- dummy implementation for documentation purposes only
end

--- CompileGoblinScriptDeterministic: Compiles a deterministic GoblinScript expression into a reusable Lua function for efficient repeated evaluation.
--- @param goblinscript string The GoblinScript to compile.
--- @param debugOut nil|table An optional table where debug info (lua code, errors) will be written.
--- @return function
function dmhub.CompileGoblinScriptDeterministic(goblinscript, debugOut)
	-- dummy implementation for documentation purposes only
end

--- EvalGoblinScriptDeterministic: This evaluates the given goblinscript string with the support of the lookup function which can be used to lookup the value of symbols. The goblinscript should not contain any dice rolls. It will be forced to a numeric result even if there are errors or illicit dice rolls.
--- @param goblinscript string
--- @param lookupFunction function
--- @param defaultValue nil|number
--- @param reason nil|string
function dmhub.EvalGoblinScriptDeterministic(goblinscript, lookupFunction, defaultValue, reason)
	-- dummy implementation for documentation purposes only
end

--- ExplainDeterministicGoblinScript: Evaluates a deterministic boolean GoblinScript expression and returns an explanation of each symbol's contribution using the explainFunction.
--- param goblinscript string
--- @param lookupFunction function
--- @param explainFunction fun(symbol: string, has: boolean): string
--- @return nil|(string[])
function dmhub.ExplainDeterministicGoblinScript(goblinscript, lookupFunction, explainFunction)
	-- dummy implementation for documentation purposes only
end

--- AutoCompleteGoblinScript: Given some goblin script generates possible completions for the code.
--- @param args {text: string, symbols: nil|table, deterministic: nil|boolean}
--- @return nil|({word: string, completion: string, type: string, desc: string}[])
function dmhub.AutoCompleteGoblinScript(args)
	-- dummy implementation for documentation purposes only
end

--- IsRollDeterministic: Returns true if the given formula is deterministic, not involving any actual dice rolls.
--- @param text string
--- @param lookupFunction function
--- @return boolean
function dmhub.IsRollDeterministic(text, lookupFunction)
	-- dummy implementation for documentation purposes only
end

--- RollInstant: Makes an instant roll and returns the result. The lookupFunction will be used to evaluate any GoblinScript included in the text.
--- @param text string
--- @param lookupFunction function
--- @return number
function dmhub.RollInstant(text, lookupFunction)
	-- dummy implementation for documentation purposes only
end

--- RollInstantCategorized: Make a roll with an instant result. It won't be logged or visualized. The result is returned. It will be broken into categories (though most rolls will just have one category)
--- @param text string the dice roll to make. e.g. '1d6+4'
--- @result table<string,number>
function dmhub.RollInstantCategorized(text)
	-- dummy implementation for documentation purposes only
end

--- DragDice: Call this while the user is dragging the mouse. Indicates they are dragging dice and will spawn the given dice under their mouse with them dragging them.
--- @param roll string
--- @return nil
function dmhub.DragDice(roll)
	-- dummy implementation for documentation purposes only
end

--- Debug: Log a debug message. A trace will be included with it. This is the main way to perform debug output (using the print() function calls this)
--- @param msg string
--- @return nil
function dmhub.Debug(msg)
	-- dummy implementation for documentation purposes only
end

--- CloudError: Log an error to the cloud for developers to review.
--- @param msg string
--- @return nil
function dmhub.CloudError(msg)
	-- dummy implementation for documentation purposes only
end

--- Error: Log an error message.
--- @param msg string
--- @return nil
function dmhub.Error(msg)
	-- dummy implementation for documentation purposes only
end

--- DuplicateWindowInNewProcess: Execute another instance of the app connected to the same game.
--- @param options any
--- @return nil
function dmhub.DuplicateWindowInNewProcess(options)
	-- dummy implementation for documentation purposes only
end

--- SyncCamera: Forces other user's cameras to move to this user's camera position.
--- @param options {speed: nil|number} The speed the camera should move (default=1)
function dmhub.SyncCamera(options)
	-- dummy implementation for documentation purposes only
end

--- ToRawJson: Converts a Lua value to a raw JSON string, preserving list structures.
--- @param val any
--- @return string
function dmhub.ToRawJson(val)
	-- dummy implementation for documentation purposes only
end

--- ToJson: Convert a lua value to json.
--- @param val any
--- @return string
function dmhub.ToJson(val)
	-- dummy implementation for documentation purposes only
end

--- DeepCopy: Makes a deep copy of val and returns it.
--- @param val any
--- @return any
function dmhub.DeepCopy(val)
	-- dummy implementation for documentation purposes only
end

--- DeepEqual: Performs a deep comparison on a and b and returns true if they are completely equal.
--- @param a any
--- @param b any
--- @return boolean
function dmhub.DeepEqual(a, b)
	-- dummy implementation for documentation purposes only
end

--- GetDiff: Creates a patch that is required to transfer 'a' to 'b' and returns it. Returns nil if the two values are identical.
--- @param a any
--- @param b any
--- @return any
function dmhub.GetDiff(a, b)
	-- dummy implementation for documentation purposes only
end

--- Patch: Patches the first object with the second, returning true if any changes occurred, and false otherwise.
--- @param subject any
--- @param patch any
--- @return boolean
function dmhub.Patch(subject, patch)
	-- dummy implementation for documentation purposes only
end

--- Time: The number of seconds since the app started. @see serverTime for a time that will be consistent with other users.
--- @return number
function dmhub.Time()
	-- dummy implementation for documentation purposes only
end

--- FrameCount: The number of frames the app has been running for.
--- @return number
function dmhub.FrameCount()
	-- dummy implementation for documentation purposes only
end

--- Log: Log the given message locally to the chat panel.
--- @param msg string
--- @return nil
function dmhub.Log(msg)
	-- dummy implementation for documentation purposes only
end

--- Execute: Executes the given command.
--- @param cmd string
--- @return any
function dmhub.Execute(cmd)
	-- dummy implementation for documentation purposes only
end

--- Broadcast: Broadcasts the given macro
--- @param target string
--- @param cmd string
--- @return nil
function dmhub.Broadcast(target, cmd)
	-- dummy implementation for documentation purposes only
end

--- Eval: Evaluates the given lua code.
--- @param cmd string
--- @return nil
function dmhub.Eval(cmd)
	-- dummy implementation for documentation purposes only
end

--- GetBuiltinBindings: Gets the default bindings used by the app.
--- @return table<string, {command: string, name: string, section: string, dmonly: boolean}>
function dmhub.GetBuiltinBindings()
	-- dummy implementation for documentation purposes only
end

--- GetCommandBinding: Get the keystroke that is bound to the given command. If the context is given it will only be within that context.
--- @param cmd string
--- @param context nil|string
--- @return nil|string
function dmhub.GetCommandBinding(cmd, context)
	-- dummy implementation for documentation purposes only
end

--- SetCommandBinding: Sets the given keystroke to be bound to the given command. If context is given it will only be set in the named context.
--- @param keystroke string
--- @param cmd string
--- @param context string?
--- @return nil
function dmhub.SetCommandBinding(keystroke, cmd, context)
	-- dummy implementation for documentation purposes only
end

--- DetectBindableKeystroke: If a bindable keystroke is currently depressed, returns it.
--- @return nil|string
function dmhub.DetectBindableKeystroke()
	-- dummy implementation for documentation purposes only
end

--- ResetKeybindings: Reset all keybindings to defaults.
--- @return nil
function dmhub.ResetKeybindings()
	-- dummy implementation for documentation purposes only
end

--- GetFriendsList: Gets a table full of users that the current user might be considered 'friends' with -- as in have shared a game with those users.
--- @return table<string,{games: string[], aliases: string[]}>
function dmhub.GetFriendsList()
	-- dummy implementation for documentation purposes only
end

--- UpdateScreenHudArea: After the given delay, recalculates the area of the screen that the map should be drawn in.
--- @param delay number
--- @return nil
function dmhub.UpdateScreenHudArea(delay)
	-- dummy implementation for documentation purposes only
end

--- PushUserRichStatus: Sets the 'rich status' displayed for this user. Returns a value which can be passed to @see PopUserRichStatus to remove this rich status. Any number of rich status can be set, and the most recent one that hasn't been removed will display.
--- @param statusText string
--- @param previousid nil|string If given, will pop the rich status with this id before pushing the new status.
--- @return string
function dmhub.PushUserRichStatus(statusText, previousid)
	-- dummy implementation for documentation purposes only
end

--- PopUserRichStatus: This removes the rich status message with the id previously returned from @PushUserRichStatus.
--- @param luaid nil|number
function dmhub.PopUserRichStatus(luaid)
	-- dummy implementation for documentation purposes only
end

--- GetDisplayName: Gets the display name the user has chosen for themself.
--- @param userid string
--- @return string
function dmhub.GetDisplayName(userid)
	-- dummy implementation for documentation purposes only
end

--- IsUserOwner: Check if the given user is the owner of the game.
--- @param userid string
--- @return boolean
function dmhub.IsUserOwner(userid)
	-- dummy implementation for documentation purposes only
end

--- IsUserDM: Check if the given user is a GM.
--- @param userid string
--- @return boolean
function dmhub.IsUserDM(userid)
	-- dummy implementation for documentation purposes only
end

--- SetDMStatus: Sets whether the given user is a GM. Must have correct permissions for this to succeed.
--- @param userid string
--- @param status boolean
--- @return nil
function dmhub.SetDMStatus(userid, status)
	-- dummy implementation for documentation purposes only
end

--- KickPlayer: Kicks the player with the given userid from the game. Must have permissions for this to be successful.
--- @param userid string
--- @return nil
function dmhub.KickPlayer(userid)
	-- dummy implementation for documentation purposes only
end

--- GetPartyInfo: Gets party information for the given party id.
--- @param partyid string
--- @return LuaPartyInfo
function dmhub.GetPartyInfo(partyid)
	-- dummy implementation for documentation purposes only
end

--- GetPlayerInfo: Gets game information about the player with the given userid. If beginChanges is true, notifies that we intend to modify the returned value and then will use @see UploadPlayerInfo to upload changes to the cloud.
--- @param userid string
--- @param beginChanges nil|boolean (default=false)
--- @return LuaGamePlayerDetails
function dmhub.GetPlayerInfo(userid, beginChanges)
	-- dummy implementation for documentation purposes only
end

--- UploadPlayerInfo: After calling @see GetPlayerInfo() and modifying the player info this will upload the modified data to the cloud.
--- @param userid string
--- @return nil
function dmhub.UploadPlayerInfo(userid)
	-- dummy implementation for documentation purposes only
end

--- RegisterRemoteEvent: Listens for the named eventid to be triggered, with the given callback being called when it is. @see BroadcastRemoteEvent for more details.
--- @param eventid string A unique eventid identifying the event.
--- @param callback function
function dmhub.RegisterRemoteEvent(eventid, callback)
	-- dummy implementation for documentation purposes only
end

--- BroadcastRemoteEvent: This broadcasts an event to connected computers using the peer-to-peer mechanism. Because it uses peer-to-peer there is no guarantee the messages will arrive. They should be used to communicate transient information that will go out of date quickly, such as the user's mouse position, what they are highlighting, etc. If multiple messages using the same sessionid arrive out of order, the old messages will be discarded and not processed. 
--- @param eventid string A unique eventid identifying the event.
--- @param sessionid A unique id identifying a 'session' which can receive multiple messages. If you want to broadcast multiple events concerning the same topic, use the same sessionid.
--- @param args any
function dmhub.BroadcastRemoteEvent(eventid, sessionid, args)
	-- dummy implementation for documentation purposes only
end

--- RegisterEscapePriority: Registers a named priority for escape listening. The named key is associated with the given priority level.
--- @param key string
--- @param value number
--- @return nil
function dmhub.RegisterEscapePriority(key, value)
	-- dummy implementation for documentation purposes only
end

--- GetInputForCommand: Given a command, returns a list of any hotkey presses that will trigger that command.
--- @param cmd string
--- @return string[]
function dmhub.GetInputForCommand(cmd)
	-- dummy implementation for documentation purposes only
end

--- ImportObjects: Opens the import dialog to allow the user to import objects from image files.
--- @return nil
function dmhub.ImportObjects()
	-- dummy implementation for documentation purposes only
end

--- ImportBattleMap: Opens the import dialog to allow the user to import a battle map image.
--- @return nil
function dmhub.ImportBattleMap()
	-- dummy implementation for documentation purposes only
end

--- AddObjectFolder: Adds a new object folder to the object palette and returns its id.
--- @return string
function dmhub.AddObjectFolder()
	-- dummy implementation for documentation purposes only
end

--- LeaveGame: Leaves the current game back to the titlescreen
--- @return nil
function dmhub.LeaveGame()
	-- dummy implementation for documentation purposes only
end

--- ShowPlayerSettings: Opens the player settings dialog with the given arguments.
--- @param args any
--- @return nil
function dmhub.ShowPlayerSettings(args)
	-- dummy implementation for documentation purposes only
end

--- Undo: Undo the last user editing action.
--- @return nil
function dmhub.Undo()
	-- dummy implementation for documentation purposes only
end

--- Redo: Redo the last user editing action.
--- @return nil
function dmhub.Redo()
	-- dummy implementation for documentation purposes only
end

--- ElevateToDM: Elevates the user to GM status or removes their GM status. Only works on admin accounts.
--- @param isDM any
--- @return nil
function dmhub.ElevateToDM(isDM)
	-- dummy implementation for documentation purposes only
end

--- OpenTutorialVideo: Open the tutorial video with the given id.
--- @param id string
--- @return nil
function dmhub.OpenTutorialVideo(id)
	-- dummy implementation for documentation purposes only
end

--- OpenArtistPage: Open the page for the given content creator's web page.
--- @param artist string
--- @return nil
function dmhub.OpenArtistPage(artist)
	-- dummy implementation for documentation purposes only
end

--- OpenImageAssetURL: Open the image asset with the given id in a web browser.
--- @param imageid string
--- @return nil
function dmhub.OpenImageAssetURL(imageid)
	-- dummy implementation for documentation purposes only
end

--- OpenRegisteredURL: Opens a known registered URL from the list of known url's.
--- @param urlName string
--- @return boolean
function dmhub.OpenRegisteredURL(urlName)
	-- dummy implementation for documentation purposes only
end

--- OpenURL: Open the given URL in a web browser. Only links to certain approved domains will be allowed for security reasons.
--- @param url string
--- @return nil
function dmhub.OpenURL(url)
	-- dummy implementation for documentation purposes only
end

--- OverrideMouseCursor: Forces the mouse cursor to the given mouse cursor. Lasts for 'duration' time. You may call this again and again to refresh periodically.
--- @param cursorid MouseCursor
--- @param duration number
function dmhub.OverrideMouseCursor(cursorid, duration)
	-- dummy implementation for documentation purposes only
end

--- RefreshMapLayout: Force recalculation of map layout. This does not normally need to be called, though may be used for debugging purposes if the map doesn't update after making a change.
--- @return nil
function dmhub.RefreshMapLayout()
	-- dummy implementation for documentation purposes only
end

--- GetSessionInfo: Gets session information for the given user, including connection status and ping data.
--- @param userid The userid of the user to get session info concerning.
--- @return LuaGameSession
function dmhub.GetSessionInfo()
	-- dummy implementation for documentation purposes only
end

--- PingUser: Pings a connected user to measure latency. Calls the callback with the cloud round-trip time, and optionally the peer-to-peer callback with direct connection time.
--- @param userid string The userid of the user to ping.
--- @param callback (fun(): any) The callback to call when the pong is received. This means a message will have been sent to the cloud, the cloud notified the other user, and the user responded via the cloud.
--- @param callbackPeerToPeer (fun(): any) The call when the peer-to-peer pong is received. This means a direct message was sent from this computer to the other computer. Sometimes peer-to-peer connections don't work and this may not be called.
function dmhub.PingUser(userid, callback, callbackPeerToPeer)
	-- dummy implementation for documentation purposes only
end

--- GetTokensAtLoc: Returns all tokens that are at the given location. For tokens larger than one location, it will return them if any part of them is in the location.
--- @param loc Loc
--- @return nil|CharacterToken[]
function dmhub.GetTokensAtLoc(loc)
	-- dummy implementation for documentation purposes only
end

--- GetTokens: If options is nil, this will return a list of all tokens on the map. Otherwise, will return all the tokens that meet the criteria given in the options. playerControlled = all tokens controlled by players. playerControlledNotShared = all tokens controlled by players, but doesn't include 'party controlled' tokens. haveProperties means tokens that have non-nil CharacterToken.properties. This is largely deprecated since all CharacterTokens should now have properties. unaffiliated means monsters, tokens not controlled by the players or any party. pending refers to tokens that are currently being added but may not have been transferred to the cloud yet (this state should be very brief, less than a second). If position is given, then only tokens within radius of the position will be returned. This function may return an empty list if there are no tokens that match the criteria, but it will not return nil.
--- @param options nil|{playerControlled: nil|boolean, playerControlledNotShared: nil|boolean, haveProperties: nil|boolean, unaffiliated: nil|boolean, pending: nil|boolean, position: {x: number, y: radius: radius: number}}
--- @return CharacterToken[]
function dmhub.GetTokens(options)
	-- dummy implementation for documentation purposes only
end

--- LookupToken: Given a token's Lua properties (the CharacterToken.properties member, which is most often a Creature) returns the CharacterToken if found.
--- @param properties table
--- @return nil|CharacterToken
function dmhub.LookupToken()
	-- dummy implementation for documentation purposes only
end

--- LookupTokenId: Given a token's Lua properties (the CharacterToken.properties member, which is most often a Creature) returns the tokenid of the token if found.
--- @param properties table
--- @return nil|string
function dmhub.LookupTokenId()
	-- dummy implementation for documentation purposes only
end

--- GetTokenById: Gets the token associated with the given tokenid. This only searches live tokens that are currently spawned on the map, so it will have to be on the map that is currently loaded. Otherwise nil will be returned. @see GetCharacterById to get a token anywhere in the game.
--- @param tokenid string
--- @return nil|CharacterToken
function dmhub.GetTokenById(idStr)
	-- dummy implementation for documentation purposes only
end

--- GetCharacterIdsInParty: Returns a list of all the tokenid's in the given party. Returns an empty list if the party is empty or if the party doesn't exist.
--- @param partyid string The id of the party to get token ids for.
--- @return string[]
function dmhub.GetCharacterIdsInParty(partyidStr)
	-- dummy implementation for documentation purposes only
end

--- GetAllCharacters: Returns a table of all characters in the game, keyed by their character id. Includes characters not currently on the map.
--- @return table<string, CharacterToken>
function dmhub.GetAllCharacters()
	-- dummy implementation for documentation purposes only
end

--- GetCharacterById: Gets the token associated with the given tokenid. This retrieves the token as long as it is defined anywhere in the game, it need not be spawned in the map.
--- @param tokenid string
--- @return nil|CharacterToken
function dmhub.GetCharacterById(idStr)
	-- dummy implementation for documentation purposes only
end

--- CreatureSizeToTokenScale: Converts a creature size string (e.g. 'medium', 'large') to the corresponding token visual scale.
--- @param creatureSize string
--- @return number
function dmhub.CreatureSizeToTokenScale(creatureSize)
	-- dummy implementation for documentation purposes only
end

--- Assert: Asserts that the given condition is true. Raises an error if false.
--- @param cond boolean
function dmhub.Assert(cond)
	-- dummy implementation for documentation purposes only
end

--- RegisterSetting: Registers a new setting.
--- @param info {id: string, storage: SettingStorage, default: any, enum: nil|any[], format: nil|string, invalidatesStyles: nil|boolean}
function dmhub.RegisterSetting(info)
	-- dummy implementation for documentation purposes only
end

--- HasSetting: Returns true if the given setting id exists.
--- @param settingid string
--- @return boolean
function dmhub.HasSetting(settingid)
	-- dummy implementation for documentation purposes only
end

--- GetSettingValue: Get the value of a game setting.
--- @return number
function dmhub.GetSettingValue()
	-- dummy implementation for documentation purposes only
end

--- CopyTokenToClipboard: Copies the given token to the clipboard for later pasting.
--- @param token any
--- @return nil
function dmhub.CopyTokenToClipboard(token)
	-- dummy implementation for documentation purposes only
end

--- PasteTokenFromClipboard: Pastes a token from the clipboard at the given location. Returns the token id of the pasted token, or nil if nothing was pasted.
--- @param loc nil|Loc The location to paste the token at.
--- @return nil|string
function dmhub.PasteTokenFromClipboard(loc)
	-- dummy implementation for documentation purposes only
end

--- ResetSetting: Reset the given setting to its default value.
--- @param settingid string
--- @return boolean
function dmhub.ResetSetting(settingid)
	-- dummy implementation for documentation purposes only
end

--- SetSettingValue: Sets the game setting to the given value. 
--- @param settingid string
--- @param val any
--- @param lockValue nil|boolean
function dmhub.SetSettingValue(settingid, val, lockValue)
	-- dummy implementation for documentation purposes only
end

--- PreviewSettingValue: Sets a game setting, but only locally, not transferring it yet. This is a good idea to do if e.g. the user is dragging a slider but hasn't committed to the change yet.
--- @param settingid string
--- @param val any
--- @return nil
function dmhub.PreviewSettingValue(settingid, val)
	-- dummy implementation for documentation purposes only
end

--- KeyPressed: Returns true if the given key is currently depressed.
--- @param keycode KeyCode
--- @return boolean
function dmhub.KeyPressed(keycode)
	-- dummy implementation for documentation purposes only
end

--- SetDraggingObject: Notifies the engine that an object is being dragged from the object palette. This will be cleared when the engine detects that the user releases the mouse.
--- @return nil
function dmhub.SetDraggingObject()
	-- dummy implementation for documentation purposes only
end

--- SetDraggingMonster: Notifies the engine that a monster is being dragged from the bestiary. This will be cleared when the engine detects that the user releases the mouse.
--- @return nil
function dmhub.SetDraggingMonster()
	-- dummy implementation for documentation purposes only
end

--- GenerateGuid: Generate a new guid -- a unique, random string.
--- @return string
function dmhub.GenerateGuid()
	-- dummy implementation for documentation purposes only
end

--- ScreenShake: Make the screen shake on this machine.
--- @param duration any
--- @param strength any
--- @param vibrato any
--- @param randomness any
--- @return nil
function dmhub.ScreenShake(duration, strength, vibrato, randomness)
	-- dummy implementation for documentation purposes only
end

--- FormatTimestamp: Format a timestamp as an attractive display and returns it.
--- @param timestamp number
--- @param formatstr string|nil Defaults to 'yyyy-MM-dd HH:mm:ss'
--- @return string
function dmhub.FormatTimestamp(timestamp, formatstr)
	-- dummy implementation for documentation purposes only
end

--- ViewSign: Shows the given image as a modal that fills most of the screen.
--- @param imageid string
function dmhub.ViewSign(imageid)
	-- dummy implementation for documentation purposes only
end

--- Schedule: After delay seconds elapses, fn will be executed.
--- @param delay number
--- @param fn (fun(): any)
function dmhub.Schedule(delay, fn)
	-- dummy implementation for documentation purposes only
end

--- ScheduleWhen: Arranges for predicate to be called every frame. The first time it returns true, fn is executed.
--- param predicate (fun(): boolean)
--- @param fn (fn(): any)
function dmhub.ScheduleWhen(predicate, fn)
	-- dummy implementation for documentation purposes only
end

--- CenterOnToken: Center on the token with the given id, calling the callback when complete.
--- @param tokenid string
--- @param callback (fun(): nil)
--- @return boolean
function dmhub.CenterOnToken(tokenid, args)
	-- dummy implementation for documentation purposes only
end

--- SelectToken: Select the token with the given id, clearing selection of other tokens.
--- @param charid string
--- @return nil
function dmhub.SelectToken(charid)
	-- dummy implementation for documentation purposes only
end

--- AddTokenToSelection: Add the token with the given id to the selection.
--- @param tokenid string
--- @return nil
function dmhub.AddTokenToSelection(tokenid)
	-- dummy implementation for documentation purposes only
end

--- PulseHighlightToken: Momentarily highlights the token with the given id.
--- @param tokenid string
--- @return nil
function dmhub.PulseHighlightToken(tokenid)
	-- dummy implementation for documentation purposes only
end

--- UploadInitiativeQueue: Tranmit changes to the initiative queue to the cloud.
--- @return nil
function dmhub:UploadInitiativeQueue()
	-- dummy implementation for documentation purposes only
end

--- HaveImageInClipboard: Query if there is a valid image in the system clipboard.
--- @return boolean
function dmhub.HaveImageInClipboard()
	-- dummy implementation for documentation purposes only
end

--- CopyToClipboard: Copies the given text to the system clipboard.
--- @param text string
--- @return nil
function dmhub.CopyToClipboard(text)
	-- dummy implementation for documentation purposes only
end

--- CopyToInternalClipboard: Sets the contents of the internal clipboard.
--- @param obj any
--- @return nil
function dmhub.CopyToInternalClipboard(obj)
	-- dummy implementation for documentation purposes only
end

--- GetInternalClipboard: The contents of the internal clipboard used when copying and pasting.
--- any
function dmhub.GetInternalClipboard()
	-- dummy implementation for documentation purposes only
end

--- CloseCharacterSheet: Closes the character sheet if it is currently open. Returns true if the sheet was closed, false if it was not open.
--- @return boolean
function dmhub.CloseCharacterSheet()
	-- dummy implementation for documentation purposes only
end

--- GetPlayerActionRequests: Gets all pending player action requests in the current game.
--- @return table<string, LuaPlayerActionRequest>
function dmhub.GetPlayerActionRequests()
	-- dummy implementation for documentation purposes only
end

--- GetPlayerActionRequest: Gets a specific player action request by its id. Returns nil if the request does not exist.
--- @param id string
--- @return nil|LuaPlayerActionRequest
function dmhub.GetPlayerActionRequest(id)
	-- dummy implementation for documentation purposes only
end

--- SendActionRequest: Sends a new player action request to the cloud and returns its guid. Clears any existing requests from the same requester unless the request is silent.
--- @param info table The action request details.
--- @return string
function dmhub.SendActionRequest(info)
	-- dummy implementation for documentation purposes only
end

--- CancelActionRequest: Cancels a player action request with the given id.
--- @param id any
--- @return nil
function dmhub.CancelActionRequest(id)
	-- dummy implementation for documentation purposes only
end

--- QuitApplication: Quit the application.
--- @return nil
function dmhub.QuitApplication()
	-- dummy implementation for documentation purposes only
end

--- SendRecoverPasswordEmail: Try to recover the user's password to the supplied email address.
--- @param email string
--- @return nil
function dmhub.SendRecoverPasswordEmail(email)
	-- dummy implementation for documentation purposes only
end

--- Login: Logs the user in with the supplied credentials.
--- @param username string
--- @param password string
--- @param remember boolean
--- @return nil
function dmhub.Login(username, password, remember)
	-- dummy implementation for documentation purposes only
end

--- Logout: Logs the user out.
--- @return nil
function dmhub.Logout()
	-- dummy implementation for documentation purposes only
end

--- TryAutoLogin: Attempt to automatically login using saved credentials. Returns true if we have saved credentials to login with.
--- @return boolean
function dmhub.TryAutoLogin()
	-- dummy implementation for documentation purposes only
end

--- Coroutine: Starts running 'fn' as a coroutine with the given arguments.
--- @param fn (fun(): nil)
--- @vararg args any
function dmhub.Coroutine(fn, args)
	-- dummy implementation for documentation purposes only
end

--- CoroutineSynchronous: Starts running 'fn' as a coroutine with the given arguments. If already in a coroutine it will run synchronously. If we are inside a dmhub call (e.g. CharacterToken.ModifyProperties) it will wait until the end of the execution of that call before running the coroutine code immediately after.
--- @param fn (fun(): nil)
--- @vararg args any
function dmhub.CoroutineSynchronous(fn, args)
	-- dummy implementation for documentation purposes only
end

--- Stopwatch: Creates a stopwatch object which can be used to measure time.
--- @return LuaStopwatch
function dmhub.Stopwatch()
	-- dummy implementation for documentation purposes only
end

--- ProfileMarker: Create a marker for profiling purposes.
--- @return LuaProfileMarker
function dmhub.ProfileMarker(name)
	-- dummy implementation for documentation purposes only
end

--- CreateNetworkOperation: Call this to signal an important network operation is occurring which should lock the app behind an unskippable dialog until it's complete. Set progress on the returned object to set the percentage complete. When set to 1 the operation will complete and UI disappear.
--- @return NetworkOperationStatus
function dmhub.CreateNetworkOperation()
	-- dummy implementation for documentation purposes only
end

--- ClearSelectedObjects: Clear all objects from being selected.
--- @return nil
function dmhub.ClearSelectedObjects()
	-- dummy implementation for documentation purposes only
end

--- GetCoverInfo: Given an attacker and a target, gets information about how much cover exists between them.
--- @param attacker CharacterToken
--- @param target CharacterToken
--- @return {cover: number, coverModifier: number, description: string}
function dmhub.GetCoverInfo(attacker, target)
	-- dummy implementation for documentation purposes only
end

--- GetAttackTrajectory: Given an attack with a given outcome, will calculate a good path for a missile to go from the source to the target to make an appealing animation for the user.
--- @param attacker CharacterToken
--- @param target CharacterToken
--- @param sourcePos Vector2
--- @param outcomeType AttackOutcome
--- @return {sourcePoint: Vector2, destPoint: Vector2, obstructionPoint: Vector2}
function dmhub.GetAttackTrajectory(attacker, target, sourcePos, outcomeType)
	-- dummy implementation for documentation purposes only
end

--- GetMouseWorldPoint: Get the position of the mouse in world coordinates.
--- @return Vector2
function dmhub.GetMouseWorldPoint()
	-- dummy implementation for documentation purposes only
end

--- HighlightLine: Highlights the line between a and b. Call Destroy() on the returned reference to remove the highlighted line.
--- @param options {color: nil|Color, a: Vector2, b: Vector2, floorIndex: number?}
--- @return LuaTargetingMarkers
function dmhub.HighlightLine(options)
	-- dummy implementation for documentation purposes only
end

--- MarkLineOfSight: Mark the line of sight between the attacker and target on the map. Call Destroy() on the returned reference to clear the marker.
--- @param attacker CharacterToken
--- @param target CharacterToken
--- @return LuaTargetingMarkers
function dmhub.MarkLineOfSight(attacker, target)
	-- dummy implementation for documentation purposes only
end

--- ease: Applies the given easing function to t and returns the result. Useful for animation interpolation.
--- @param t number A value between 0 and 1.
--- @param easing Easing The easing to use.
--- @return number
function dmhub.ease(t, easing)
	-- dummy implementation for documentation purposes only
end

--- HasStylus: Returns true if a stylus of some kind is available as an input device.
--- @return boolean
function dmhub.HasStylus()
	-- dummy implementation for documentation purposes only
end

--- GetDiceStyling: Query what colors a dice set uses so we can draw a UI representation of it.
--- @param diceset nil|string The dice set to query the dice styling for. Default='default'
--- @param colorStr nil|string An optional color to style the dice with, if this dice set allows dice coloring.
--- @return {trimcolor: string, bgcolor: string, color: string}
function dmhub.GetDiceStyling(diceset, colorStr)
	-- dummy implementation for documentation purposes only
end

--- BeginTransaction: When called, all network changes will be delayed until @see EndTransaction is called and then all changes will be made at once.
--- @return nil
function dmhub.BeginTransaction()
	-- dummy implementation for documentation purposes only
end

--- EndTransaction: Should be paired with a call to @see BeginTransaction. Will commit all changes since BeginTransaction was called.
--- @return nil
function dmhub.EndTransaction()
	-- dummy implementation for documentation purposes only
end

--- tr: Translates the given string using the translation system, returning the translated string. If there is no translation available or we the language is set to English, the string will be returned unaltered.
--- @param text string
--- @return string
function dmhub.tr(text, options)
	-- dummy implementation for documentation purposes only
end

--- GetPanelTrace: Returns the creation trace for the panel with the given id. Useful for debugging panel lifecycle.
--- @param panelid string
--- @return string
function dmhub.GetPanelTrace(panelid)
	-- dummy implementation for documentation purposes only
end
