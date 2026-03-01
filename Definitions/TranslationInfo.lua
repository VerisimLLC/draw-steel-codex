--- @class TranslationInfo:GameAsset Represents a single translation language pack containing translated string mappings.
--- @field name string The display name of this translation language.
TranslationInfo = {}

--- GetString: Returns the translated string for the given source text, or nil if no translation exists.
--- @return nil|string
function TranslationInfo:GetString(from)
	-- dummy implementation for documentation purposes only
end

--- SetString: Sets or removes the translation for the given source text. Pass nil or empty string to remove a translation.
--- @param from string
--- @param to string
--- @return nil
function TranslationInfo:SetString(from, to)
	-- dummy implementation for documentation purposes only
end
