--- FSCILeveledChoiceImporter handles importing choices made in a Forge Steel character
--- into the complex Codex choices - when the available features are arrayed by level
--- @class FSCILeveledChoiceImporter: GameType
--- @field availableFeatures table The features available in the Codex
--- @field levelChoices table The calculated list of selected features formatted for the character
--- @field featureData table The full feature objects keyed by GUID
--- @field filter table Optional filter for feature processing (e.g., { description = "War Domain" })
FSCILeveledChoiceImporter = RegisterGameType("FSCILeveledChoiceImporter")
FSCILeveledChoiceImporter.__index = FSCILeveledChoiceImporter

local writeDebug = FSCIUtils.writeDebug
local writeLog = FSCIUtils.writeLog
local STATUS = FSCIUtils.STATUS

--- Creates a new level choice importer and processes the selected features.
--- @param availableFeatures table The list of available feature definitions
--- @param filter? table Optional filter for feature processing (e.g., { description = "War Domain" })
--- @return FSCILeveledChoiceImporter|nil instance The new importer instance if valid
function FSCILeveledChoiceImporter:new(availableFeatures, filter)

    if availableFeatures then
        if type(availableFeatures) == "table" then
            if next(availableFeatures) then
                local instance = setmetatable({}, self)
                instance.availableFeatures = availableFeatures
                instance.levelChoices = {}
                instance.featureData = {}
                instance.filter = filter or {}
                return instance
            end
        end
    end

    return nil
end

--- Processes a single selected feature to build our levelChoices structure
--- @param feature table The selected feature to import
--- @return table levelChoices The list of selected features, apped to available features
--- @return table featureData The full feature objects keyed by GUID
function FSCILeveledChoiceImporter:ProcessFeature(feature)
    writeDebug("FSCILEVELEDCHOICEIMPORTER:: PROCESSFEATURE:: FEATURE:: %s", json(feature))

    for _, level in pairs(self.availableFeatures) do
        if level.features and next(level.features) then
            writeDebug("FSCILEVELEDCHOICEIMPORTER:: PROCESSFEATURE:: LEVEL:: %s", json(level))
            local ci = FSCIChoiceImporter:new(level.features, self.filter)
            if ci then
                local choices, features = ci:ProcessFeature(feature)
                if choices then
                    FSCIUtils.MergeTables(self.levelChoices, choices)
                end
                if features then
                    FSCIUtils.MergeTables(self.featureData, features)
                end
            end
        end
    end

    return self.levelChoices, self.featureData
end

--- Updates the featureData table with new data
--- @param newFeatureData table The new feature data table to replace the current one
function FSCILeveledChoiceImporter:UpdateFeatureData(newFeatureData)
    self.featureData = newFeatureData or {}
end

--- Sets the filter for feature processing
--- @param filter? table The filter to apply (e.g., { description = "War Domain" }), or nil to clear
function FSCILeveledChoiceImporter:SetFilter(filter)
    self.filter = filter or {}
end

--- Processes all selected features to build our levelChoices structure
--- @param selectedFeatures table The selected features to import
--- @return table levelChoices The list of selected features, mapped to available features
--- @return table featureData The full feature objects keyed by GUID
function FSCILeveledChoiceImporter:Process(selectedFeatures)
    writeDebug("FSCICHOICEIMPORTER:: PROCESS:: START:: %s", json(selectedFeatures))

    for _, selectedFeature in pairs(selectedFeatures) do
        self:ProcessFeature(selectedFeature)
    end

    writeDebug("FSCICHOICEIMPORTER:: PROCESS:: COMPLETE:: %s", json(self.levelChoices))
    return self.levelChoices, self.featureData
end

--- Process selected features where the selected features are in a list by level
--- to build our levelChoices structure
--- @param leveledFeatures table A multi-level list of levels with features inside them
--- @return table levelChoices The list of selected features, mapped to available features
--- @return table featureData The full feature objects keyed by GUID
function FSCILeveledChoiceImporter:ProcessLeveled(leveledFeatures)
    writeDebug("FSCICHOICEIMPORTER:: PROCESSLEVELED:: START::")

    for _, level in pairs(leveledFeatures) do
        if level.features then
            self:Process(level.features)
        end
    end

    writeDebug("FSCICHOICEIMPORTER:: PROCESSLEVELED:: COMPLETE::")
    return self.levelChoices, self.featureData
end