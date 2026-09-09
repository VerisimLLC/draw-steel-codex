--- FSCIClassImporter handles importing class data from Forge Steel characters
--- into the Codex character system. Encapsulates all class-related import logic
--- including kits, class features, subclasses, and deity selections.
--- @class FSCIClassImporter: GameType
--- @field fsClass table The Forge Steel class data to import
--- @field character table The Codex character being built
FSCIClassImporter = RegisterGameType("FSCIClassImporter")
FSCIClassImporter.__index = FSCIClassImporter

local writeDebug = FSCIUtils.writeDebug
local writeLog = FSCIUtils.writeLog
local STATUS = FSCIUtils.STATUS
local tableLookupFromName = FSCIUtils.TableLookupFromName

--- Creates a new class importer instance with the provided class data and character.
--- @param fsClass table The Forge Steel class data to import
--- @param character table The Codex character being built
--- @return FSCIClassImporter instance The new importer instance
function FSCIClassImporter:new(fsClass, character)
    local instance = setmetatable({}, self)
    instance.fsClass = fsClass
    instance.character = character
    return instance
end

--- Imports the class data into the character. Main entry point for class import.
--- Processes class setup, kits, deity, class features, and subclasses.
function FSCIClassImporter:Import()
    writeDebug("FSCICLASSIMPORTER:: IMPORT:: START::")
    writeLog("Import Class starting.", STATUS.INFO, 1)

    if self.fsClass and self.fsClass.name and self.fsClass.level then
        local className = self.fsClass.name
        local classLevel = self.fsClass.level
        writeLog(string.format("Found Class [%s] Level [%d] in import.", className, classLevel))

        local classId, classInfo = tableLookupFromName(Class.tableName, className)
        if classId and classInfo then
            writeLog(string.format("Adding Class [%s] to character.", className), STATUS.IMPL)
            local classes = self.character:get_or_add("classes", {})
            classes[#classes + 1] = {
                classid = classId,
                level = classLevel
            }

            self:_processKits(self.fsClass.featuresByLevel)

            local classFill = {}
            classInfo:FillLevelsUpTo(classLevel, false, "nonprimary", classFill)
            writeDebug("FSCICLASSIMPORTER:: CLASSFILL:: %s", json(classFill))

            local classFillImporter = FSCILeveledChoiceImporter:new(classFill)
            if classFillImporter then
                local domainChoiceKey, domainUsesSubclass = self:_processDeity(classFillImporter)
                writeDebug("FSCICLASSIMPORTER:: DOMAINKEY:: [%s] USESUBCLASS:: [%s]", domainChoiceKey, domainUsesSubclass)

                if domainUsesSubclass then
                    self:_processDomainAsSubclass(classFillImporter, classLevel)
                else
                    self:_processSubclass(classFillImporter, classLevel)
                end
                
                self:_processClassFeatures(classFillImporter)
            end
        else
            writeLog(string.format("!!!! Class [%s] not found in Codex.", className), STATUS.WARN)
        end
    else
        writeLog("!!!! Class information not found in import!", STATUS.WARN)
    end

    writeLog("Import Class complete.", STATUS.INFO, -1)
    writeDebug("FSCICLASSIMPORTER:: IMPORT:: COMPLETE::")
end

--- Processes deity selection for the class.
--- @param classFillImporter FSCILeveledChoiceImporter The class fill importer
--- @return string|nil domainChoiceKey The key of the first item in leveledChoices, or nil if empty
--- @return boolean useSubclass The useSubclass field from the corresponding feature, or false if not present
--- @private
function FSCIClassImporter:_processDeity(classFillImporter)

    local findDeity = { type = "Deity", name = "All Domains" }
    local leveledChoices, featureData = classFillImporter:ProcessFeature(findDeity)
    FSCIUtils.MergeTables(self.character:GetLevelChoices(), leveledChoices)
    writeDebug("FSCICLASSIMPORTER:: PROCESSDEITY:: CHOICES:: %s", json(leveledChoices))
    writeDebug("FSCICLASSIMPORTER:: PROCESSDEITY:: FEATURES:: %s", json(featureData))

    -- Return the key of the first item in leveledChoices
    local domainChoiceKey = next(leveledChoices)

    -- Extract useSubclass field from the corresponding feature data
    local useSubclass = false
    if domainChoiceKey then
        if featureData and featureData[domainChoiceKey] then
            useSubclass = featureData[domainChoiceKey].useSubclass or false
        end
        if not useSubclass then
            self:_processDomains(domainChoiceKey, classFillImporter)
        end
    end

    return domainChoiceKey, useSubclass
end

--- Process domains as subclasses
--- @param classFillImporter FSCILeveledChoiceImporter The class fill importer
--- @param classLevel number The character's level
--- @private
function FSCIClassImporter:_processDomainAsSubclass(classFillImporter, classLevel)

    writeDebug("DOMAINASSUB:: START::")

    local domainCount = 0

    if self.fsClass.featuresByLevel then
        for _, levelFeature in ipairs(self.fsClass.featuresByLevel) do
            if levelFeature.features then
                for _, feature in pairs(levelFeature.features) do
                    if string.lower(feature.name) == "domain" then
                        for _, domainInfo in pairs(feature.data.selected) do
                            writeDebug("DOMAINASSUB:: DOMAIN:: %s", domainInfo.name)
                            writeLog(string.format("Domain [%s] found.", domainInfo.name))
                            local domainId, domainItem = tableLookupFromName("subclasses", domainInfo.name .. " Domain")
                            if domainId == nil then
                                writeLog(string.format("!!!! Domain [%s] not found in Codex.", domainInfo.name), STATUS.WARN)
                                break
                            end
                            
                            domainCount = domainCount + 1
                            if domainCount > 2 then
                                writeLog("Too many domains!", STATUS.WARN)
                                return
                            end
                            local searchKey = string.format("%s Domain", domainCount == 2 and "2nd" or "1st")
                            writeDebug("DOMAINASSUB:: SEARCH:: %s", searchKey)

                            domainInfo.name = domainInfo.name .. " Domain"

                            local foundLevelChoice = false
                            for _, levelDetails in ipairs(classFillImporter.availableFeatures) do
                                for _, featureInfo in ipairs(levelDetails.features) do
                                    if featureInfo.typeName == "CharacterSubclassChoice" and featureInfo.name == searchKey then
                                        writeDebug("DOMAINASSUB:: FOUND:: %s", featureInfo.guid)
                                        local lc = self.character:GetLevelChoices()
                                        if lc[featureInfo.guid] == nil then lc[featureInfo.guid] = {} end
                                        table.insert(lc[featureInfo.guid], domainItem.id)

                                        local subclassFill = {}
                                        domainItem:FillLevelsUpTo(classLevel, false, "nonprimary", subclassFill)
                                        writeDebug("ADDDOMAIN:: SUBCLASSFILL:: %s", json(subclassFill))

                                        local domainImporter = FSCILeveledChoiceImporter:new(subclassFill)
                                        if domainImporter then
                                            local levelChoices = domainImporter:ProcessLeveled(domainInfo.featuresByLevel)
                                            FSCIUtils.MergeTables(self.character:GetLevelChoices(), levelChoices)
                                        end

                                        foundLevelChoice = true
                                        break
                                    end
                                end
                                if foundLevelChoice then break end
                            end
                        end
                    end
                end
            end
        end
    end

end

--- Process domain data from the class features
--- @param domainChoiceKey string The key into which to write domains
--- @param classFillImporter FSCILeveledChoiceImporter The class fill importer
--- @private
function FSCIClassImporter:_processDomains(domainChoiceKey, classFillImporter)

    if self.fsClass.featuresByLevel then
        local domains = self:_extractDomains(self.fsClass.featuresByLevel)
        writeDebug("FSCICLASSIMPORTER:: DOMAINS:: EXTRACTED:: %s", json(domains))

        for domainName, domain in pairs(domains) do
            writeLog(string.format("Found Domain [%s] in import.", domainName))
            local domainId = tableLookupFromName(DeityDomain.tableName, domainName)
            if domainId then
                writeLog(string.format("Adding Domain [%s].", domainName), STATUS.IMPL)
                writeDebug("FSCICLASSIMPORTER:: DOMAINS:: ADDING::")
                FSCIUtils.AppendToTable(self.character:GetLevelChoices(), domainChoiceKey .. "-domains", domainId)

                if domain.featuresByLevel then
                    writeDebug("FSCICLASSIMPORTER:: DOMAINS:: FEATURESBYLEVEL:: INPUT:: %s", json(domain.featuresByLevel))
                    local filter = { name = domainName .. " Domain" }
                    classFillImporter:SetFilter(filter)
                    local leveledChoices = classFillImporter:ProcessLeveled(domain.featuresByLevel)
                    writeDebug("FSCICLASSIMPORTER:: DOMAINS:: FEATURESBYLEVEL:: RESULT:: %s", json(leveledChoices))
                    FSCIUtils.MergeTables(self.character:GetLevelChoices(), leveledChoices)
                    classFillImporter:SetFilter(nil)
                end
            end
        end
    end

end

--- Processes kit data from the class features.
--- @param featuresByLevel table The list of features that might hold kit information
--- @private
function FSCIClassImporter:_processKits(featuresByLevel)
    local kits = self:_extractKits(featuresByLevel)
    writeDebug("PROCESSKITS:: %s", json(kits))
    local kitCount = 0
    for _, kit in ipairs(kits) do
        writeLog(string.format("Kit [%s] found in import.", kit.name))
        local kitId = tableLookupFromName(Kit.tableName, kit.name)
        if kitId then
            kitCount = kitCount + 1
            local propName = "kitid"
            if kitCount > 1 then propName = propName .. kitCount end
            writeLog(string.format("Adding Kit %d [%s].", kitCount, kit.name), STATUS.IMPL)
            local k = self.character:get_or_add(propName, kitId)
            k = kitId
        else
            writeLog(string.format("!!!! Kit [%s] not found in Codex!", kit.name), STATUS.WARN)
        end
    end
end

--- Processes class features and abilities.
--- @param classFillImporter FSCILeveledChoiceImporter The class fill importer
--- @private
function FSCIClassImporter:_processClassFeatures(classFillImporter)

    if self.fsClass.featuresByLevel and self.fsClass.abilities then
        writeDebug("FSCICLASSIMPORTER:: CLASSFEATURES:: %s", json(self.fsClass.featuresByLevel))
        writeLog("Class features start.", STATUS.INFO, 1)

        local translatedFeatures = self:_translateClassAbilitySelections(self.fsClass.featuresByLevel, self.fsClass.abilities)
        writeDebug("FSCICLASSIMPORTER:: CLASSFEATURES:: TRANSLATED:: %s", json(translatedFeatures))

        local leveledChoices = classFillImporter:Process(translatedFeatures)
        FSCIUtils.MergeTables(self.character:GetLevelChoices(), leveledChoices)
        writeLog("Class features complete.", STATUS.INFO, -1)
    else
        writeLog("!!!! No Class features found in import!", STATUS.WARN)
    end

end

--- Processes subclass data if present.
--- @param classFillImporter FSCILeveledChoiceImporter The class fill importer
--- @param classLevel number The class level
--- @private
function FSCIClassImporter:_processSubclass(classFillImporter, classLevel)
    local subclassName, subclassFeaturesByLevel = self:_findSubclassName(self.fsClass.subclasses or {})

    writeDebug("FSCICLASSIMPORTER:: SUBCLASS:: %s", subclassName)
    if subclassName and #subclassName then
        local findSubclass = { type = "Subclass", name = subclassName}
        local leveledChoices = classFillImporter:ProcessFeature(findSubclass)
        FSCIUtils.MergeTables(self.character:GetLevelChoices(), leveledChoices)

        local _, subclassItem = tableLookupFromName("subclasses", subclassName)
        if subclassItem then
            local subclassFill = {}
            subclassItem:FillLevelsUpTo(classLevel, false, "nonprimary", subclassFill)
            writeDebug("FSCICLASSIMPORTER:: SUBCLASS:: FILL:: %s", json(subclassFill))
            local subclassFillImporter = FSCILeveledChoiceImporter:new(subclassFill)
            if subclassFillImporter then
                leveledChoices = subclassFillImporter:ProcessLeveled(subclassFeaturesByLevel)
                FSCIUtils.MergeTables(self.character:GetLevelChoices(), leveledChoices)
            end

            if subclassFeaturesByLevel then
                self:_processKits(subclassFeaturesByLevel)
            end
        end
    end
end

--- Finds the selected subclass name from the subclasses array.
--- @param subclasses table Array of subclass objects
--- @return string|nil subclassName The name of the selected subclass
--- @return table|nil featuresByLevel The features by level for the selected subclass
--- @private
function FSCIClassImporter:_findSubclassName(subclasses)
    for _, subclass in pairs(subclasses) do
        if subclass.selected then
            return subclass.name, subclass.featuresByLevel
        end
    end
end

--- Extracts kit names from the selected character features into a simple list of names.
--- @param featuresByLevel table Array of level objects containing features
--- @return table kits Array of kit names
--- @private
function FSCIClassImporter:_extractKits(featuresByLevel)
    local features = {}
    local featureType = "kit"

    for _, levelData in pairs(featuresByLevel) do
        if levelData.features then
            for _, feature in pairs(levelData.features) do
                if string.lower(feature.type) == featureType then
                    if feature.data and feature.data.selected then
                        for _, selectedFeature in pairs(feature.data.selected) do
                            table.insert(features, selectedFeature)
                        end
                    end
                end
            end
        end
    end

    return features
end

--- Extracts selected domains plus features by level for each
--- @param featuresByLEvel table Array of level objects containing features
--- @return table domains Array of domains with leveled features
--- @private
function FSCIClassImporter:_extractDomains(featuresByLevel)
    local domains = {}

    for _, levelData in pairs(featuresByLevel) do
        if levelData.features and #levelData.features > 0 then
           for _, feature in pairs(levelData.features) do
                if string.lower(feature.type) == "domain" then
                    if feature.data and feature.data.selected and #feature.data.selected > 0 then
                        for _, domainSelection in pairs(feature.data.selected) do
                            local domainName = domainSelection.name
                            local domainFeatures = self:_extractDomainFeatures(domainName, featuresByLevel)
                            if #domainFeatures > 0 then
                                domains[domainName] = {
                                    featuresByLevel = domainFeatures
                                }
                            end
                        end
                    end
                end
           end 
        end
    end

    return domains
end

--- Extracts domain names from the selected character features into list of leveled features.
--- @param domainName string Name of the domain for which to extract leveled features
--- @param featuresByLevel table Array of level objects containing features
--- @return table leveledFeatures Array of leveled features for the domain
--- @private
function FSCIClassImporter:_extractDomainFeatures(domainName, featuresByLevel)
    local leveledFeatures = {}
    local domainKey = "domain-" .. domainName:lower()

    for _, levelData in pairs(featuresByLevel) do
        if levelData.features and #levelData.features > 0 then
            local leveledFeature = {
                level = levelData.level,
                features = {}
            }
            for _, feature in pairs(levelData.features) do
                if string.lower(feature.type) == "domain feature" then
                    for _, selectedFeature in pairs(feature.data.selected) do
                        if selectedFeature.id and selectedFeature.id:lower():sub(1, #domainKey) == domainKey then
                            table.insert(leveledFeature.features, selectedFeature)
                        end
                    end
                end
            end
            if #leveledFeature.features > 0 then
                table.insert(leveledFeatures, leveledFeature)
            end
        end
    end

    return leveledFeatures
end

--- Translates Class Ability selections from featuresByLevel data.
--- Extracts all "Class Ability" type features and translates their selectedIDs from 
--- reference IDs to human-readable names.
--- @param featuresByLevel table Array of level objects containing features
--- @param referenceArray table Array of ability objects with id and name properties for translation
--- @return table destinationArray Array of translated Class Ability selections
--- @private
function FSCIClassImporter:_translateClassAbilitySelections(featuresByLevel, referenceArray)
    local destinationArray = {}

    for _, levelData in pairs(featuresByLevel) do
        if levelData.features then
            for _, feature in pairs(levelData.features) do
                local featureType = string.lower(feature.type)
                if featureType == "class ability" and feature.data and feature.data.selectedIDs then
                    local translatedItem = {
                        type = "ability",
                        data = {
                            selected = {}
                        }
                    }

                    for _, selectedID in pairs(feature.data.selectedIDs) do
                        for _, referenceItem in pairs(referenceArray) do
                            if referenceItem.id == selectedID then
                                table.insert(translatedItem.data.selected, {
                                    name = referenceItem.name,
                                    description = referenceItem.description
                                })
                                break
                            end
                        end
                    end

                    if #translatedItem.data.selected > 0 then
                        table.insert(destinationArray, translatedItem)
                    end
                else --if featureType == "skill choice" or featureType == "perk" then
                    table.insert(destinationArray, feature)
                end
            end
        end
    end

    return destinationArray
end
