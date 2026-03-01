--- @class i18n Provides Lua access to the translation system for managing language packs and translated strings.
--- @field translations string[] Returns a list of translation pack IDs available in the current game.
i18n = {}

--- GetStrings: Returns a list of all translatable strings collected from game assets.
--- @return string[]
function i18n.GetStrings()
	-- dummy implementation for documentation purposes only
end

--- hash: Returns the MD5 hash of the given string, used as a key for translation lookups.
--- @param str string
--- @return string
function i18n.hash(str)
	-- dummy implementation for documentation purposes only
end

--- GetTranslation: Returns the TranslationInfo for the given translation pack ID, or nil if not found.
--- @return nil|TranslationInfo
function i18n.GetTranslation(id)
	-- dummy implementation for documentation purposes only
end

--- DeleteTranslation: Deletes the translation pack with the given ID from the current game.
--- @param id string
--- @return nil
function i18n.DeleteTranslation(id)
	-- dummy implementation for documentation purposes only
end

--- CreateTranslation: Creates a new empty translation pack with default settings and uploads it to the current game.
--- @return nil
function i18n.CreateTranslation()
	-- dummy implementation for documentation purposes only
end

--- UploadTranslation: Uploads or updates a translation pack with the given ID and TranslationInfo data.
--- @param translationid string The ID of the translation pack.
--- @param translationInfo TranslationInfo The translation data to upload.
function i18n.UploadTranslation(translationid, translationInfo)
	-- dummy implementation for documentation purposes only
end

--- LanguageIDToKey: Converts a language identifier (e.g. 'en') to its corresponding translation pack key, or nil if not found.
--- @param langid string
--- @return string
function i18n.LanguageIDToKey(langid)
	-- dummy implementation for documentation purposes only
end
