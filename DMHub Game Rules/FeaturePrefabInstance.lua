local mod = dmhub.GetModLoading()

--One of these is an instance of a FeaturePrefab. It is like a CharacterFeatureChoice,
--but instead wraps/references a prefab which will itself be a choice and may filter
--options from it.
--- @class FeaturePrefabInstance: GameType
--- @field prefabSetGuid string Guid of the CharacterFeaturePrefabs collection containing the prefab.
--- @field prefabGuid string Guid of the specific CharacterFeature prefab within the collection.
--- A CharacterChoice-like wrapper that references a feature prefab by guid rather than embedding it inline.
FeaturePrefabInstance = RegisterGameType("FeaturePrefabInstance")

FeaturePrefabInstance.prefabSetGuid = ""
FeaturePrefabInstance.prefabGuid = ""

function FeaturePrefabInstance:GetPrefab()
    local tbl = dmhub.GetTable(CharacterFeaturePrefabs.tableName) or {}

    local set = tbl[self.prefabSetGuid]
    if set == nil then
        return nil
    end

    local classLevel = set:GetClassLevel()
    for _,feature in ipairs(classLevel.features) do
        if feature.guid == self.prefabGuid then
            return feature
        end
    end

    return nil
end