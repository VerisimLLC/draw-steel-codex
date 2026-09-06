---@meta

--- Provides Lua access to the translation system for managing language packs and translated strings.
--- @class i18n
--- @field translations string[] Returns a list of translation pack IDs available in the current game.
i18n = {}

--- Returns a list of all translatable strings collected from game assets.
--- @return string[]
function i18n.GetStrings() end

--- Returns the MD5 hash of the given string, used as a key for translation lookups.
--- @param str? string
--- @return string
function i18n.hash(str) end

--- Returns the TranslationInfo for the given translation pack ID, or nil if not found.
--- @return nil|TranslationInfo
--- @param id? string
function i18n.GetTranslation(id) end

--- Deletes the translation pack with the given ID from the current game.
--- @param id? string
function i18n.DeleteTranslation(id) end

--- Creates a new empty translation pack with default settings and uploads it to the current game.
function i18n.CreateTranslation() end

--- Uploads or updates a translation pack with the given ID and TranslationInfo data.
--- @param translationid string The ID of the translation pack.
--- @param translationInfo TranslationInfo The translation data to upload.
function i18n.UploadTranslation(translationid, translationInfo) end

--- Converts a language identifier (e.g. 'en') to its corresponding translation pack key, or nil if not found.
--- @param langid? string
--- @return string
function i18n.LanguageIDToKey(langid) end
