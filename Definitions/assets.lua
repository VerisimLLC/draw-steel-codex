--- @class assets Provides access to the cloud asset library, including monsters, tilesheets, images, audio, objects, and other game assets.
--- @field coreAssetsDownloaded boolean True if core assets have been downloaded.
--- @field artists table<string, ArtistLua> Gets a table of all artists, keyed by artist ID.
--- @field devOnlyBuiltinImagesList table Gets a list of built-in UI icon images. Dev-only diagnostic property.
--- @field monstersRoot MonsterNodeLua Gets the root node of the monster tree hierarchy.
--- @field monsters table<string, MonsterAssetLua> Gets a table of all monster assets, keyed by monster ID.
--- @field monsterFolders table<string, MonsterFolderLua> Gets a table of all monster folders, keyed by folder ID.
--- @field allObjects table<string, ObjectNodeLua> Gets a table of all object nodes, keyed by object ID.
--- @field themes table<string, LuaSheetTheme> Gets a table of all sheet themes, keyed by theme ID.
--- @field brushes table<string, BrushAssetLua> Gets a table of all brush assets, keyed by brush GUID.
--- @field shopItems table<string, ShopItemLua> Gets a table of all shop items, keyed by item ID.
--- @field biomes table<string, BiomeAssetLua> Gets a table of all biome assets, keyed by biome ID.
--- @field tilesheets table<string, TilesheetAssetLua> Gets a table of all non-hidden tilesheet assets, keyed by tilesheet ID.
--- @field floors table<string, TilesheetAssetLua> Gets a table of floor tilesheets (building layer), keyed by tilesheet ID.
--- @field walls table<string, WallAssetLua> Gets a table of all non-hidden wall assets, keyed by wall ID.
--- @field weatherEffects table<string, WeatherEffectLua> Gets a table of all non-hidden weather effect assets, keyed by effect ID.
--- @field imagesTable table<string, ImageAssetLua> Gets a table of all non-hidden image assets, keyed by image ID.
--- @field imagesByTypeTable table<string, table<string, ImageAssetLua>> Gets images grouped by type, as a table of tables keyed by image type string.
--- @field imageLibrariesTable table<string, ImageLibraryAssetLua> Gets a table of all image library assets, keyed by library GUID.
--- @field emojiTable table<string, EmojiAssetLua> Gets a table of all emoji assets, keyed by emoji ID. Hidden emojis are excluded unless showdeleted setting is on.
--- @field imageAtlasTable table<string, ImageAtlasAssetLua> Gets a table of all image atlas assets, keyed by atlas ID. Hidden atlases are excluded unless showdeleted setting is on.
--- @field audioTable table<string, AudioAssetLua> Gets a table of all audio assets, keyed by audio ID.
--- @field pdfDocumentsTable table<string, PDFDocumentAssetLua> Gets a table of all PDF document assets, keyed by document ID.
--- @field clipboardTable table<string, ClipboardItem> Gets a table of all clipboard items, keyed by clipboard item ID.
--- @field clipboardFoldersTable table<string, ClipboardFolderLua> Gets a table of all clipboard folders, keyed by folder ID.
--- @field audioFoldersTable table<string, AudioFolderLua> Gets a table of non-hidden audio folders, keyed by folder ID.
--- @field audioFoldersTableIncludingDeleted table<string, AudioFolderLua> Gets a table of all audio folders including deleted ones, keyed by folder ID.
--- @field documentFoldersTable table<string, DocumentFolderLua> Gets a table of non-hidden document folders, keyed by folder ID.
--- @field objectComponentOptions table Gets a list of available object component options for use in menus.
--- @field allAssets table<string, GameAssetLua> Gets a table of all assets across all types, keyed by asset GUID.
assets = {}

--- GetMonsterNode: Gets a monster node by its ID, or nil if not found.
--- @param id string
--- @return MonsterNodeLua
function assets:GetMonsterNode(id)
	-- dummy implementation for documentation purposes only
end

--- AddAndUploadArtist: Creates and uploads a new artist entry with the given ID.
--- @param id string The artist ID.
function assets:AddAndUploadArtist(id)
	-- dummy implementation for documentation purposes only
end

--- UploadNewMonsterFolder: Creates and uploads a new monster folder from the given table arguments.
--- @param tableArgs table The folder properties.
function assets:UploadNewMonsterFolder(tableArgs)
	-- dummy implementation for documentation purposes only
end

--- UploadNewClipboardFolder: Creates and uploads a new clipboard folder from the given table arguments.
--- @param tableArgs table The folder properties.
function assets:UploadNewClipboardFolder(tableArgs)
	-- dummy implementation for documentation purposes only
end

--- UploadNewAudioFolder: Creates and uploads a new audio folder from the given table arguments.
--- @param tableArgs table The folder properties.
function assets:UploadNewAudioFolder(tableArgs)
	-- dummy implementation for documentation purposes only
end

--- GetObjectNode: Gets an object node by its ID, or nil if not found.
--- @param id string The object ID.
--- @return nil|ObjectNodeLua
function assets:GetObjectNode(id)
	-- dummy implementation for documentation purposes only
end

--- GetObjectsWithKeyword: Gets a list of object nodes matching the given keyword.
--- @param keyword string The keyword to search for.
--- @return ObjectNodeLua[]
function assets:GetObjectsWithKeyword(keyword)
	-- dummy implementation for documentation purposes only
end

--- UploadNewObjectFolder: Creates and uploads a new object folder from the given table arguments.
--- @param tableArgs table The folder properties.
function assets:UploadNewObjectFolder(tableArgs)
	-- dummy implementation for documentation purposes only
end

--- UploadNewObject: Creates and uploads a new object from a Lua table and returns its GUID.
--- @param args table The object properties.
--- @return string
function assets:UploadNewObject(args)
	-- dummy implementation for documentation purposes only
end

--- CreateBrush: Creates a new brush asset with default settings and returns it.
--- @return BrushAssetLua
function assets:CreateBrush()
	-- dummy implementation for documentation purposes only
end

--- CreateLocalShopItem: Creates a local shop item. The item is not valid until uploaded.
--- @return ShopItemLua
function assets.CreateLocalShopItem()
	-- dummy implementation for documentation purposes only
end

--- CreateNewImageLibrary: Creates and uploads a new image library, returning its GUID.
--- @param options nil|table Optional settings including name, docsourceid, and images.
function assets:CreateNewImageLibrary(options)
	-- dummy implementation for documentation purposes only
end

--- FindEmojiByIdOrName: Finds an emoji asset by its ID or name, optionally filtering by emoji type. Returns nil if not found.
--- @param name string The emoji ID or display name.
--- @param emojiType string The emoji type filter, or nil for any type.
--- @return nil|EmojiAssetLua
function assets:FindEmojiByIdOrName(name, emojiType)
	-- dummy implementation for documentation purposes only
end

--- UploadEmojiAsset: Uploads a new emoji asset from a file path. Options include path, emojiType, error callback, and upload callback.
--- @param options table Upload options with path, emojiType, error, and upload fields.
--- @return nil|string The GUID of the uploaded emoji, or nil on failure.
function assets:UploadEmojiAsset(options)
	-- dummy implementation for documentation purposes only
end

--- UploadImageAtlasAsset: Uploads a new image atlas asset from a file path. Options include path, error callback, and upload callback.
--- @param options table Upload options with path, error, and upload fields.
--- @return nil|string The GUID of the uploaded atlas, or nil on failure.
function assets:UploadImageAtlasAsset(options)
	-- dummy implementation for documentation purposes only
end

--- UploadPDFDocumentAsset: Uploads a PDF document from a file path. Options include path, guid, parentFolder, description, error, progress, and upload callbacks.
--- @param options table Upload options.
--- @return string The GUID of the uploaded document.
function assets.UploadPDFDocumentAsset(options)
	-- dummy implementation for documentation purposes only
end

--- UploadNewDocumentFolder: Creates and uploads a new document folder from the given table arguments.
--- @param tableArgs table The folder properties.
function assets:UploadNewDocumentFolder(tableArgs)
	-- dummy implementation for documentation purposes only
end

--- UploadAudioAsset: Uploads an audio file. Automatically converts FLAC files to MP3. Options include path, guid, parentFolder, description, error, progress, and upload callbacks.
--- @param options table Upload options.
--- @return nil|string The GUID of the uploaded audio asset, or nil on failure.
function assets:UploadAudioAsset(options)
	-- dummy implementation for documentation purposes only
end

--- UploadClipboardAsset: Uploads a clipboard image asset. Options include item (ClipboardItem), path, error, and upload callbacks.
--- @param options table Upload options.
--- @return nil|string The GUID of the uploaded clipboard asset, or nil on failure.
function assets:UploadClipboardAsset(options)
	-- dummy implementation for documentation purposes only
end

--- UploadImageAsset: Uploads a generic image asset. Options include path, description, parentFolder, imageType, ord, error, and upload callbacks.
--- @param options table Upload options.
--- @return nil|string The GUID of the uploaded image, or nil on failure.
function assets:UploadImageAsset(options)
	-- dummy implementation for documentation purposes only
end

--- PathSizeInBytes: Returns the file size in bytes for the given file path.
--- @param path string
--- @return number
function assets.PathSizeInBytes(path)
	-- dummy implementation for documentation purposes only
end

--- CreateWallAssetFromFile: Creates a wall asset from an image file. Wall textures must be multiples of 64px high and 128px wide.
--- @param options table Upload options with path, error, and upload fields.
--- @return nil|string The GUID of the created wall, or nil on failure.
function assets:CreateWallAssetFromFile(options)
	-- dummy implementation for documentation purposes only
end

--- CreateTilesheetFromFile: Creates a tilesheet asset from an image file. Options include floor, effects, path, args, error, and upload callback.
--- @param options table Upload options.
--- @return nil|string The GUID of the created tilesheet, or nil on failure.
function assets:CreateTilesheetFromFile(options)
	-- dummy implementation for documentation purposes only
end

--- CreateWeatherEffectFromFile: Creates a weather effect asset from an image or video file.
--- @param options table Upload options with path, error, and upload fields.
--- @return nil|string The GUID of the created weather effect, or nil on failure.
function assets:CreateWeatherEffectFromFile(options)
	-- dummy implementation for documentation purposes only
end

--- DuplicateTilesheet: Duplicates a tilesheet asset and returns the new GUID. Returns nil if the source is not found.
--- @param tileid string|number The tilesheet ID to duplicate.
--- @return nil|string
function assets:DuplicateTilesheet(tileid)
	-- dummy implementation for documentation purposes only
end

--- DuplicateWall: Duplicates a wall asset and returns the new GUID. Returns nil if the source is not found.
--- @param wallid string|number The wall ID to duplicate.
--- @return nil|string
function assets:DuplicateWall(wallid)
	-- dummy implementation for documentation purposes only
end

--- ImportUniversalVTT: Imports one or more Universal VTT map files, uploading their images and creating map objects.
--- @param pathsList string[] List of file paths to UVTT files.
--- @param callback function Called on success with info table containing objids, width, height, and uvttData.
--- @param error function Called on error with an error message string.
function assets:ImportUniversalVTT(pathsList, callback, error)
	-- dummy implementation for documentation purposes only
end

--- CreateBestiaryEntry: Creates a new bestiary entry locally and returns its GUID.
--- @return string
function assets:CreateBestiaryEntry()
	-- dummy implementation for documentation purposes only
end

--- CreateBestiaryFolder: Creates a new bestiary folder locally and returns its GUID.
--- @param name string|number The folder name.
--- @return string
function assets:CreateBestiaryFolder(name)
	-- dummy implementation for documentation purposes only
end

--- CreateAudioFolder: Creates a new audio folder locally and returns its GUID.
--- @param name string|number The folder name.
--- @return string
function assets:CreateAudioFolder(name)
	-- dummy implementation for documentation purposes only
end

--- RefreshAssets: Forces a refresh of asset data. Optionally pass a category string to refresh only that category.
--- @param cat nil|string Optional asset category to refresh.
function assets:RefreshAssets(cat)
	-- dummy implementation for documentation purposes only
end

--- LoadImageOrVideoFileLocally: Loads an image or video file into a local cache without uploading. Pass 'CLIPBOARD' to load from system clipboard.
--- @param path string The file path or 'CLIPBOARD'.
--- @return nil|LocalImageOrVideoFileLua
function assets:LoadImageOrVideoFileLocally(path)
	-- dummy implementation for documentation purposes only
end
