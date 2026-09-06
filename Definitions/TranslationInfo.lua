---@meta

--- Represents a single translation language pack containing translated string mappings.
--- @class TranslationInfo:GameAsset
--- @field name string The display name of this translation language.
TranslationInfo = {}

--- Returns the translated string for the given source text, or nil if no translation exists.
--- @return nil|string
--- @param from? string
function TranslationInfo:GetString(from) end

--- Sets or removes the translation for the given source text. Pass nil or empty string to remove a translation.
--- @param from? string
--- @param to? string
function TranslationInfo:SetString(from, to) end
