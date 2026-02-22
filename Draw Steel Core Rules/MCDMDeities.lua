local mod = dmhub.GetModLoading()

--- @class Deity
--- @field name string
--- @field description string
--- @field tableName string

RegisterGameType("Deity")
RegisterGameType("DeityDomain")

Deity.name = "New Deity"
Deity.description = ""
Deity.group = "New Group"
Deity.domainList = {}

DeityDomain.name = "New Domain"

function Deity.CreateNew()
    return Deity.new{}
end

function DeityDomain.CreateNew()
    return DeityDomain.new{}
end

Deity.tableName = "Deities"
DeityDomain.tableName = "DeityDomains"

Commands.resetdomains = function()
    local deitiesTable = dmhub.GetTable(Deity.tableName) or {}
    local domainsTable = dmhub.GetTable(DeityDomain.tableName) or {}
    for i, deity in unhidden_pairs(deitiesTable) do
        local deityDomains = DeepCopy(deity:GetDomains())
        for id, domain in pairs(deityDomains) do
            if domain.typeName == "DeityDomain" then
                for k, v in pairs(domainsTable) do
                    print("Check::", domain.text, "->", v.name, "?")
                    if v.name == domain.text then
                        print("Domain Fixed:", deity.name, v.name, "->", k)
                        deityDomains[id] = k
                    end
                end
            end
        end
        deity.domainList = deityDomains
        dmhub.SetAndUploadTableItem(Deity.tableName, deity)
    end
end

RegisterGoblinScriptSymbol(creature, {
	name = "Deities",
	type = "set",
	desc = "The deities that this creature worships.",
	examples = {'self.Deities has "Val"'},
	calculate = function(c)
        if not c:IsHero() then
            return StringSet.new{}
        end
        local deitiesTable = GetTableCached(Deity.tableName) or {}

        local features = c:GetClassFeaturesAndChoicesWithDetails()

        local strings = {}
        for i, featureInfo in ipairs(features) do
            if featureInfo.feature.typeName == "CharacterDomainChoice" then
                local deityId = featureInfo.feature.deityId
                local deity = deitiesTable[deityId]
                if deity then
                    strings[#strings+1] = string.lower(deity.name)
                end
            end
        end
        return StringSet.new{
			strings = strings,
		}
	end,
})

RegisterGoblinScriptSymbol(creature, {
	name = "Domains",
	type = "set",
	desc = "The chosen domains of the creature's deities.",
	examples = {'self.Domains has "Nature"'},
	calculate = function(c)
        if not c:IsHero() then
            return StringSet.new{}
        end

        local features = c:GetClassFeaturesAndChoicesWithDetails()
        local subclasses = c:GetClassesAndSubClasses()

        local strings = {}
        for i, featureInfo in ipairs(features) do
            if featureInfo.feature.typeName == "CharacterDomainChoice" then
                local choices = featureInfo.feature:Choices(i, c:GetLevelChoices()[featureInfo.feature.guid] or {}, c)
                if choices ~= nil and #choices > 0 then
                    local chosen = c:GetLevelChoices()[featureInfo.feature.guid] or {}
                    for _, choice in ipairs(chosen) do
                        for _, option in ipairs(choices) do
                            if option.id == choice then
                                strings[#strings+1] = string.lower(option.text)
                            end
                        end
                    end
                end
            end
        end

        for i, classInfo in ipairs(subclasses) do
            local class = classInfo.class
            if class then
                local domainName = string.match(class.name, "^(%w+)%s+Domain")
                if domainName then
                    strings[#strings+1] = string.lower(domainName)
                end
            end
        end
        return StringSet.new{
			strings = strings,
		}
	end,
})

RegisterGoblinScriptSymbol(creature, {
	name = "Deity",
	type = "deity",
	desc = "The primary deity that this creature worships.",
	examples = {'self.Deity.Name is "Val"', 'self.Deity.Domains has "War"'},
	calculate = function(c)
        if not c:IsHero() then
            return nil
        end
        
        local deitiesTable = GetTableCached(Deity.tableName) or {}
        local features = c:GetClassFeaturesAndChoicesWithDetails()

        -- Find the first deity choice
        for i, featureInfo in ipairs(features) do
            if featureInfo.feature.typeName == "CharacterDeityChoice" then
                local choiceidList = c:GetLevelChoices()[featureInfo.feature.guid]
                if choiceidList ~= nil and #choiceidList > 0 then
                    local deityId = choiceidList[1]
                    local deity = deitiesTable[deityId]
                    if deity then
                        -- Return the raw deity table
                        return deity
                    end
                end
            end
        end
        
        return nil
	end,
})

function Deity.GetDropdownList()
    local result = {}
    local deitiesTable = dmhub.GetTable(Deity.tableName) or {}
    for k,v in unhidden_pairs(deitiesTable) do
        result[#result+1] = { id = k, text = v.name }
    end
    table.sort(result, function(a,b)
        return a.text < b.text
    end)
    return result
end

function DeityDomain.GetDropdownList()
    local result = {}
    local domainsTable = dmhub.GetTable(DeityDomain.tableName) or {}
    for k,v in unhidden_pairs(domainsTable) do
        result[#result+1] = { id = k, text = v.name }
    end
    table.sort(result, function(a,b)
        return a.text < b.text
    end)
    return result
end

function DeityDomain.GetDropdownListWithAdd(currentList)
    local allDomains = DeityDomain.GetDropdownList()
    local result = {}
    
    -- Create a lookup table of current domain IDs for fast checking
    local currentDomainIds = {}
    if currentList then
        for _, domainId in ipairs(currentList) do
            currentDomainIds[domainId] = true
        end
    end
    
    -- Add only domains that are not already in the current list
    for _, domain in ipairs(allDomains) do
        if not currentDomainIds[domain.id] then
            result[#result+1] = domain
        end
    end
        
    table.insert(result, 1, { id = "none", text = "Add Domain" })
    return result
end

function Deity.GetDomainDropdownOptions(self)
	local result = {}

    local domainsTable = dmhub.GetTable(DeityDomain.tableName) or {}
	for _,s in ipairs(Deity.GetDomains(self)) do
        local domain = domainsTable[s]
        if domain ~= nil then
            result[#result+1] = {
                id = s,
                text = domain.name,
            }
        end
	end

    table.sort(result, function(a,b)
        return a.text < b.text
    end)
	return result
end

function Deity.GetDomains(self)
    return self.domainList or {}
end

function Deity.AddDomain(self, domainId)
    -- Create a new copy of the domains list to avoid shared references
    local domains = {}
    local existingDomains = self.domainList or {}
    for i, domain in ipairs(existingDomains) do
        domains[i] = domain
    end
    
    domains[#domains+1] = domainId

    self.domainList = domains
end

function DeityDomain.CreateNew()
    return DeityDomain.new{
        id = dmhub.GenerateGuid(),
        name = "New Domain",
    }
end

function Deity.DeleteDomainById(self, id)
    local existingDomains = self.domainList or {}
    local newDomains = {}
    
    for _, domainId in ipairs(existingDomains) do
        if domainId ~= id then
            newDomains[#newDomains+1] = domainId
        end
    end

    self.domainList = newDomains
end

RegisterGameType("CharacterDeityChoice", "CharacterChoice")

CharacterDeityChoice.name = "Deity"
CharacterDeityChoice.description = "Choose a deity."
CharacterDeityChoice.domainList = {}
CharacterDeityChoice.deityId = "none"
CharacterDeityChoice.numDomains = 1
CharacterDeityChoice.useSubclass = false

function CharacterDeityChoice.Create(options)
    local result = CharacterDeityChoice.new{
        guid = dmhub.GenerateGuid(),
        allowDuplicateChoices = false,
    }

    for k,v in pairs(options or {}) do
        result[k] = v
    end

    return result
end

local g_deityEntryCache = {}
dmhub.RegisterEventHandler("refreshTable", function(keys)
    g_deityEntryCache = {}
end)
function CharacterDeityChoice:GetEntries(creature)
    if #g_deityEntryCache > 0 then return g_deityEntryCache end
    local options = {}
    local domainTable = dmhub.GetTableVisible(DeityDomain.tableName)
    for _,item in pairs(dmhub.GetTableVisible(Deity.tableName)) do
        local domains = {}
        local domainList = item:try_get("domainList", {})
        for _,key in ipairs(domainList) do
            local domain = domainTable[key]
            if domain then
                domains[#domains+1] = domain.name
            end
        end
        local description
        if #domains > 0 then
            table.sort(domains)
            description = string.format("**Domains:** %s", table.concat(domains, ", "))
        end
        local option = DeepCopy(item)
        option.lore = option:try_get("description")
        option.description = description
        option.unique = true
        options[#options+1] = option
    end
    table.sort(options, function(a,b) return a.name < b.name end)
    g_deityEntryCache = options
    return g_deityEntryCache
end

function CharacterDeityChoice:Choices(numOption, existingChoices, creature)
    return Deity.GetDropdownList()
end

local g_optCache = {}
dmhub.RegisterEventHandler("refreshTables", function(keys)
    g_optCache = {}
end)
function CharacterDeityChoice:GetOptions()
    if #g_optCache > 0 then return g_optCache end
    local options = {}

    for _,item in pairs(dmhub.GetTableVisible(Deity.tableName)) do
        options[#options+1] = {
            guid = item.id,
            name = item.name,
            unique = true
        }
    end
    table.sort(options, function(a,b) return a.name < b.name end)

    g_optCache = options
    return g_optCache
end

function CharacterDeityChoice:NumChoices(creature)
    return 1
end

function CharacterDeityChoice:GetDescription()
    return self.description
end

function CharacterDeityChoice:CanRepeat()
    return false
end

function CharacterDeityChoice:FillChoice(choices, result)
	local choiceidList = choices[self.guid]
	if choiceidList == nil then
		return
	end

    local deitiesTable = dmhub.GetTable(Deity.tableName) or {}
    local deity = deitiesTable[choiceidList[1]]

    if deity == nil then
        return
    end

    local deityFeature = CharacterFeature.Create({name = deity.name, description = deity.description or ""})
    result[#result+1] = deityFeature

    if not self:try_get("useSubclass", false) then
        local domainFeature = CharacterDomainChoice.Create({
            guid = string.format("%s-domains", self.guid),
            name = "Domain Choice", 
            options = deity:GetDomainDropdownOptions(), 
            numChoices = self.numDomains, 
            deityId = choiceidList[1]
        })
        
        domainFeature:FillChoice(choices, result)
    end
end

function CharacterDeityChoice:FillFeaturesRecursive(choices, result)
    result[#result+1] = self

    local choiceidList = choices[self.guid]
    if choiceidList == nil then
        return
    end

    local deitiesTable = dmhub.GetTable(Deity.tableName) or {}
    local deity = deitiesTable[choiceidList[1]]

    if deity == nil then
        return
    end

    local deityFeature = CharacterFeature.Create({name = deity.name, description = deity.description or ""})
    result[#result+1] = deityFeature

    if not self:try_get("useSubclass", false) then
        local domainFeature = CharacterDomainChoice.Create({
            guid = string.format("%s-domains", self.guid),
            name = "Domain Choice", 
            options = deity:GetDomainDropdownOptions(), 
            numChoices = self.numDomains, 
            deityId = choiceidList[1]
        })

        domainFeature:FillFeaturesRecursive(choices, result)
    end
end


function CharacterDeityChoice:CreateEditor(classOrRace, params)
    params = params or {}

    local resultPanel

    resultPanel = {
        width = '100%',
        height = 'auto',
        flow = 'vertical',

        gui.Panel{
            classes = {'formPanel', cond(self:try_get("useSubclass", false), "collapsed-anim")},
            gui.Label{
                classes = ('formLabel'),
                text = "Domains:",
            },
            gui.Input{
                width = 180,
                text = tonumber(self:try_get("numDomains", 1)),
                characterLimit = 2,

                change = function(element)
                    local n = math.max(1, round(tonumber(element.text) or self.numDomains))
                    self.numDomains = n
                    resultPanel:FireEvent("change")
                end,
            }
        },

        gui.Check{
            text = "Use Subclass as Domain",
            hover = gui.Tooltip("If checked, will not auto populate domain choices and instead looks for a subclass."),
            value = self:try_get("useSubclass", false),
            change = function(element)
                self.useSubclass = element.value
                local domainsPanel = resultPanel.children[1]
                domainsPanel:SetClass("collapsed-anim", element.value)
                resultPanel:FireEvent("change")
            end,
        },
    }

    for k,v in pairs(params) do
        resultPanel[k] = v
    end

    resultPanel = gui.Panel(resultPanel)

    return resultPanel

end

CharacterChoice.RegisterChoice{
    id = "deity",
    text = "Choice of a Deity",
    type = CharacterDeityChoice,
}

RegisterGameType("CharacterDomainChoice", "CharacterChoice")

CharacterDomainChoice.name = "Domain"
CharacterDomainChoice.numChoices = 1
CharacterDomainChoice.description = "Choose a domain for your deity"
CharacterDomainChoice.deityId = ""
CharacterDomainChoice.options = {}

function CharacterDomainChoice.Create(options)
    local result = CharacterDomainChoice.new{
        guid = (options and options.guid) or dmhub.GenerateGuid(), -- Use provided GUID or generate new one
        allowDuplicateChoices = false,
    }

    for k,v in pairs(options or {}) do
        result[k] = v
    end

    return result
end

function CharacterDomainChoice:Choices(numOption, existingChoices, creature)
    local result = {} 
    local domainsTable = GetTableCached(DeityDomain.tableName)

    local allDomains = {}
    for domainId, domain in unhidden_pairs(domainsTable) do
        allDomains[#allDomains+1] = {
            id = domainId,
            text = domain.name
        }
    end

    if not self.deityId then
        return allDomains
    end

    local deitiesTable = dmhub.GetTable(Deity.tableName) or {}
    local deity = deitiesTable[self.deityId]
    if not deity then
        return allDomains
    end

    
    for _, domainId in ipairs(deity:GetDomains()) do
        local domain = domainsTable[domainId]
        if domain then
            result[#result+1] = {
                id = domainId,
                text = domain.name
            }
        end
    end

    return result
end

function CharacterDomainChoice:GetEntries(creature)

    local entries = {}
    local domainsTable = dmhub.GetTableVisible(DeityDomain.tableName)

    if self:try_get("deityId") then
        local deity = dmhub.GetTableVisible(Deity.tableName)[self.deityId]
        if deity then
            for _,id in ipairs(deity:GetDomains()) do
                entries[#entries+1] = dmhub.DeepCopy(domainsTable[id])
            end
        end
    end

    if #entries == 0 then
        for _,item in pairs(domainsTable) do
            entries[#entries+1] = dmhub.DeepCopy(item)
        end
    end

    table.sort(entries, function(a,b) return a.name < b.name end)

    return entries
end

function CharacterDomainChoice:GetOptions()
    local items = self:Choices()
    local options = {}
    for i,item in ipairs(items) do
        options[i] = {
            guid = item.id,
            name = item.text,
            unique = true,
        }
    end
    table.sort(options, function(a,b) return a.name < b.name end)
    return options
end

function CharacterDomainChoice:NumChoices(creature)
    return self.numChoices or 1
end

function CharacterDomainChoice:CanRepeat()
    return false
end

function CharacterDomainChoice:GetDomainFeatures()
    if self:try_get("_tmp_domainFeatures") ~= nil then
        return self._tmp_domainFeatures
    end

    self._tmp_domainFeatures = {}

    local deitiesTable = GetTableCached(Deity.tableName)
    local domainsTable = GetTableCached(DeityDomain.tableName)
    local deity = deitiesTable[self.deityId]
    
    if deity then
        for _, deityDomain in ipairs(deity:GetDomains()) do
            local domain = domainsTable[deityDomain]
            if domain ~= nil then
                local featureCopy = CharacterFeature.Create()
                featureCopy.id = domain.id
                featureCopy.guid = domain.id
                featureCopy.name = domain.name
                featureCopy.description = deity.description or ""
                self._tmp_domainFeatures[#self._tmp_domainFeatures+1] = featureCopy
            end
        end
    end

    return self._tmp_domainFeatures
end

function CharacterDomainChoice:FillChoice(choices, result)
	local choiceidList = choices[self.guid]
	if choiceidList == nil then
		return
	end

    local domainFeatures = self:GetDomainFeatures()
    for _,choiceid in ipairs(choiceidList) do
        for _,f in ipairs(domainFeatures) do
            if f.guid == choiceid then
                f:FillChoice(choices, result)
            end
        end
    end
end

function CharacterDomainChoice:FillFeaturesRecursive(choices, result)
	result[#result+1] = self

	local choiceidList = choices[self.guid]
	if choiceidList == nil then
		return
	end

    local domainFeatures = self:GetDomainFeatures()
    for _,choiceid in ipairs(choiceidList) do
        for _,f in ipairs(domainFeatures) do
            if choiceid.guid == choiceid then
                f:FillFeaturesRecursive(choices, result)
            end
        end
    end
end

function CharacterDomainChoice:CreateEditor(classOrRace, params)
    params = params or {}

    local resultPanel

    resultPanel = gui.Panel{
        width = '100%',
        height = 'auto',
        flow = 'vertical',

        gui.Panel{
            classes = {'formPanel'},
            gui.Label{
                classes = ('formLabel'),
                text = "Choices:",
            },
            gui.Input{
                width = 180,
                text = tonumber(self:try_get("numChoices", 1)),
                characterLimit = 2,

                change = function(element)
                    local n = math.max(1, round(tonumber(element.text) or self.numChoices))
                    self.numChoices = n
                    resultPanel:FireEvent("change")
                end,
            }
        }
    }

    --[[ for k,v in pairs(params) do
        resultPanel[k] = v
    end ]]

    return resultPanel

end

CharacterChoice.RegisterChoice{
    id = "domain",
    text = "Choice of Domain",
    type = CharacterDomainChoice,
}

local helpSymbols = {
    _name = "deity",
    _sampleFields = {"name", "domains"},

    name = {
        name = "Name",
        type = "text",
        desc = "The name of the deity.",
    },

    domains = {
        name = "Domains",
        type = "set",
        desc = "The domains associated with the deity.",
        examples = {'Deity.Domains has "War"'},
    }
}

local lookupSymbols = {
    name = function(c)
        return c.name
    end,

    domains = function(c)
        local result = {}
        local domainsTable = dmhub.GetTable(DeityDomain.tableName) or {}
        local domains = c:GetDomains()
        for _, domainId in ipairs(domains) do
            local domain = domainsTable[domainId]
            if domain then
                result[#result+1] = string.lower(domain.name)
            end
        end

        return StringSet.new{
            strings = result,
        }
    end

}

Deity.lookupSymbols = lookupSymbols
Deity.helpSymbols = helpSymbols

dmhub.RegisterEventHandler("refreshTables", function(keys)
	if keys ~= nil and (not keys[CustomFieldCollection.tableName]) then
		return
	end

	local table = dmhub.GetTable(CustomFieldCollection.tableName) or {}

    local customFields = table["deities"]
	if customFields == nil then
		return
	end

	Deity.lookupSymbols = shallow_copy_table(lookupSymbols)
	Deity.helpSymbols = shallow_copy_table(helpSymbols)

	for k,v in pairs(customFields.fields) do
		local symbol = v:SymbolName()

		printf("Deity Custom Symbol: %s", symbol)

		Deity.lookupSymbols[symbol] = function(c)
			local customFields = c:try_get("customFields")
			if customFields == nil then
				return v.default
			end

			return customFields:try_get(k, v.default)
		end

		local documentation = v.documentation
		if documentation == nil or documentation == "" then
			documentation = string.format("The %s custom field", v.name)
		end
		Deity.helpSymbols[symbol] = {
			name = v.name,
			type = "number",
			desc = documentation,
		}
	end
end)
